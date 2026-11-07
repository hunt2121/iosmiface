using System;
using System.IO.Ports;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using BandFace.Protocol;

namespace BandFace
{
    /// <summary>
    /// Експериментально: Bluetooth LE через плату ESP32-S3 / ESP32-C3 з прошивкою «BandFace bridge»,
    /// підключену по USB (COM-порт). Протокол — текстові рядки, див. windows/EspBridge/src/main.cpp.
    /// </summary>
    sealed class BridgeTransport : ILink
    {
        const int Baud = 921600;

        SerialPort _port;
        readonly object _sendLock = new object();
        readonly object _replyLock = new object();
        readonly SemaphoreSlim _opLock = new SemaphoreSlim(1, 1);
        TaskCompletionSource<string> _reply;
        string _replyKind;
        Action<FoundBand> _found;
        volatile bool _connected;
        int _block = 960;

        public event Action<byte[]> Data;
        public event Action Disconnected;
        public event Action<string> Info;
        public string ConnectedName { get; private set; }
        public bool IsOpen { get { var p = _port; return p != null && p.IsOpen; } }
        public bool IsConnected => _connected && IsOpen;
        public string PortName => _port?.PortName;

        /// <summary>Шукає плату: на кожен COM-порт надсилає HELLO і чекає «OK BRIDGE».</summary>
        public Task OpenAsync()
        {
            if (IsOpen) return Task.CompletedTask;
            return Task.Run(() =>
            {
                foreach (var name in SerialPort.GetPortNames())
                {
                    SerialPort p = null;
                    try
                    {
                        p = new SerialPort(name, Baud)
                        {
                            DtrEnable = false, RtsEnable = false,   // інакше плати з CH340/CP2102 перезавантажуються
                            ReadTimeout = 200, WriteTimeout = 2000, NewLine = "\n", Encoding = Encoding.ASCII,
                            ReadBufferSize = 1 << 16,
                        };
                        p.Open();
                        if (Probe(p))
                        {
                            _port = p;
                            break;
                        }
                        p.Close();
                    }
                    catch (Exception) { try { p?.Close(); } catch (Exception) { } }
                }
                if (_port == null) throw new BandException(ErrorKind.NotConnected, "bridge");
                _port.ReadTimeout = SerialPort.InfiniteTimeout;
                var reader = new Thread(ReadLoop) { IsBackground = true, Name = "ESP32 bridge" };
                reader.Start(_port);
            });
        }

        static bool Probe(SerialPort p)
        {
            var until = DateTime.UtcNow.AddMilliseconds(1800);
            var next = DateTime.MinValue;
            while (DateTime.UtcNow < until)
            {
                if (DateTime.UtcNow >= next) { p.Write("\nHELLO\n"); next = DateTime.UtcNow.AddMilliseconds(500); }
                try { if (p.ReadLine().Trim().StartsWith("OK BRIDGE")) return true; }
                catch (TimeoutException) { }
            }
            return false;
        }

        /// <summary>Закрити порт (перемикач вимкнено або вікно закрито).</summary>
        public void Close()
        {
            StopScan();
            Disconnect();
            var p = _port;
            _port = null;
            try { p?.Close(); } catch (Exception) { }
        }

        void ReadLoop(object arg)
        {
            var port = (SerialPort)arg;
            try
            {
                while (true)
                {
                    var line = port.ReadLine().TrimEnd('\r');
                    if (line.Length > 0) Handle(line);
                }
            }
            catch (Exception) { }
            if (_port != port) return;   // закрили самі
            // плату висмикнули з USB
            _port = null;
            try { port.Close(); } catch (Exception) { }
            Info?.Invoke("bridge: USB lost");
            Complete("C", "ERR usb");
            Complete("W", "E usb");
            bool was = _connected;
            _connected = false; ConnectedName = null;
            if (was) Disconnected?.Invoke();
        }

        void Handle(string l)
        {
            if (l.StartsWith("N "))
            {
                var b = Bytes.ParseHex(l.Substring(2));
                if (b != null) Data?.Invoke(b);
            }
            else if (l == "K" || l.StartsWith("E ")) Complete("W", l);
            else if (l.StartsWith("ADV ")) Advert(l);
            else if (l.StartsWith("CONNECTED") || l.StartsWith("ERR")) Complete("C", l);
            else if (l == "DISCONNECTED")
            {
                bool was = _connected;
                _connected = false; ConnectedName = null;
                Complete("W", "E disconnected");
                if (was) Disconnected?.Invoke();
            }
            else if (l.StartsWith("LOG ")) Info?.Invoke("bridge: " + l.Substring(4));
        }

        // ADV <адреса> <тип> <rssi> <fe95> <назва>
        void Advert(string l)
        {
            var f = _found;
            if (f == null) return;
            var p = l.Split(new[] { ' ' }, 6);
            if (p.Length < 6) return;
            string name = p[5].Trim();
            if (name.Length == 0) return;
            bool ours = p[4] == "1"
                || name.IndexOf("Band", StringComparison.OrdinalIgnoreCase) >= 0
                || name.IndexOf("Xiaomi", StringComparison.OrdinalIgnoreCase) >= 0;
            if (!ours) return;
            ulong addr;
            if (!ulong.TryParse(p[1].Replace(":", ""), System.Globalization.NumberStyles.HexNumber, null, out addr)) return;
            int type;
            int.TryParse(p[2], out type);
            f(new FoundBand { Name = name, Address = addr, BridgeAddr = p[1], AddrType = type });
        }

        Task<string> Expect(string kind)
        {
            var t = new TaskCompletionSource<string>(TaskCreationOptions.RunContinuationsAsynchronously);
            lock (_replyLock) { _reply = t; _replyKind = kind; }
            return t.Task;
        }

        void Complete(string kind, string line)
        {
            TaskCompletionSource<string> t = null;
            lock (_replyLock)
            {
                if (_reply != null && _replyKind == kind) { t = _reply; _reply = null; }
            }
            t?.TrySetResult(line);
        }

        void Send(string line)
        {
            var p = _port;
            if (p == null || !p.IsOpen) throw new BandException(ErrorKind.NotConnected, "bridge");
            try { lock (_sendLock) p.Write(line + "\n"); }
            catch (Exception ex) when (!(ex is BandException)) { throw new BandException(ErrorKind.Disconnected, "bridge"); }
        }

        static async Task<string> Wait(Task<string> t, int ms)
        {
            if (await Task.WhenAny(t, Task.Delay(ms)).ConfigureAwait(false) != t) throw new BandException(ErrorKind.Timeout, "bridge");
            return t.Result;
        }

        public void StartScan(Action<FoundBand> found)
        {
            _found = found;
            Send("SCAN 1");
        }

        public void StopScan()
        {
            _found = null;
            try { if (IsOpen) Send("SCAN 0"); } catch (Exception) { }
        }

        public async Task ConnectAsync(FoundBand band)
        {
            if (band.BridgeAddr == null) throw new BandException(ErrorKind.NotConnected);
            await _opLock.WaitAsync();
            try
            {
                _connected = false; ConnectedName = null;
                var t = Expect("C");
                Send("CONN " + band.BridgeAddr + " " + band.AddrType);
                string r;
                try { r = await Wait(t, 60000); }
                catch (BandException) { try { Send("DISC"); } catch (Exception) { } throw; }
                if (!r.StartsWith("CONNECTED"))
                {
                    string why = r.Length > 4 ? r.Substring(4) : r;
                    if (why == "service" || why == "characteristic") throw new BandException(ErrorKind.CharacteristicNotFound);
                    throw new InvalidOperationException("ESP32: " + why);
                }
                int mtu;
                var parts = r.Split(' ');
                if (parts.Length < 2 || !int.TryParse(parts[1], out mtu)) mtu = 23;
                // блок до ~1000 байтів, кратний BLE-пакету — тоді ESP32 ріже кадри так само, як Windows
                int packet = Math.Max(mtu - 3, 20);
                _block = packet * Math.Max(1, 1000 / packet);
                Info?.Invoke("bridge: mtu " + mtu);
                ConnectedName = band.Name;
                _connected = true;
            }
            finally { _opLock.Release(); }
        }

        public void Disconnect()
        {
            bool was = _connected;
            _connected = false; ConnectedName = null;
            if (was) { try { Send("DISC"); } catch (Exception) { } }
        }

        public async Task WriteAsync(byte[] frame)
        {
            if (!IsConnected) throw new BandException(ErrorKind.NotConnected);
            await _opLock.WaitAsync().ConfigureAwait(false);
            try
            {
                for (int off = 0; off < frame.Length; off += _block)
                {
                    int n = Math.Min(_block, frame.Length - off);
                    var part = new byte[n];
                    Buffer.BlockCopy(frame, off, part, 0, n);
                    var t = Expect("W");
                    Send("W " + Bytes.ToHexLower(part));
                    var r = await Wait(t, 15000).ConfigureAwait(false);
                    if (r != "K") throw new BandException(ErrorKind.Disconnected, "write");
                }
            }
            finally { _opLock.Release(); }
        }
    }
}
