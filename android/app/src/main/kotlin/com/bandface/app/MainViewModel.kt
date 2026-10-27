package com.bandface.app

import android.app.Application
import android.net.Uri
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.bandface.kit.BandError
import com.bandface.kit.BandSession
import com.bandface.kit.Command
import com.bandface.kit.ErrorKind
import com.bandface.kit.FaceFile
import com.bandface.kit.Hex
import com.bandface.kit.InstallPhase
import com.bandface.kit.ProtoWriter
import com.bandface.kit.SessionConfig
import com.bandface.kit.WatchfaceInstaller
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class MainViewModel(app: Application) : AndroidViewModel(app) {
    private val prefs = app.getSharedPreferences("bandface", 0)
    private val ctx = app

    val log = mutableStateListOf<String>()
    val devices = mutableStateListOf<FoundDevice>()

    var keyText by mutableStateOf(prefs.getString("key", "") ?: "")
    var faceName by mutableStateOf<String?>(null)
    var face by mutableStateOf<FaceFile?>(null)
    var busy by mutableStateOf(false)
    var progress by mutableStateOf<Float?>(null)
    var status by mutableStateOf<String?>(null)
    var connectedName by mutableStateOf<String?>(null)

    private val ble = BleManager(app) { addLog(it) }
    private var job: Job? = null
    private val time = SimpleDateFormat("HH:mm:ss", Locale.US)

    init {
        ble.onFound = { d -> if (devices.none { it.address == d.address }) devices.add(d) }
        ble.bonded().forEach { devices.add(it) }
    }

    fun addLog(text: String) {
        viewModelScope.launch { log.add("${time.format(Date())}  $text") }
    }

    private fun s(id: Int, vararg a: Any) = ctx.getString(id, *a)

    fun scan() {
        devices.clear()
        ble.bonded().forEach { devices.add(it) }
        ble.startScan()
    }

    fun connect(d: FoundDevice) {
        ble.stopScan()
        job = viewModelScope.launch {
            busy = true
            try {
                ble.connect(d.address)
                connectedName = ble.connectedName
                addLog(s(R.string.connected, connectedName ?: ""))
            } catch (e: Exception) {
                status = describe(e)
                addLog(status!!)
            } finally {
                busy = false
            }
        }
    }

    fun saveKey(text: String): Boolean {
        val bytes = Hex.decode(text)
        if (bytes == null || bytes.size != 16) {
            status = s(R.string.key_invalid)
            return false
        }
        keyText = Hex.encode(bytes)
        prefs.edit().putString("key", keyText).apply()
        status = s(R.string.key_saved)
        return true
    }

    /** Шукає в текстовому файлі 32 hex-символи поспіль. */
    fun importKey(uri: Uri) {
        val text = runCatching {
            ctx.contentResolver.openInputStream(uri)?.use { it.readBytes().toString(Charsets.ISO_8859_1) }
        }.getOrNull() ?: ""
        val m = Regex("(?<![0-9a-fA-F])[0-9a-fA-F]{32}(?![0-9a-fA-F])").find(text)
        if (m != null) {
            keyText = m.value.lowercase()
            saveKey(keyText)
            status = s(R.string.key_found)
        } else {
            status = s(R.string.key_not_found)
        }
    }

    fun pickFace(uri: Uri) {
        try {
            val bytes = ctx.contentResolver.openInputStream(uri)!!.use { it.readBytes() }
            val f = FaceFile(bytes)
            face = f
            faceName = f.name ?: f.id
            status = null
            addLog("${f.id} (${f.size / 1024} KB)")
        } catch (e: Exception) {
            face = null
            faceName = null
            status = describe(e)
        }
    }

    fun install() {
        val f = face ?: return
        if (!ble.isConnected) { status = s(R.string.err_connect); return }
        val key = Hex.decode(keyText)
        if (key == null || key.size != 16) { status = s(R.string.key_invalid); return }
        job = viewModelScope.launch {
            busy = true
            status = null
            progress = 0f
            val config = SessionConfig()
            config.log = { addLog(it) }
            val session = BandSession(ble, config)
            ble.onData = { session.receive(it) }
            ble.onDisconnect = { session.connectionLost(); connectedName = null }
            val installer = WatchfaceInstaller()
            installer.phoneModel = "Android"
            installer.phoneInfo = phoneInfo()
            try {
                var already = false
                installer.install(f, key, session) { phase ->
                    when (phase) {
                        is InstallPhase.Uploading -> {
                            if (phase.total > 0) progress = phase.sent.toFloat() / phase.total
                            status = s(R.string.progress, phase.sent, phase.total)
                        }
                        is InstallPhase.Done -> already = phase.alreadyInstalled
                        else -> Unit
                    }
                }
                status = s(if (already) R.string.done_already else R.string.done_installed)
            } catch (e: Exception) {
                status = describe(e)
            } finally {
                addLog(status ?: "")
                ble.onData = null
                ble.onDisconnect = null
                session.dispose()
                progress = null
                busy = false
            }
        }
    }

    private fun phoneInfo(): ByteArray {
        val w = ProtoWriter()
        w.varint(1, 1)
        w.float(2, 27.2f)
        w.string(3, "Unknown")
        w.varint(4, 25_183_776)
        w.string(5, Locale.getDefault().country.ifEmpty { "UA" })
        return w.output
    }

    private fun describe(e: Throwable): String = when (e) {
        is BandError -> when (e.kind) {
            ErrorKind.AUTH_KEY_MISMATCH, ErrorKind.NOT_AUTHENTICATED, ErrorKind.INVALID_AUTH_KEY -> s(R.string.err_auth)
            ErrorKind.TIMEOUT, ErrorKind.SESSION_OPEN_FAILED -> s(R.string.err_timeout)
            ErrorKind.NOT_CONNECTED -> s(R.string.err_connect)
            ErrorKind.DISCONNECTED, ErrorKind.CANCELLED -> s(R.string.err_disconnected)
            ErrorKind.INVALID_FACE_FILE, ErrorKind.INVALID_PREVIEW -> s(R.string.err_face)
            ErrorKind.INSTALL_REJECTED, ErrorKind.UPLOAD_REJECTED, ErrorKind.INSTALL_ABORTED ->
                s(R.string.err_install, e.status.toInt())
            else -> s(R.string.err_generic, e.message ?: "")
        }
        else -> s(R.string.err_generic, e.message ?: e.javaClass.simpleName)
    }

    override fun onCleared() {
        ble.disconnect()
    }
}
