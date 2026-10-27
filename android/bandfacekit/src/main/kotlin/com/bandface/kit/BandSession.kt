// SPDX-License-Identifier: MIT
package com.bandface.kit

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.cancel
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.withTimeoutOrNull
import java.security.SecureRandom

/** Транспорт, що доставляє цілі кадри до браслета (сам ріже їх на пакети BLE). */
interface BandTransport {
    suspend fun write(frame: ByteArray)
}

class SessionConfig {
    var sessionOpenTimeoutMs = 4000L
    var sessionOpenAttempts = 2
    /** TLV параметри відкриття; null — стандартні. */
    var openParameters: List<Pair<Int, ByteArray>>? = null
    var fileWindow = 12
    var fileAckTimeoutMs = 3000L
    var fileResendAttempts = 3
    var onOtherApp: ((String) -> Unit)? = null
    var sessionCloseTimeoutMs = 1000L
    var commandTimeoutMs = 10_000L
    var log: ((String) -> Unit)? = null
}

enum class SessionState { IDLE, OPENING, OPEN, AUTHENTICATED, CLOSED }

@OptIn(ExperimentalCoroutinesApi::class)
class BandSession(private val transport: BandTransport, val config: SessionConfig = SessionConfig()) {
    private class Waiter(val matches: (Command) -> Boolean, val result: CompletableDeferred<Command>)
    private class SentFrame(val sequence: Int, val bytes: ByteArray)

    private val dispatcher = Dispatchers.Default.limitedParallelism(1)
    private val scope = CoroutineScope(SupervisorJob() + dispatcher)
    private val input = Channel<ByteArray>(Channel.UNLIMITED)
    private val ackSignal = Channel<Unit>(Channel.CONFLATED)
    private val random = SecureRandom()

    var state = SessionState.IDLE
        private set
    var installStatus: Long? = null
        private set

    private val parser = FrameParser()
    private var phoneSequence = 0
    private var expectedBandSequence: Int? = null
    private var keys: SessionKeys? = null
    private val unacked = ArrayList<SentFrame>()
    private val unsolicitedSeen = HashSet<String>()
    private val waiters = ArrayList<Waiter>()
    private val eventWaiters = ArrayList<Pair<String, CompletableDeferred<Boolean>>>()
    private var sessionWaiter: Pair<Int, CompletableDeferred<SessionControl>>? = null
    private var otherAppReported = false

    init {
        scope.launch {
            for (chunk in input) process(chunk)
        }
    }

    /** Передайте сюди кожне сповіщення з характеристики 0x5E — у порядку надходження. */
    fun receive(data: ByteArray) {
        input.trySend(data)
    }

    /** Звільняє ресурси. Викликайте після завершення роботи з сесією. */
    fun dispose() {
        input.close()
        scope.cancel()
    }

    private fun log(message: () -> String) {
        config.log?.invoke(message())
    }

    private fun noteOtherApp(reason: String) {
        log { "other app on the band: $reason" }
        if (otherAppReported) return
        otherAppReported = true
        config.onOtherApp?.invoke(reason)
    }

    // region Сесія

    suspend fun open() = withContext(dispatcher) {
        state = SessionState.OPENING
        repeat(maxOf(config.sessionOpenAttempts, 1)) {
            resetCounters()
            val control = config.openParameters?.let { SessionControl(SessionControl.OPEN_REQUEST, it) }
                ?: SessionControl.defaultOpen
            try {
                sessionExchange(control, SessionControl.OPEN_RESPONSE, config.sessionOpenTimeoutMs)
                state = SessionState.OPEN
                log { "session: open" }
                return@withContext
            } catch (e: BandError) {
                if (e.kind != ErrorKind.TIMEOUT) throw e
            }
        }
        state = SessionState.IDLE
        throw BandError(ErrorKind.SESSION_OPEN_FAILED)
    }

    suspend fun close() = withContext(dispatcher) {
        failAllWaiters(BandError(ErrorKind.CANCELLED))
        if (state == SessionState.OPEN || state == SessionState.AUTHENTICATED || state == SessionState.OPENING) {
            try {
                sessionExchange(SessionControl.close, SessionControl.CLOSE_RESPONSE, config.sessionCloseTimeoutMs)
            } catch (_: Exception) {
            }
        }
        keys = null
        state = SessionState.CLOSED
        log { "session: closed" }
    }

    /** Викликайте, коли BLE-з'єднання розірвалося. */
    fun connectionLost() {
        scope.launch {
            failAllWaiters(BandError(ErrorKind.DISCONNECTED))
            for ((_, d) in eventWaiters) d.complete(false)
            eventWaiters.clear()
            sessionWaiter?.second?.completeExceptionally(BandError(ErrorKind.DISCONNECTED))
            sessionWaiter = null
            ackSignal.trySend(Unit)
            keys = null
            state = SessionState.CLOSED
        }
    }

    private fun resetCounters() {
        parser.reset()
        unacked.clear()
        phoneSequence = 0
        expectedBandSequence = null
        keys = null
    }

    private suspend fun sessionExchange(control: SessionControl, code: Int, timeoutMs: Long): SessionControl {
        sessionWaiter?.second?.completeExceptionally(BandError(ErrorKind.CANCELLED))
        val deferred = CompletableDeferred<SessionControl>()
        sessionWaiter = code to deferred
        try {
            transport.write(Frame(FrameType.SESSION, 0, control.payload).encoded())
            return withTimeout(timeoutMs) { deferred.await() }
        } catch (e: TimeoutCancellationException) {
            throw BandError(ErrorKind.TIMEOUT)
        } finally {
            if (sessionWaiter?.second === deferred) sessionWaiter = null
        }
    }

    // endregion

    // region Автентифікація

    suspend fun authenticate(
        authKey: ByteArray,
        phoneModel: String = "Android",
        region: String = "UK",
        phoneInfo: ByteArray? = null,
    ) = withContext(dispatcher) {
        if (authKey.size != 16) throw BandError(ErrorKind.INVALID_AUTH_KEY)
        if (state != SessionState.OPEN) throw BandError(ErrorKind.SESSION_NOT_OPEN)

        val phoneNonce = ByteArray(16).also { random.nextBytes(it) }
        log { "auth: step 1" }
        val step2 = request(Command.authPhoneNonce(phoneNonce), encrypted = false, redact = true) {
            it.matches(Command.AUTH, 26)
        }
        val bandNonce = step2.root.bytes(listOf(3, 31, 1))
        val bandHmac = step2.root.bytes(listOf(3, 31, 2))
        if (bandNonce == null || bandNonce.size != 16 || bandHmac == null || bandHmac.size != 32) {
            throw BandError(ErrorKind.MALFORMED_RESPONSE, "auth step 2")
        }
        val sessionKeys = SessionKeys(authKey, phoneNonce, bandNonce)
        if (!constantTimeEqual(sessionKeys.expectedBandHMAC(phoneNonce, bandNonce), bandHmac)) {
            throw BandError(ErrorKind.AUTH_KEY_MISMATCH)
        }
        val info = sessionKeys.encryptPhoneInfo(phoneInfo ?: Command.phoneInfo(phoneModel, region))
        val confirmation = sessionKeys.phoneConfirmation(phoneNonce, bandNonce)
        log { "auth: step 3" }
        keys = sessionKeys
        try {
            request(Command.authConfirm(confirmation, info), encrypted = false, redact = true) {
                it.matches(Command.AUTH, 27, 5)
            }
        } catch (e: Exception) {
            keys = null
            throw e
        }
        state = SessionState.AUTHENTICATED
        log { "auth: done" }
    }

    // endregion

    // region Команди

    suspend fun request(
        body: ByteArray,
        encrypted: Boolean = true,
        timeoutMs: Long? = null,
        redact: Boolean = false,
        matches: (Command) -> Boolean,
    ): Command = withContext(dispatcher) {
        if (encrypted && keys == null) throw BandError(ErrorKind.NOT_AUTHENTICATED)
        val waiter = Waiter(matches, CompletableDeferred())
        waiters.add(waiter)
        try {
            val header = runCatching { Command(body).name }.getOrDefault("?")
            log { "→ cmd $header" + if (redact) "" else " ${body.hexString()}" }
            val payloadBody = if (encrypted) keys!!.encryptCommand(body) else body
            writeData(DataPacket(DataChannel.PROTOBUF, if (encrypted) DataOpcode.ENCRYPTED else DataOpcode.PLAIN, payloadBody))
            withTimeout(timeoutMs ?: config.commandTimeoutMs) { waiter.result.await() }
        } catch (e: TimeoutCancellationException) {
            throw BandError(ErrorKind.TIMEOUT)
        } finally {
            waiters.remove(waiter)
        }
    }

    suspend fun command(body: ByteArray, timeoutMs: Long? = null): Command {
        val header = Command(body)
        val t = header.type
        val s = header.subtype
        return request(body, timeoutMs = timeoutMs) { it.type == t && it.subtype == s }
    }

    private fun failAllWaiters(error: Throwable) {
        val all = waiters.toList()
        waiters.clear()
        for (w in all) w.result.completeExceptionally(error)
    }

    private suspend fun writeData(packet: DataPacket, trackAck: Boolean = false) {
        val bytes = Frame(FrameType.DATA, phoneSequence, packet.payload).encoded()
        if (trackAck) unacked.add(SentFrame(phoneSequence, bytes))
        phoneSequence = (phoneSequence + 1) and 0xFF
        transport.write(bytes)
    }

    // endregion

    // region Файл

    suspend fun sendFileParts(parts: List<ByteArray>, progress: ((Int, Int) -> Unit)? = null) =
        withContext(dispatcher) {
            if (state != SessionState.AUTHENTICATED) throw BandError(ErrorKind.NOT_AUTHENTICATED)
            log { "file: sending ${parts.size} parts" }
            unacked.clear()
            unsolicitedSeen.clear()
            installStatus = null
            for ((index, part) in parts.withIndex()) {
                ensureActive()
                waitForFileAcks(maxOf(config.fileWindow, 1))
                writeData(DataPacket(DataChannel.FILE, DataOpcode.PLAIN, part), trackAck = true)
                progress?.invoke(index + 1, parts.size)
            }
            log { "file: all parts sent, waiting for the band to confirm" }
            waitForFileAcks(1)
            log { "file: all parts confirmed" }
        }

    private suspend fun waitForFileAcks(limit: Int) {
        var resends = 0
        while (unacked.size >= limit) {
            val status = installStatus
            if (status != null && status != INSTALLED_STATUS) throw BandError(ErrorKind.INSTALL_ABORTED, status = status)
            if (state == SessionState.CLOSED) throw BandError(ErrorKind.DISCONNECTED)
            if (withTimeoutOrNull(config.fileAckTimeoutMs) { ackSignal.receive() } != null) {
                resends = 0
                continue
            }
            resends++
            val first = unacked.firstOrNull()
            if (resends > config.fileResendAttempts || first == null) throw BandError(ErrorKind.TIMEOUT)
            log { "file: no ack, resending ${unacked.size} parts from ${first.sequence}" }
            for (f in unacked.toList()) transport.write(f.bytes)
        }
    }

    /** Підтвердження сукупне: номер N означає, що отримано всі кадри до N включно. */
    private fun handleBandAck(sequence: Int) {
        val before = unacked.size
        unacked.removeAll { ((sequence - it.sequence) and 0xFF) < 128 }
        if (unacked.size != before) ackSignal.trySend(Unit)
    }

    // endregion

    // region Вхідні кадри

    private suspend fun process(bytes: ByteArray) {
        for (frame in parser.append(bytes)) {
            when (frame.type) {
                FrameType.SESSION -> handleSession(frame)
                FrameType.ACK -> {
                    log { "← ack ${frame.sequence}" }
                    if (state != SessionState.OPENING && ((frame.sequence - phoneSequence) and 0xFF) < 128) {
                        noteOtherApp("ack ${frame.sequence}, our next frame is $phoneSequence")
                    }
                    handleBandAck(frame.sequence)
                }
                FrameType.DATA -> handleData(frame)
            }
        }
    }

    private fun handleSession(frame: Frame) {
        val control = SessionControl.parse(frame.payload) ?: return
        log { "← session code ${control.code}" }
        val waiter = sessionWaiter
        if (waiter == null || waiter.first != control.code) {
            noteOtherApp("session code ${control.code} without our request")
            return
        }
        sessionWaiter = null
        waiter.second.complete(control)
    }

    private fun handleData(frame: Frame) {
        sendAck(frame.sequence)
        val expected = expectedBandSequence
        if (expected != null && ((frame.sequence - expected) and 0xFF) >= 128) {
            log { "← data ${frame.sequence} dropped (expected $expected)" }
            return
        }
        expectedBandSequence = (frame.sequence + 1) and 0xFF

        val packet = DataPacket.parse(frame.payload) ?: return
        if (packet.channel != DataChannel.PROTOBUF) {
            log { "← data ${frame.sequence} channel ${packet.channel}, ${packet.body.size} bytes" }
            return
        }
        val body = when (packet.opcode) {
            DataOpcode.ENCRYPTED -> {
                val k = keys
                if (k == null) { log { "← data ${frame.sequence}: encrypted, but no keys" }; return }
                k.decryptCommand(packet.body)
            }
            DataOpcode.PLAIN -> packet.body
            else -> { log { "← data ${frame.sequence}: unknown opcode ${packet.opcode}" }; return }
        }
        val command = try { Command(body) } catch (e: Exception) {
            log { "← data ${frame.sequence}: undecodable command" }
            return
        }
        val redact = command.type == Command.AUTH
        log { "← cmd ${command.name} seq ${frame.sequence}" + if (redact) "" else " ${body.hexString()}" }

        val waiter = waiters.firstOrNull { it.matches(command) && !it.result.isCompleted }
        if (waiter != null) {
            waiters.remove(waiter)
            waiter.result.complete(command)
            return
        }
        unsolicitedSeen.add(command.name)
        if (command.type == Command.WATCHFACE && command.subtype == 5L) {
            installStatus = command.root.varint(listOf(6, 7, 2))
            log { "install status ${installStatus ?: "?"}" }
            ackSignal.trySend(Unit)
        }
        val matching = eventWaiters.filter { it.first == command.name }
        eventWaiters.removeAll(matching)
        for ((_, d) in matching) d.complete(true)
    }

    /** Чекає, поки браслет сам надішле команду «тип/підтип». true — дочекалися. */
    suspend fun waitFor(type: Long, subtype: Long, timeoutMs: Long): Boolean = withContext(dispatcher) {
        val name = "$type/$subtype"
        if (unsolicitedSeen.contains(name)) return@withContext true
        val d = CompletableDeferred<Boolean>()
        val entry = name to d
        eventWaiters.add(entry)
        val result = withTimeoutOrNull(timeoutMs) { d.await() } ?: false
        eventWaiters.remove(entry)
        result
    }

    private fun sendAck(sequence: Int) {
        val bytes = Frame.ack(sequence).encoded()
        log { "→ ack $sequence" }
        scope.launch { try { transport.write(bytes) } catch (_: Exception) { } }
    }

    // endregion

    companion object {
        const val INSTALLED_STATUS = 3L
    }
}
