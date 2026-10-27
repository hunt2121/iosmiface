// SPDX-License-Identifier: MIT
package com.bandface.kit

import kotlinx.coroutines.delay

sealed class InstallPhase {
    object Connecting : InstallPhase()
    object Authenticating : InstallPhase()
    object RequestingInstall : InstallPhase()
    object RemovingOldVersion : InstallPhase()
    data class Uploading(val sent: Int, val total: Int) : InstallPhase()
    object Activating : InstallPhase()
    object Closing : InstallPhase()
    data class Done(val alreadyInstalled: Boolean) : InstallPhase()
}

/**
 * Повний сценарій: відкриття сесії → автентифікація → 2/2, 2/1 → 4/4 → 22/0 → файл → закриття.
 * Прийнявши файл, браслет сам вмикає циферблат і повідомляє 4/5.
 */
class WatchfaceInstaller {
    var phoneModel = "Android"
    var region = "UK"
    var phoneInfo: ByteArray? = null
    var commandsAfterAuth: List<ByteArray> = emptyList()
    var pauseAfterAuthMs = 500L
    var pauseBeforeInstallMs = 300L
    var waitForInstallStatusMs = 1500L
    var activationTimeoutMs = 4000L
    var activationAttempts = 2

    private enum class Check { NEEDS_UPLOAD, ALREADY_INSTALLED, ALREADY_ACTIVE }

    suspend fun install(face: FaceFile, authKey: ByteArray, session: BandSession, onPhase: (InstallPhase) -> Unit = {}) {
        onPhase(InstallPhase.Connecting)
        session.open()
        try {
            onPhase(InstallPhase.Authenticating)
            session.authenticate(authKey, phoneModel, region, phoneInfo)
            for (body in commandsAfterAuth) runCatching { session.command(body, 3000) }

            delay(pauseAfterAuthMs)
            runCatching { session.command(Command.deviceInfoRequest()) }
            runCatching { session.command(Command.batteryRequest()) }
            delay(pauseBeforeInstallMs)

            val check = requestInstall(face, session, onPhase)
            when (check) {
                Check.NEEDS_UPLOAD -> {
                    upload(face, session, onPhase)
                    confirmInstalled(session)
                }
                Check.ALREADY_INSTALLED -> {
                    onPhase(InstallPhase.Activating)
                    activate(face, session)
                }
                Check.ALREADY_ACTIVE -> Unit
            }
            onPhase(InstallPhase.Closing)
            session.close()
            onPhase(InstallPhase.Done(check != Check.NEEDS_UPLOAD))
        } catch (e: Throwable) {
            session.close()
            throw e
        }
    }

    private suspend fun requestInstall(face: FaceFile, session: BandSession, onPhase: (InstallPhase) -> Unit): Check {
        onPhase(InstallPhase.RequestingInstall)
        var removedOld = false
        while (true) {
            val response = session.command(Command.installRequest(face.id, face.size))
            val status = response.root.varint(listOf(6, 5)) ?: 0L
            when (status) {
                0L -> return Check.NEEDS_UPLOAD
                2L -> return Check.ALREADY_INSTALLED
                else -> {
                    if (removedOld) throw BandError(ErrorKind.INSTALL_REJECTED, status = status)
                    val list = WatchfaceEntry.list(session.command(Command.watchfaceListRequest()))
                    val old = list.firstOrNull { it.id == face.id } ?: throw BandError(ErrorKind.INSTALL_REJECTED, status = status)
                    if (old.isActive) return Check.ALREADY_ACTIVE
                    if (!old.canDelete) throw BandError(ErrorKind.INSTALL_REJECTED, status = status)
                    onPhase(InstallPhase.RemovingOldVersion)
                    session.command(Command.deleteWatchface(face.id))
                    removedOld = true
                }
            }
        }
    }

    private suspend fun confirmInstalled(session: BandSession) {
        session.waitFor(Command.WATCHFACE, 5, waitForInstallStatusMs)
        val status = session.installStatus
        if (status != null && status != BandSession.INSTALLED_STATUS) throw BandError(ErrorKind.INSTALL_ABORTED, status = status)
    }

    private suspend fun activate(face: FaceFile, session: BandSession) {
        for (attempt in 1..maxOf(activationAttempts, 1)) {
            try {
                val response = session.command(Command.activateWatchface(face.id), activationTimeoutMs)
                val result = response.root.varint(listOf(6, 4))
                if (result != null && result != 1L) throw BandError(ErrorKind.ACTIVATION_FAILED)
                return
            } catch (e: BandError) {
                if (e.kind == ErrorKind.TIMEOUT && attempt < activationAttempts) continue
                throw e
            }
        }
    }

    private suspend fun upload(face: FaceFile, session: BandSession, onPhase: (InstallPhase) -> Unit) {
        val md5 = face.md5
        val response = UploadResponse(session.command(Command.uploadRequest(md5, face.size)))
        if (response.status != 0L) throw BandError(ErrorKind.UPLOAD_REJECTED, status = response.status)
        if (response.chunkSize <= 4) throw BandError(ErrorKind.MALFORMED_RESPONSE, "chunk size ${response.chunkSize}")
        val parts = FileTransfer.parts(face.data, md5, response.resumePosition, response.chunkSize)
        onPhase(InstallPhase.Uploading(0, parts.size))
        session.sendFileParts(parts) { sent, total -> onPhase(InstallPhase.Uploading(sent, total)) }
    }
}
