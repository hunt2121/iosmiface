// SPDX-License-Identifier: MIT
using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Linq;
using System.Security.Cryptography;
using System.Threading;
using System.Threading.Tasks;

namespace BandFace.Protocol
{
    /// <summary>Транспорт: доставляє цілі кадри (сам ріже їх на пакети BLE і серіалізує записи).</summary>
    public interface IBandTransport
    {
        Task WriteAsync(byte[] frame);
    }

    public sealed class SessionConfig
    {
        public int SessionOpenTimeoutMs = 4000;
        public int SessionOpenAttempts = 2;
        public List<KeyValuePair<int, byte[]>> OpenParameters;
        public int FileWindow = 12;
        public int FileAckTimeoutMs = 3000;
        public int FileResendAttempts = 3;
        public int SessionCloseTimeoutMs = 1000;
        public int CommandTimeoutMs = 10000;
        public Action<string> Log;
    }

    public enum SessionState { Idle, Opening, Open, Authenticated, Closed }

    public sealed class BandSession : IDisposable
    {
        sealed class Waiter { public Func<Command, bool> Match; public TaskCompletionSource<Command> Tcs; }
        sealed class Sent { public int Seq; public byte[] Bytes; }

        readonly IBandTransport _transport;
        readonly SessionConfig _cfg;
        readonly object _gate = new object();
        readonly BlockingCollection<byte[]> _input = new BlockingCollection<byte[]>();
        readonly SemaphoreSlim _ackSignal = new SemaphoreSlim(0);
        readonly FrameParser _parser = new FrameParser();
        readonly List<Sent> _unacked = new List<Sent>();
        readonly HashSet<string> _unsolicited = new HashSet<string>();
        readonly List<Waiter> _waiters = new List<Waiter>();
        readonly List<KeyValuePair<string, TaskCompletionSource<bool>>> _events = new List<KeyValuePair<string, TaskCompletionSource<bool>>>();
        KeyValuePair<int, TaskCompletionSource<SessionControl>>? _sessionWaiter;
        int _phoneSeq;
        int _expectedBand = -1;
        SessionKeys _keys;

        public SessionState State { get; private set; } = SessionState.Idle;
        public long? InstallStatus { get; private set; }
        public const long InstalledStatus = 3;

        public BandSession(IBandTransport transport, SessionConfig cfg = null)
        {
            _transport = transport;
            _cfg = cfg ?? new SessionConfig();
            var t = new Thread(Pump) { IsBackground = true, Name = "BandSession" };
            t.Start();
        }

        public void Dispose() => _input.CompleteAdding();

        /// <summary>Передайте сюди кожне сповіщення з характеристики 0x5E у порядку надходження.</summary>
        public void Receive(byte[] data)
        {
            try { _input.Add(data); } catch (InvalidOperationException) { }
        }

        void Log(string s) => _cfg.Log?.Invoke(s);

        void Pump()
        {
            foreach (var chunk in _input.GetConsumingEnumerable())
            {
                try { Process(chunk); } catch (Exception e) { Log("pump: " + e.Message); }
            }
        }

        static async Task<bool> WithTimeout(Task t, int ms)
        {
            var done = await Task.WhenAny(t, Task.Delay(ms)).ConfigureAwait(false);
            return done == t;
        }

        // ---- Сесія

        public async Task OpenAsync()
        {
            State = SessionState.Opening;
            for (int a = 0; a < Math.Max(_cfg.SessionOpenAttempts, 1); a++)
            {
                lock (_gate) { _parser.Reset(); _unacked.Clear(); _phoneSeq = 0; _expectedBand = -1; _keys = null; }
                var control = _cfg.OpenParameters != null ? new SessionControl(SessionControl.OpenRequest, _cfg.OpenParameters) : SessionControl.DefaultOpen();
                try
                {
                    await SessionExchange(control, SessionControl.OpenResponse, _cfg.SessionOpenTimeoutMs).ConfigureAwait(false);
                    State = SessionState.Open;
                    Log("session: open");
                    return;
                }
                catch (BandException e) when (e.Kind == ErrorKind.Timeout) { }
            }
            State = SessionState.Idle;
            throw new BandException(ErrorKind.SessionOpenFailed);
        }

        public async Task CloseAsync()
        {
            FailAll(new BandException(ErrorKind.Cancelled));
            if (State == SessionState.Open || State == SessionState.Authenticated || State == SessionState.Opening)
            {
                try { await SessionExchange(SessionControl.Close(), SessionControl.CloseResponse, _cfg.SessionCloseTimeoutMs).ConfigureAwait(false); }
                catch (Exception) { }
            }
            lock (_gate) _keys = null;
            State = SessionState.Closed;
            Log("session: closed");
        }

        public void ConnectionLost()
        {
            FailAll(new BandException(ErrorKind.Disconnected));
            lock (_gate)
            {
                foreach (var e in _events) e.Value.TrySetResult(false);
                _events.Clear();
                _sessionWaiter?.Value.TrySetException(new BandException(ErrorKind.Disconnected));
                _sessionWaiter = null;
                _keys = null;
            }
            State = SessionState.Closed;
            _ackSignal.Release();
        }

        async Task<SessionControl> SessionExchange(SessionControl control, int code, int timeoutMs)
        {
            var tcs = new TaskCompletionSource<SessionControl>(TaskCreationOptions.RunContinuationsAsynchronously);
            lock (_gate)
            {
                _sessionWaiter?.Value.TrySetException(new BandException(ErrorKind.Cancelled));
                _sessionWaiter = new KeyValuePair<int, TaskCompletionSource<SessionControl>>(code, tcs);
            }
            try
            {
                await _transport.WriteAsync(new Frame(FrameType.Session, 0, control.Payload).Encoded()).ConfigureAwait(false);
                if (!await WithTimeout(tcs.Task, timeoutMs).ConfigureAwait(false)) throw new BandException(ErrorKind.Timeout);
                return await tcs.Task.ConfigureAwait(false);
            }
            finally
            {
                lock (_gate) { if (_sessionWaiter.HasValue && _sessionWaiter.Value.Value == tcs) _sessionWaiter = null; }
            }
        }

        // ---- Автентифікація

        bool _awaitConfirm;

        public Task SendPlainAsync(byte[] body) =>
            WriteData(new DataPacket(DataChannel.Protobuf, DataOpcode.Plain, body), false);

        public async Task AuthenticateAsync(byte[] authKey, string model = "Windows", string region = "UK")
        {
            if (authKey.Length != 16) throw new BandException(ErrorKind.InvalidAuthKey);
            if (State != SessionState.Open) throw new BandException(ErrorKind.SessionNotOpen);
            byte[] phoneNonce, bandNonce, bandHmac;
            for (int round = 0; ; round++)
            {
                phoneNonce = new byte[16];
                using (var rng = RandomNumberGenerator.Create()) rng.GetBytes(phoneNonce);
                _awaitConfirm = false;
                Log("auth: step 1");
                // Браслет у режимі очікування спершу чекає підтвердження користувача на екрані (до кількох десятків секунд)
                var step2 = await RequestAsync(Command.AuthPhoneNonce(phoneNonce), false, 60000, true, c => c.Matches(Command.Auth, 26)).ConfigureAwait(false);
                bandNonce = step2.Root.BytesAt(3, 31, 1);
                bandHmac = step2.Root.BytesAt(3, 31, 2);
                if (bandNonce == null || bandNonce.Length != 16 || bandHmac == null || bandHmac.Length != 32)
                    throw new BandException(ErrorKind.MalformedResponse, "auth step 2");
                if (_awaitConfirm && round < 2)
                {
                    // як Mi Fitness: після підтвердження на браслеті повідомляємо статус 7 і починаємо автентифікацію наново
                    Log("auth: confirmed on the band, restarting");
                    await SendPlainAsync(Command.AuthStatus(7)).ConfigureAwait(false);
                    await Task.Delay(200).ConfigureAwait(false);
                    continue;
                }
                if (!Bytes.ConstantTimeEqual(new SessionKeys(authKey, phoneNonce, bandNonce).ExpectedBandHmac(phoneNonce, bandNonce), bandHmac))
                    throw new BandException(ErrorKind.AuthKeyMismatch);
                break;
            }

            var keys = new SessionKeys(authKey, phoneNonce, bandNonce);
            var info = keys.EncryptPhoneInfo(Command.PhoneInfo(model, region));
            var confirmation = keys.PhoneConfirmation(phoneNonce, bandNonce);
            Log("auth: step 3");
            lock (_gate) _keys = keys;
            try
            {
                await RequestAsync(Command.AuthConfirm(confirmation, info), false, null, true, c => c.Matches(Command.Auth, 27, 5)).ConfigureAwait(false);
            }
            catch (Exception) { lock (_gate) _keys = null; throw; }
            State = SessionState.Authenticated;
            Log("auth: done");
        }

        // ---- Команди

        public async Task<Command> RequestAsync(byte[] body, bool encrypted, int? timeoutMs, bool redact, Func<Command, bool> match)
        {
            SessionKeys keys;
            lock (_gate) keys = _keys;
            if (encrypted && keys == null) throw new BandException(ErrorKind.NotAuthenticated);
            var w = new Waiter { Match = match, Tcs = new TaskCompletionSource<Command>(TaskCreationOptions.RunContinuationsAsynchronously) };
            lock (_gate) _waiters.Add(w);
            try
            {
                string name; try { name = new Command(body).Name; } catch (Exception) { name = "?"; }
                Log("→ cmd " + name + (redact ? "" : " " + body.Hex()));
                var payload = encrypted ? keys.EncryptCommand(body) : body;
                await WriteData(new DataPacket(DataChannel.Protobuf, encrypted ? DataOpcode.Encrypted : DataOpcode.Plain, payload), false).ConfigureAwait(false);
                if (!await WithTimeout(w.Tcs.Task, timeoutMs ?? _cfg.CommandTimeoutMs).ConfigureAwait(false)) throw new BandException(ErrorKind.Timeout);
                return await w.Tcs.Task.ConfigureAwait(false);
            }
            finally { lock (_gate) _waiters.Remove(w); }
        }

        public Task<Command> CommandAsync(byte[] body, int? timeoutMs = null)
        {
            var h = new Command(body);
            long t = h.Type, s = h.Subtype;
            return RequestAsync(body, true, timeoutMs, false, c => c.Type == t && c.Subtype == s);
        }

        void FailAll(Exception e)
        {
            List<Waiter> all;
            lock (_gate) { all = _waiters.ToList(); _waiters.Clear(); }
            foreach (var w in all) w.Tcs.TrySetException(e);
        }

        async Task WriteData(DataPacket p, bool trackAck)
        {
            byte[] bytes;
            lock (_gate)
            {
                bytes = new Frame(FrameType.Data, _phoneSeq, p.Payload).Encoded();
                if (trackAck) _unacked.Add(new Sent { Seq = _phoneSeq, Bytes = bytes });
                _phoneSeq = (_phoneSeq + 1) & 0xFF;
            }
            await _transport.WriteAsync(bytes).ConfigureAwait(false);
        }

        // ---- Файл

        public async Task SendFilePartsAsync(List<byte[]> parts, Action<int, int> progress, CancellationToken ct = default(CancellationToken))
        {
            if (State != SessionState.Authenticated) throw new BandException(ErrorKind.NotAuthenticated);
            Log("file: sending " + parts.Count + " parts");
            lock (_gate) { _unacked.Clear(); _unsolicited.Clear(); InstallStatus = null; }
            while (_ackSignal.CurrentCount > 0) _ackSignal.Wait(0);
            for (int i = 0; i < parts.Count; i++)
            {
                ct.ThrowIfCancellationRequested();
                await WaitAcks(Math.Max(_cfg.FileWindow, 1)).ConfigureAwait(false);
                await WriteData(new DataPacket(DataChannel.File, DataOpcode.Plain, parts[i]), true).ConfigureAwait(false);
                progress?.Invoke(i + 1, parts.Count);
            }
            Log("file: all parts sent, waiting for the band to confirm");
            await WaitAcks(1).ConfigureAwait(false);
            Log("file: all parts confirmed");
        }

        async Task WaitAcks(int limit)
        {
            int resends = 0;
            while (true)
            {
                int count; long? status; Sent first;
                lock (_gate) { count = _unacked.Count; status = InstallStatus; first = _unacked.FirstOrDefault(); }
                if (count < limit) return;
                if (status.HasValue && status.Value != InstalledStatus) throw new BandException(ErrorKind.InstallAborted, "", status.Value);
                if (State == SessionState.Closed) throw new BandException(ErrorKind.Disconnected);
                if (await _ackSignal.WaitAsync(_cfg.FileAckTimeoutMs).ConfigureAwait(false)) { resends = 0; continue; }
                resends++;
                if (resends > _cfg.FileResendAttempts || first == null) throw new BandException(ErrorKind.Timeout);
                List<Sent> copy; lock (_gate) copy = _unacked.ToList();
                Log("file: no ack, resending " + copy.Count + " parts from " + first.Seq);
                foreach (var f in copy) await _transport.WriteAsync(f.Bytes).ConfigureAwait(false);
            }
        }

        // ---- Вхідні кадри

        void Process(byte[] bytes)
        {
            List<Frame> frames;
            lock (_gate) frames = _parser.Append(bytes);
            foreach (var f in frames)
            {
                switch (f.Type)
                {
                    case FrameType.Session: HandleSession(f); break;
                    case FrameType.Ack:
                        Log("← ack " + f.Sequence);
                        lock (_gate)
                        {
                            int before = _unacked.Count;
                            _unacked.RemoveAll(u => ((f.Sequence - u.Seq) & 0xFF) < 128);
                            if (_unacked.Count != before) _ackSignal.Release();
                        }
                        break;
                    case FrameType.Data: HandleData(f); break;
                }
            }
        }

        void HandleSession(Frame f)
        {
            var c = SessionControl.Parse(f.Payload);
            if (c == null) return;
            Log("← session code " + c.Code);
            TaskCompletionSource<SessionControl> tcs = null;
            lock (_gate)
            {
                if (_sessionWaiter.HasValue && _sessionWaiter.Value.Key == c.Code) { tcs = _sessionWaiter.Value.Value; _sessionWaiter = null; }
            }
            tcs?.TrySetResult(c);
        }

        void HandleData(Frame f)
        {
            var ack = Frame.Ack(f.Sequence).Encoded();
            Log("→ ack " + f.Sequence);
            var _ = Task.Run(async () => { try { await _transport.WriteAsync(ack).ConfigureAwait(false); } catch (Exception) { } });

            SessionKeys keys;
            lock (_gate)
            {
                if (_expectedBand >= 0 && ((f.Sequence - _expectedBand) & 0xFF) >= 128) { Log("← data " + f.Sequence + " dropped"); return; }
                _expectedBand = (f.Sequence + 1) & 0xFF;
                keys = _keys;
            }
            var packet = DataPacket.Parse(f.Payload);
            if (packet == null) return;
            if (packet.Channel != DataChannel.Protobuf) { Log("← data channel " + packet.Channel); return; }
            byte[] body;
            if (packet.Opcode == DataOpcode.Encrypted)
            {
                if (keys == null) { Log("← encrypted without keys"); return; }
                body = keys.DecryptCommand(packet.Body);
            }
            else if (packet.Opcode == DataOpcode.Plain) body = packet.Body;
            else return;

            Command cmd;
            try { cmd = new Command(body); } catch (Exception) { Log("← undecodable command"); return; }
            bool redact = cmd.Type == Command.Auth;
            Log("← cmd " + cmd.Name + (redact ? "" : " " + body.Hex()));
            if (cmd.Type == Command.Auth && cmd.Subtype == 16) { _awaitConfirm = true; Log("auth: waiting for confirmation on the band"); }

            Waiter w = null;
            lock (_gate)
            {
                w = _waiters.FirstOrDefault(x => x.Match(cmd) && !x.Tcs.Task.IsCompleted);
                if (w != null) _waiters.Remove(w);
            }
            if (w != null) { w.Tcs.TrySetResult(cmd); return; }

            List<KeyValuePair<string, TaskCompletionSource<bool>>> hit;
            lock (_gate)
            {
                _unsolicited.Add(cmd.Name);
                if (cmd.Type == Command.Watchface && cmd.Subtype == 5)
                {
                    InstallStatus = cmd.Root.VarintAt(6, 7, 2);
                    Log("install status " + (InstallStatus.HasValue ? InstallStatus.Value.ToString() : "?"));
                    _ackSignal.Release();
                }
                hit = _events.Where(e => e.Key == cmd.Name).ToList();
                _events.RemoveAll(e => e.Key == cmd.Name);
            }
            foreach (var e in hit) e.Value.TrySetResult(true);
        }

        public async Task<bool> WaitForAsync(long type, long subtype, int timeoutMs)
        {
            string name = type + "/" + subtype;
            var tcs = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
            var entry = new KeyValuePair<string, TaskCompletionSource<bool>>(name, tcs);
            lock (_gate)
            {
                if (_unsolicited.Contains(name)) return true;
                _events.Add(entry);
            }
            bool ok = await WithTimeout(tcs.Task, timeoutMs).ConfigureAwait(false) && tcs.Task.Result;
            lock (_gate) _events.Remove(entry);
            return ok;
        }
    }
}
