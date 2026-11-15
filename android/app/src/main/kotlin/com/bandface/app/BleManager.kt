package com.bandface.app

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.content.Context
import android.os.Handler
import android.os.Looper
import com.bandface.kit.BandError
import com.bandface.kit.BandTransport
import com.bandface.kit.ErrorKind
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withTimeout
import java.util.UUID

data class FoundDevice(val name: String, val address: String) {
    /** У списку лише браслети й годинники Xiaomi (навушники, колонки й інше — ні) */
    val isXiaomi: Boolean get() = Regex("(?i)xiaomi|redmi|mi smart band|mi band|smart band").containsMatchIn(name)
}

/** BLE: сервіс FE95, сповіщення з 0x5E, запис без відповіді в 0x5F. */
@SuppressLint("MissingPermission")
@Suppress("DEPRECATION")
class BleManager(private val context: Context, private val log: (String) -> Unit) : BandTransport {
    private val manager = context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
    private val adapter: BluetoothAdapter? = manager.adapter
    /** Пристрої з пошуку: у них правильний тип адреси (Xiaomi — випадкова), а не лише рядок адреси */
    private val seen = HashMap<String, BluetoothDevice>()
    private val main = Handler(Looper.getMainLooper())

    private var gatt: BluetoothGatt? = null
    private var tx: BluetoothGattCharacteristic? = null
    private var mtu = 23
    private val writeLock = Mutex()
    private var writeDone: CompletableDeferred<Unit>? = null
    private var connectDone: CompletableDeferred<Unit>? = null
    private var stage: CompletableDeferred<Unit>? = null

    var onData: ((ByteArray) -> Unit)? = null
    var onDisconnect: (() -> Unit)? = null
    var onFound: ((FoundDevice) -> Unit)? = null
    var connectedName: String? = null
        private set
    val isConnected: Boolean get() = (tx != null || spp != null) && connectedName != null

    /** Класичний Bluetooth (SPP), як у Mi Fitness: ті самі кадри A5 A5…, лише без BLE.
     *  Прив'язаний до телефона браслет тримає класичне з'єднання й на BLE не відповідає (147) */
    @Volatile private var spp: android.bluetooth.BluetoothSocket? = null
    private val sppUuids = listOf(
        UUID.fromString("0000fe95-0000-1000-8000-00805f9b34fb"),
        UUID.fromString("00001101-0000-1000-8000-00805f9b34fb"),
    )

    private val service = UUID.fromString("0000fe95-0000-1000-8000-00805f9b34fb")
    private val rx = UUID.fromString("0000005e-0000-1000-8000-00805f9b34fb")
    private val txUuid = UUID.fromString("0000005f-0000-1000-8000-00805f9b34fb")
    private val cccd = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")

    private val scanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            val name = result.device.name ?: result.scanRecord?.deviceName ?: return
            seen[result.device.address] = result.device
            FoundDevice(name, result.device.address).takeIf { it.isXiaomi }?.let { onFound?.invoke(it) }
        }
    }

    /** Спарені пристрої. Без дозволу «Пристрої поблизу» (Android 12+) — порожньо, а не падіння застосунку:
     *  при першому запуску дозволу ще немає, список оновиться після «Шукати пристрій». */
    fun bonded(): List<FoundDevice> = runCatching {
        adapter?.bondedDevices?.map { FoundDevice(it.name ?: it.address, it.address) }?.filter { it.isXiaomi } ?: emptyList()
    }.getOrDefault(emptyList())

    fun startScan() {
        runCatching { adapter?.bluetoothLeScanner?.startScan(scanCallback) }.onFailure { log("scan: ${it.message}") }
        main.postDelayed({ stopScan() }, 10_000)
    }

    fun stopScan() {
        runCatching { adapter?.bluetoothLeScanner?.stopScan(scanCallback) }
    }

    private val callback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(g: BluetoothGatt, status: Int, newState: Int) {
            log("gatt: state $newState, status $status")
            if (newState == BluetoothProfile.STATE_CONNECTED) {
                // MTU не погоджується (деякі телефони) — одразу шукаємо сервіси, без зависання
                if (!g.requestMtu(247)) g.discoverServices()
            } else {
                tx = null
                connectedName = null
                connectDone?.completeExceptionally(BandError(ErrorKind.NOT_CONNECTED, "status $status"))
                writeDone?.completeExceptionally(BandError(ErrorKind.DISCONNECTED))
                runCatching { g.close() }
                if (gatt === g) gatt = null
                onDisconnect?.invoke()
            }
        }

        override fun onMtuChanged(g: BluetoothGatt, newMtu: Int, status: Int) {
            log("gatt: mtu $newMtu, status $status")
            mtu = newMtu
            g.discoverServices()
        }

        override fun onServicesDiscovered(g: BluetoothGatt, status: Int) {
            val s = g.getService(service)
            val r = s?.getCharacteristic(rx)
            val t = s?.getCharacteristic(txUuid)
            log("gatt: services status $status, fe95 ${if (s != null) "є" else "немає"}")
            if (r == null || t == null) {
                connectDone?.completeExceptionally(BandError(ErrorKind.CHARACTERISTIC_NOT_FOUND))
                return
            }
            t.writeType = BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE
            tx = t
            g.setCharacteristicNotification(r, true)
            val d = r.getDescriptor(cccd)
            d.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
            g.writeDescriptor(d)
        }

        override fun onDescriptorWrite(g: BluetoothGatt, d: BluetoothGattDescriptor, status: Int) {
            log("gatt: notifications status $status")
            connectedName = g.device.name ?: g.device.address
            connectDone?.complete(Unit)
        }

        override fun onCharacteristicChanged(g: BluetoothGatt, c: BluetoothGattCharacteristic) {
            if (c.uuid == rx) onData?.invoke(c.value.copyOf())
        }

        override fun onCharacteristicWrite(g: BluetoothGatt, c: BluetoothGattCharacteristic, status: Int) {
            writeDone?.complete(Unit)
        }
    }

    /** Підключення з повторами: Android часто обриває першу спробу (status 133), друга вдається */
    suspend fun connect(address: String) {
        // спарений браслет — спершу класичний Bluetooth (так з'єднаний Mi Fitness), потім BLE
        val bondedDevice = runCatching { adapter?.bondedDevices?.firstOrNull { it.address.equals(address, true) } }.getOrNull()
        if (bondedDevice != null && connectSpp(bondedDevice)) return
        var last: BandError? = null
        for (attempt in 1..3) {
            try {
                connectOnce(address, attempt)
                return
            } catch (e: BandError) {
                last = e
                if (e.kind != ErrorKind.NOT_CONNECTED && e.kind != ErrorKind.TIMEOUT) throw e
                log("спроба $attempt: ${e.message}")
                if (attempt < 3) kotlinx.coroutines.delay(1_000)
            }
        }
        throw last ?: BandError(ErrorKind.NOT_CONNECTED)
    }

    /** Спроба 1 — браслет, уже підключений до системи (Mi Fitness): приєднуємося до того самого з'єднання;
     *  спроба 2 — та сама адреса як випадкова (так оголошуються браслети Xiaomi, Android 13+);
     *  спроба 3 — чекаємо, поки браслет сам з'явиться (autoConnect), до 30 с */
    private suspend fun connectOnce(address: String, attempt: Int) {
        disconnect()
        val system = runCatching { manager.getConnectedDevices(BluetoothProfile.GATT).firstOrNull { it.address.equals(address, true) } }.getOrNull()
        val bonded = runCatching { adapter?.bondedDevices?.firstOrNull { it.address.equals(address, true) } }.getOrNull()
        val random = if (attempt == 2) randomAddressDevice(address) else null
        val device: BluetoothDevice = random ?: system ?: seen[address] ?: bonded ?: adapter?.getRemoteDevice(address) ?: throw BandError(ErrorKind.NOT_CONNECTED)
        val auto = attempt == 3
        val done = CompletableDeferred<Unit>()
        connectDone = done
        log("connect $address" + when {
            random != null -> " (випадкова адреса)"
            system != null -> " (уже підключений до системи)"
            auto -> " (очікування браслета)"
            else -> ""
        })
        gatt = device.connectGatt(context, auto, callback, BluetoothDevice.TRANSPORT_LE)
        try {
            withTimeout(if (auto) 30_000 else 15_000) { done.await() }
        } catch (e: Exception) {
            disconnect()
            throw if (e is BandError) e else BandError(ErrorKind.TIMEOUT, "connect")
        }
    }

    private fun randomAddressDevice(address: String): BluetoothDevice? =
        if (android.os.Build.VERSION.SDK_INT >= 33)
            runCatching { adapter?.getRemoteLeDevice(address, BluetoothDevice.ADDRESS_TYPE_RANDOM) }.getOrNull()
        else null

    private suspend fun connectSpp(device: BluetoothDevice): Boolean = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
        disconnect()
        runCatching { adapter?.cancelDiscovery() }
        val known = runCatching { device.uuids?.map { it.uuid } }.getOrNull().orEmpty()
        log("spp: uuids ${known.joinToString { it.toString().substring(4, 8) }}")
        // спершу відомі канали Xiaomi, потім решта не звукових сервісів браслета
        val audio = setOf("1108", "110a", "110b", "110c", "110d", "110e", "110f", "111e", "111f", "1112", "112f", "1132", "1200", "1203")
        val candidates = (sppUuids + known.filter { it.toString().substring(4, 8) !in audio }).distinct()
        for (uuid in candidates) {
            val socket = runCatching { device.createRfcommSocketToServiceRecord(uuid) }.getOrNull() ?: continue
            // connect() блокує: закриваємо сокет, якщо браслет мовчить
            val timeout = Runnable { runCatching { socket.close() } }
            main.postDelayed(timeout, 8_000)
            val ok = runCatching { socket.connect() }.onFailure { log("spp ${uuid.toString().substring(4, 8)}: ${it.message}") }.isSuccess
            main.removeCallbacks(timeout)
            if (!ok) { runCatching { socket.close() }; continue }
            spp = socket
            connectedName = device.name ?: device.address
            log("spp ${uuid.toString().substring(4, 8)}: connected")
            startReader(socket)
            return@withContext true
        }
        false
    }

    private fun startReader(socket: android.bluetooth.BluetoothSocket) {
        Thread {
            val buf = ByteArray(4096)
            try {
                val input = socket.inputStream
                while (true) {
                    val n = input.read(buf)
                    if (n < 0) break
                    if (n > 0) onData?.invoke(buf.copyOf(n))
                }
            } catch (e: Exception) {
            }
            if (spp === socket) {
                spp = null
                connectedName = null
                writeDone?.completeExceptionally(BandError(ErrorKind.DISCONNECTED))
                onDisconnect?.invoke()
            }
        }.apply { isDaemon = true; name = "spp-reader" }.start()
    }

    fun disconnect() {
        spp?.let { s -> spp = null; runCatching { s.close() } }
        gatt?.let { runCatching { it.disconnect() }; runCatching { it.close() } }
        gatt = null
        tx = null
        connectedName = null
    }

    override suspend fun write(frame: ByteArray) {
        spp?.let { socket ->
            writeLock.withLock {
                try {
                    kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
                        socket.outputStream.write(frame); socket.outputStream.flush()
                    }
                } catch (e: java.io.IOException) {
                    throw BandError(ErrorKind.DISCONNECTED, "spp write")
                }
            }
            return
        }
        val g = gatt ?: throw BandError(ErrorKind.NOT_CONNECTED)
        val t = tx ?: throw BandError(ErrorKind.NOT_CONNECTED)
        val chunk = maxOf(mtu - 3, 20)
        writeLock.withLock {
            var offset = 0
            while (offset < frame.size) {
                val end = minOf(offset + chunk, frame.size)
                val done = CompletableDeferred<Unit>()
                writeDone = done
                t.value = frame.copyOfRange(offset, end)
                if (!g.writeCharacteristic(t)) throw BandError(ErrorKind.DISCONNECTED, "write failed")
                withTimeout(5_000) { done.await() }
                offset = end
            }
        }
    }
}
