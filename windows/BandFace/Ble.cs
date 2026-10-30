using System;
using Windows.Foundation;
using System.Collections.Generic;
using System.Runtime.InteropServices.WindowsRuntime;
using System.Threading.Tasks;
using System.Threading;
using BandFace.Protocol;
using Windows.Devices.Bluetooth;
using Windows.Devices.Bluetooth.Advertisement;
using Windows.Devices.Bluetooth.GenericAttributeProfile;
using Windows.Devices.Enumeration;
using Windows.Storage.Streams;

namespace BandFace
{
    sealed class FoundBand
    {
        public string Name; public ulong Address;
        public override string ToString() => Name;
    }

    /// <summary>BLE: сервіс FE95, сповіщення з 0x5E, запис без відповіді в 0x5F.</summary>
    sealed class BleTransport : IBandTransport
    {
        static readonly Guid Service = Guid.Parse("0000fe95-0000-1000-8000-00805f9b34fb");
        static readonly Guid RxUuid = Guid.Parse("0000005e-0000-1000-8000-00805f9b34fb");
        static readonly Guid TxUuid = Guid.Parse("0000005f-0000-1000-8000-00805f9b34fb");

        BluetoothLEDevice _dev;
        GattSession _session;
        GattCharacteristic _rx, _tx;
        BluetoothLEAdvertisementWatcher _watcher;
        readonly SemaphoreSlim _writeLock = new SemaphoreSlim(1, 1);
        int _chunk = 20;

        public event Action<byte[]> Data;
        public event Action Disconnected;
        public event Action<string> Info;
        public string ConnectedName { get; private set; }
        public bool IsConnected => _tx != null && _dev != null && _dev.ConnectionStatus == BluetoothConnectionStatus.Connected;

        public void StartScan(Action<FoundBand> found)
        {
            StopScan();
            _watcher = new BluetoothLEAdvertisementWatcher { ScanningMode = BluetoothLEScanningMode.Active };
            _watcher.Received += (w, a) =>
            {
                var name = a.Advertisement.LocalName;
                if (string.IsNullOrEmpty(name)) return;
                bool ours = a.Advertisement.ServiceUuids.Contains(Service)
                    || name.IndexOf("Band", StringComparison.OrdinalIgnoreCase) >= 0
                    || name.IndexOf("Xiaomi", StringComparison.OrdinalIgnoreCase) >= 0;
                if (ours) found(new FoundBand { Name = name, Address = a.BluetoothAddress });
            };
            _watcher.Start();
        }

        public void StopScan()
        {
            try { _watcher?.Stop(); } catch (Exception) { }
            _watcher = null;
        }

        public async Task ConnectAsync(ulong address)
        {
            Disconnect();
            _dev = await BluetoothLEDevice.FromBluetoothAddressAsync(address);
            if (_dev == null) throw new BandException(ErrorKind.NotConnected);
            await EnsurePaired(address);
            var svc = await _dev.GetGattServicesForUuidAsync(Service, BluetoothCacheMode.Uncached);
            if (svc.Status != GattCommunicationStatus.Success || svc.Services.Count == 0) throw new BandException(ErrorKind.CharacteristicNotFound);
            var s = svc.Services[0];
            var rx = await s.GetCharacteristicsForUuidAsync(RxUuid, BluetoothCacheMode.Uncached);
            var tx = await s.GetCharacteristicsForUuidAsync(TxUuid, BluetoothCacheMode.Uncached);
            if (rx.Characteristics.Count == 0 || tx.Characteristics.Count == 0) throw new BandException(ErrorKind.CharacteristicNotFound);
            _rx = rx.Characteristics[0];
            _tx = tx.Characteristics[0];
            _rx.ValueChanged += OnValue;
            var st = await _rx.WriteClientCharacteristicConfigurationDescriptorAsync(GattClientCharacteristicConfigurationDescriptorValue.Notify);
            if (st != GattCommunicationStatus.Success) throw new BandException(ErrorKind.NotConnected, "notify");
            try
            {
                _session = await GattSession.FromDeviceIdAsync(_dev.BluetoothDeviceId);
                _session.MaintainConnection = true;
                _chunk = Math.Max(_session.MaxPduSize - 3, 20);
            }
            catch (Exception) { _chunk = 20; }
            _dev.ConnectionStatusChanged += (d, o) =>
            {
                if (d.ConnectionStatus == BluetoothConnectionStatus.Disconnected) { ConnectedName = null; Disconnected?.Invoke(); }
            };
            ConnectedName = _dev.Name;
        }

        /// <summary>
        /// Зв'язування на рівні BLE (LE Secure Connections, Just Works) — те саме, що робить Mi Fitness.
        /// Браслет у цей момент показує запит «підключити новий пристрій».
        /// </summary>
        async Task EnsurePaired(ulong address)
        {
            var pairing = _dev.DeviceInformation.Pairing;
            Info?.Invoke("connect pairing: paired=" + pairing.IsPaired + " canPair=" + pairing.CanPair);
            if (pairing.IsPaired)
            {
                // Застаріле зв'язування (браслет міг бути скинутий) — забуваємо його й зв'язуємо наново
                var u = await pairing.UnpairAsync();
                Info?.Invoke("connect unpair: " + u.Status);
                try { _dev.Dispose(); } catch (Exception) { }
                _dev = await BluetoothLEDevice.FromBluetoothAddressAsync(address);
                if (_dev == null) throw new BandException(ErrorKind.NotConnected);
                pairing = _dev.DeviceInformation.Pairing;
            }
            // Спершу відкриваємо справжнє GATT-з'єднання: зв'язування має відбутися на живому каналі
            var probe = await _dev.GetGattServicesAsync(BluetoothCacheMode.Uncached);
            Info?.Invoke("connect link: " + probe.Status + " status=" + _dev.ConnectionStatus);
            try { _session = await GattSession.FromDeviceIdAsync(_dev.BluetoothDeviceId); _session.MaintainConnection = true; } catch (Exception) { }
            if (!pairing.CanPair) throw new InvalidOperationException("Pairing is not supported");
            var custom = pairing.Custom;
            TypedEventHandler<DeviceInformationCustomPairing, DevicePairingRequestedEventArgs> h = (s, a) =>
            {
                Info?.Invoke("connect pair request: " + a.PairingKind);
                a.Accept();
            };
            custom.PairingRequested += h;
            try
            {
                foreach (var level in new[] { DevicePairingProtectionLevel.Encryption, DevicePairingProtectionLevel.EncryptionAndAuthentication })
                {
                    var r = await custom.PairAsync(DevicePairingKinds.ConfirmOnly, level);
                    Info?.Invoke("connect pair(" + level + "): " + r.Status + " used=" + r.ProtectionLevelUsed);
                    if (r.Status == DevicePairingResultStatus.Paired && r.ProtectionLevelUsed != DevicePairingProtectionLevel.None) return;
                    if (r.Status == DevicePairingResultStatus.Paired || r.Status == DevicePairingResultStatus.AlreadyPaired)
                    {
                        // «зв'язано» без шифрування — скидаємо й пробуємо суворіший рівень
                        await pairing.UnpairAsync();
                        await Task.Delay(500);
                        continue;
                    }
                    throw new InvalidOperationException("Pairing: " + r.Status);
                }
            }
            finally { custom.PairingRequested -= h; }
        }

        void OnValue(GattCharacteristic c, GattValueChangedEventArgs e)
        {
            var r = DataReader.FromBuffer(e.CharacteristicValue);
            var b = new byte[e.CharacteristicValue.Length];
            r.ReadBytes(b);
            Data?.Invoke(b);
        }

        public void Disconnect()
        {
            try { if (_rx != null) _rx.ValueChanged -= OnValue; } catch (Exception) { }
            try { _session?.Dispose(); } catch (Exception) { }
            try { _dev?.Dispose(); } catch (Exception) { }
            _session = null; _dev = null; _rx = null; _tx = null; ConnectedName = null;
        }

        public async Task WriteAsync(byte[] frame)
        {
            var tx = _tx;
            if (tx == null) throw new BandException(ErrorKind.NotConnected);
            await _writeLock.WaitAsync().ConfigureAwait(false);
            try
            {
                for (int off = 0; off < frame.Length; off += _chunk)
                {
                    int n = Math.Min(_chunk, frame.Length - off);
                    var part = new byte[n];
                    System.Buffer.BlockCopy(frame, off, part, 0, n);
                    var st = await tx.WriteValueAsync(part.AsBuffer(), GattWriteOption.WriteWithoutResponse);
                    if (st != GattCommunicationStatus.Success) throw new BandException(ErrorKind.Disconnected, "write");
                }
            }
            finally { _writeLock.Release(); }
        }
    }
}
