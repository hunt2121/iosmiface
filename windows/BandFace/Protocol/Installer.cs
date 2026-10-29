// SPDX-License-Identifier: MIT
using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;

namespace BandFace.Protocol
{
    public enum Phase { Connecting, Authenticating, RequestingInstall, RemovingOldVersion, Uploading, Activating, Closing, Done }

    public sealed class InstallProgress
    {
        public Phase Phase; public int Sent; public int Total; public bool AlreadyInstalled;
    }

    /// <summary>Сценарій: відкриття → автентифікація → 4/4 → 22/0 → файл → закриття.</summary>
    public sealed class WatchfaceInstaller
    {
        public string PhoneModel = "Windows";
        public string Region = "UK";
        public int PauseAfterAuthMs = 500, PauseBeforeInstallMs = 300, WaitForInstallStatusMs = 1500;
        public int ActivationTimeoutMs = 4000, ActivationAttempts = 2;

        enum Check { NeedsUpload, AlreadyInstalled, AlreadyActive }

        public async Task InstallAsync(FaceFile face, byte[] authKey, BandSession s, Action<InstallProgress> on, CancellationToken ct = default(CancellationToken))
        {
            Action<Phase> ph = p => on?.Invoke(new InstallProgress { Phase = p });
            ph(Phase.Connecting);
            await s.OpenAsync().ConfigureAwait(false);
            try
            {
                ph(Phase.Authenticating);
                await s.AuthenticateAsync(authKey, PhoneModel, Region).ConfigureAwait(false);
                await Task.Delay(PauseAfterAuthMs, ct).ConfigureAwait(false);
                try { await s.CommandAsync(Command.DeviceInfoRequest()).ConfigureAwait(false); } catch (BandException) { }
                try { await s.CommandAsync(Command.BatteryRequest()).ConfigureAwait(false); } catch (BandException) { }
                await Task.Delay(PauseBeforeInstallMs, ct).ConfigureAwait(false);

                var check = await RequestInstall(face, s, ph).ConfigureAwait(false);
                if (check == Check.NeedsUpload)
                {
                    await Upload(face, s, on, ct).ConfigureAwait(false);
                    await s.WaitForAsync(Command.Watchface, 5, WaitForInstallStatusMs).ConfigureAwait(false);
                    var st = s.InstallStatus;
                    if (st.HasValue && st.Value != BandSession.InstalledStatus) throw new BandException(ErrorKind.InstallAborted, "", st.Value);
                }
                else if (check == Check.AlreadyInstalled)
                {
                    ph(Phase.Activating);
                    await Activate(face, s).ConfigureAwait(false);
                }
                ph(Phase.Closing);
                await s.CloseAsync().ConfigureAwait(false);
                on?.Invoke(new InstallProgress { Phase = Phase.Done, AlreadyInstalled = check != Check.NeedsUpload });
            }
            catch (Exception)
            {
                await s.CloseAsync().ConfigureAwait(false);
                throw;
            }
        }

        async Task<Check> RequestInstall(FaceFile face, BandSession s, Action<Phase> ph)
        {
            ph(Phase.RequestingInstall);
            bool removed = false;
            while (true)
            {
                var r = await s.CommandAsync(Command.InstallRequest(face.Id, face.Size)).ConfigureAwait(false);
                long status = r.Root.VarintAt(6, 5) ?? 0;
                if (status == 0) return Check.NeedsUpload;
                if (status == 2) return Check.AlreadyInstalled;
                if (removed) throw new BandException(ErrorKind.InstallRejected, "", status);
                var list = WatchfaceEntry.List(await s.CommandAsync(Command.WatchfaceListRequest()).ConfigureAwait(false));
                var old = list.FirstOrDefault(x => x.Id == face.Id);
                if (old == null) throw new BandException(ErrorKind.InstallRejected, "", status);
                if (old.IsActive) return Check.AlreadyActive;
                if (!old.CanDelete) throw new BandException(ErrorKind.InstallRejected, "", status);
                ph(Phase.RemovingOldVersion);
                await s.CommandAsync(Command.DeleteWatchface(face.Id)).ConfigureAwait(false);
                removed = true;
            }
        }

        async Task Activate(FaceFile face, BandSession s)
        {
            for (int a = 1; a <= Math.Max(ActivationAttempts, 1); a++)
            {
                try
                {
                    var r = await s.CommandAsync(Command.ActivateWatchface(face.Id), ActivationTimeoutMs).ConfigureAwait(false);
                    var res = r.Root.VarintAt(6, 4);
                    if (res.HasValue && res.Value != 1) throw new BandException(ErrorKind.ActivationFailed);
                    return;
                }
                catch (BandException e) when (e.Kind == ErrorKind.Timeout && a < ActivationAttempts) { }
            }
        }

        async Task Upload(FaceFile face, BandSession s, Action<InstallProgress> on, CancellationToken ct)
        {
            var md5 = face.Md5;
            var resp = new UploadResponse(await s.CommandAsync(Command.UploadRequest(md5, face.Size)).ConfigureAwait(false));
            if (resp.Status != 0) throw new BandException(ErrorKind.UploadRejected, "", resp.Status);
            if (resp.ChunkSize <= 4) throw new BandException(ErrorKind.MalformedResponse, "chunk size");
            var parts = FileTransfer.Parts(face.Data, md5, resp.ResumePosition, resp.ChunkSize);
            on?.Invoke(new InstallProgress { Phase = Phase.Uploading, Sent = 0, Total = parts.Count });
            await s.SendFilePartsAsync(parts, (sent, total) =>
                on?.Invoke(new InstallProgress { Phase = Phase.Uploading, Sent = sent, Total = total }), ct).ConfigureAwait(false);
        }
    }
}
