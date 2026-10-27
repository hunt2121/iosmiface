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

data class FoundDevice(val name: String, val address: String)

/** BLE: сервіс FE95, сповіщення з 0x5E, запис без відповіді в 0x5F. */
@SuppressLint("MissingPermission")
@Suppress("DEPRECATION")
class BleManager(private val context: Context, private val log: (String) -> Unit) : BandTransport {
    private val adapter: BluetoothAdapter? =
        (context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager).adapter
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
    val isConnected: Boolean get() = tx != null && connectedName != null

    private val service = UUID.fromString("0000fe95-0000-1000-8000-00805f9b34fb")
    private val rx = UUID.fromString("0000005e-0000-1000-8000-00805f9b34fb")
    private val txUuid = UUID.fromString("0000005f-0000-1000-8000-00805f9b34fb")
    private val cccd = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")

    private val scanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            val name = result.device.name ?: result.scanRecord?.deviceName ?: return
            onFound?.invoke(FoundDevice(name, result.device.address))
        }
    }

    fun bonded(): List<FoundDevice> =
        adapter?.bondedDevices?.map { FoundDevice(it.name ?: it.address, it.address) } ?: emptyList()

    fun startScan() {
        adapter?.bluetoothLeScanner?.startScan(scanCallback)
        main.postDelayed({ stopScan() }, 10_000)
    }

    fun stopScan() {
        runCatching { adapter?.bluetoothLeScanner?.stopScan(scanCallback) }
    }

    private val callback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(g: BluetoothGatt, status: Int, newState: Int) {
            if (newState == BluetoothProfile.STATE_CONNECTED) {
                g.requestMtu(247)
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
            mtu = newMtu
            g.discoverServices()
        }

        override fun onServicesDiscovered(g: BluetoothGatt, status: Int) {
            val s = g.getService(service)
            val r = s?.getCharacteristic(rx)
            val t = s?.getCharacteristic(txUuid)
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

    suspend fun connect(address: String) {
        disconnect()
        val device: BluetoothDevice = adapter?.getRemoteDevice(address) ?: throw BandError(ErrorKind.NOT_CONNECTED)
        val done = CompletableDeferred<Unit>()
        connectDone = done
        log("connect $address")
        gatt = device.connectGatt(context, false, callback, BluetoothDevice.TRANSPORT_LE)
        try {
            withTimeout(15_000) { done.await() }
        } catch (e: Exception) {
            disconnect()
            throw if (e is BandError) e else BandError(ErrorKind.TIMEOUT, "connect")
        }
    }

    fun disconnect() {
        gatt?.let { runCatching { it.disconnect() }; runCatching { it.close() } }
        gatt = null
        tx = null
        connectedName = null
    }

    override suspend fun write(frame: ByteArray) {
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
