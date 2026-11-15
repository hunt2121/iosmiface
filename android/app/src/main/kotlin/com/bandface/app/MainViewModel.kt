package com.bandface.app

import android.app.Application
import android.content.ClipData
import android.content.ClipboardManager
import android.graphics.Bitmap
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

private val HEX32 = Regex("(?<![0-9a-fA-F])[0-9a-fA-F]{32}(?![0-9a-fA-F])")

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
    var preview by mutableStateOf<Bitmap?>(null)
    var faceInfo by mutableStateOf("")
    var fileName by mutableStateOf<String?>(null)
    var progressText by mutableStateOf("")
    var keyMessage by mutableStateOf<String?>(null)
    var devMode by mutableStateOf(prefs.getBoolean("dev", false))
    /** Браслети з акаунта Xiaomi після входу */
    val cloudDevices = mutableStateListOf<CloudDevice>()
    var cloudLoading by mutableStateOf(false)
    /** Підключитися не вдалося, бо браслет, схоже, тримає Mi Fitness */
    var bandBusy by mutableStateOf(false)
    /** Після підключення: ключ підходить і заряд, або чому ні */
    var bandInfo by mutableStateOf<String?>(null)

    val versionLabel: String = runCatching {
        val i = app.packageManager.getPackageInfo(app.packageName, 0)
        "BandFace v${i.versionName}"
    }.getOrDefault("BandFace")

    private val ble = BleManager(app) { addLog(it) }
    private var job: Job? = null
    private val time = SimpleDateFormat("HH:mm:ss", Locale.US)

    init {
        ble.onFound = { d -> if (devices.none { it.address == d.address }) devices.add(d) }
        ble.bonded().forEach { devices.add(it) }
    }

    fun setDev(v: Boolean) { devMode = v; prefs.edit().putBoolean("dev", v).apply() }

    fun copyLog() {
        val cm = ctx.getSystemService(android.content.Context.CLIPBOARD_SERVICE) as ClipboardManager
        cm.setPrimaryClip(ClipData.newPlainText("log", log.joinToString("\n")))
    }

    fun pasteKey() {
        val cm = ctx.getSystemService(android.content.Context.CLIPBOARD_SERVICE) as ClipboardManager
        val t = cm.primaryClip?.getItemAt(0)?.text?.toString() ?: ""
        val m = HEX32.find(t)
        if (m != null) { keyText = m.value.lowercase(); saveKey(keyText); keyMessage = s(R.string.key_saved) }
        else keyMessage = s(R.string.key_not_found)
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
                bandBusy = false
                bandInfo = null
                ble.connect(d.address)
                connectedName = ble.connectedName
                addLog(s(R.string.connected, connectedName ?: ""))
                checkBand()
            } catch (e: Exception) {
                // браслет не відповідає на підключення (147 / таймаут) — найчастіше його тримає Mi Fitness
                bandBusy = e is BandError && (e.kind == ErrorKind.TIMEOUT || e.detail.startsWith("status"))
                status = if (bandBusy) s(R.string.err_busy) else describe(e)
                addLog(status!!)
            } finally {
                busy = false
            }
        }
    }

    fun saveKey(text: String): Boolean {
        val bytes = Hex.decode(text)
        if (bytes == null || bytes.size != 16) {
            keyMessage = s(R.string.key_invalid)
            return false
        }
        keyText = Hex.encode(bytes)
        prefs.edit().putString("key", keyText).apply()
        keyMessage = s(R.string.key_saved)
        return true
    }


    fun pickFace(uri: Uri) {
        try {
            val bytes = ctx.contentResolver.openInputStream(uri)!!.use { it.readBytes() }
            val f = FaceFile(bytes)
            face = f
            faceName = f.name ?: f.id
            faceInfo = "ID ${f.id} · ${f.size / 1024} KB"
            fileName = runCatching {
                ctx.contentResolver.query(uri, arrayOf(android.provider.OpenableColumns.DISPLAY_NAME), null, null, null)
                    ?.use { c -> if (c.moveToFirst()) c.getString(0) else null }
            }.getOrNull()
            preview = runCatching {
                f.decodePreview()?.let { Bitmap.createBitmap(it.argb, it.width, it.height, Bitmap.Config.ARGB_8888) }
            }.getOrNull()
            status = null
            addLog("${f.id} (${f.size / 1024} KB)")
        } catch (e: Exception) {
            face = null
            faceName = null
            status = describe(e)
        }
    }

    fun disconnect() { ble.disconnect(); connectedName = null }

    /** Після підключення, як в iOS: вхід ключем і заряд — одразу видно, чи ключ підходить */
    private suspend fun checkBand() {
        val key = Hex.decode(keyText)
        if (key == null || key.size != 16) { bandInfo = s(R.string.band_no_key); return }
        val config = SessionConfig()
        if (devMode) config.log = { addLog(it) }
        val session = BandSession(ble, config)
        ble.onData = { session.receive(it) }
        try {
            session.open()
            session.authenticate(key, "Android", "UK", phoneInfo())
            val r = runCatching { session.command(Command.batteryRequest(), 2000) }.getOrNull()
            val level = r?.root?.message(listOf(4, 2, 1))?.varint(1)?.takeIf { it in 0..100 }
            bandInfo = if (level != null) s(R.string.band_ok_battery, level.toInt()) else s(R.string.band_ok)
            addLog(bandInfo!!)
        } catch (e: Exception) {
            bandInfo = describe(e)
            addLog(bandInfo!!)
        } finally {
            runCatching { session.close() }
            ble.onData = null
            session.dispose()
        }
    }

    /** Вхід на сайті Xiaomi завершено: беремо браслети з ключами з хмари Mi Fitness */
    fun loadCloud(cookies: String) {
        viewModelScope.launch {
            cloudLoading = true
            cloudDevices.clear()
            keyMessage = null
            try {
                val list = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
                    XiaomiCloud.devices(cookies) { addLog(it) }
                }
                cloudDevices.addAll(list)
                keyMessage = if (list.isEmpty()) s(R.string.cloud_empty) else null
                // один браслет — ключ одразу
                if (list.size == 1) chooseCloud(list[0])
            } catch (e: Exception) {
                addLog("xiaomi: ${e.message}")
                keyMessage = s(R.string.cloud_failed)
            } finally {
                cloudLoading = false
            }
        }
    }

    fun chooseCloud(d: CloudDevice) {
        if (saveKey(d.key)) keyMessage = s(R.string.cloud_chosen, d.name.ifEmpty { d.model })
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
            if (devMode) config.log = { addLog(it) }
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
                            progressText = s(R.string.progress, phase.sent, phase.total)
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
            // обрив під час підключення — з кодом Android, а не «спочатку підключіть»
            ErrorKind.NOT_CONNECTED -> if (e.detail.startsWith("status")) s(R.string.err_link, e.detail.removePrefix("status ").trim()) else s(R.string.err_connect)
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
