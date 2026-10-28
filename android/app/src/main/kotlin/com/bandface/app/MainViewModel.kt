package com.bandface.app

import android.app.Application
import android.content.ClipData
import android.content.ClipboardManager
import android.graphics.Bitmap
import android.net.Uri
import android.provider.DocumentsContract
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

    /** Обходить вибрану папку і шукає ключ у текстових файлах. */
    fun scanFolder(tree: Uri) {
        viewModelScope.launch {
            val found = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
                var result: String? = null
                fun walk(docId: String, depth: Int) {
                    if (result != null || depth > 6) return
                    val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, docId)
                    ctx.contentResolver.query(children, arrayOf(
                        DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                        DocumentsContract.Document.COLUMN_MIME_TYPE,
                        DocumentsContract.Document.COLUMN_SIZE), null, null, null)?.use { c ->
                        val list = ArrayList<Triple<String, String, Long>>()
                        while (c.moveToNext()) list.add(Triple(c.getString(0), c.getString(1), c.getLong(2)))
                        for ((id, mime, size) in list) {
                            if (result != null) return
                            if (mime == DocumentsContract.Document.MIME_TYPE_DIR) walk(id, depth + 1)
                            else if (size in 1..4_000_000) {
                                val text = runCatching {
                                    ctx.contentResolver.openInputStream(DocumentsContract.buildDocumentUriUsingTree(tree, id))
                                        ?.use { it.readBytes().toString(Charsets.ISO_8859_1) }
                                }.getOrNull() ?: continue
                                val m = Regex("encryptKey\\W{0,8}([0-9a-fA-F]{32})").find(text)
                                if (m != null) { result = m.groupValues[1]; return }
                            }
                        }
                    }
                }
                walk(DocumentsContract.getTreeDocumentId(tree), 0)
                result
            }
            if (found != null) { keyText = found.lowercase(); saveKey(keyText); keyMessage = s(R.string.key_found) }
            else keyMessage = s(R.string.key_not_found)
        }
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
            keyMessage = s(R.string.key_invalid)
            return false
        }
        keyText = Hex.encode(bytes)
        prefs.edit().putString("key", keyText).apply()
        keyMessage = s(R.string.key_saved)
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
            keyMessage = s(R.string.key_found)
        } else {
            keyMessage = s(R.string.key_not_found)
        }
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
