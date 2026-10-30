// SPDX-License-Identifier: MIT
using System.Collections.Generic;
using System.Linq;

namespace BandFace.Protocol
{
    /// <summary>Повідомлення «Команда» (protobuf).</summary>
    public sealed class Command
    {
        public const long Auth = 1, System = 2, Watchface = 4, DataUpload = 22, UploadTypeWatchface = 16;
        public long Type { get; }
        public long Subtype { get; }
        public ProtoMessage Root { get; }
        public string Name => Type + "/" + Subtype;

        public Command(byte[] body)
        {
            Root = ProtoMessage.Parse(body);
            var t = Root.Varint(1);
            if (!t.HasValue) throw new BandException(ErrorKind.MalformedResponse, "command without type");
            Type = t.Value;
            Subtype = Root.Varint(2) ?? 0;
        }

        public bool Matches(long type, params long[] subtypes) => Type == type && subtypes.Contains(Subtype);

        static byte[] Build(long type, long subtype, System.Action<ProtoWriter> fill = null)
        {
            var w = new ProtoWriter().WriteVarint(1, type).WriteVarint(2, subtype);
            fill?.Invoke(w);
            return w.Output;
        }

        public static byte[] AuthPhoneNonce(byte[] nonce) =>
            Build(Auth, 26, w => w.WriteMessage(3, a => a.WriteMessage(30, m => m.WriteBytes(1, nonce))));

        /// <summary>Підтвердження старту автентифікації: Mi Fitness шле його після відповіді «чекаю підтвердження».</summary>
        public static byte[] AuthStatus(int status) =>
            Build(Auth, 27, w => w.WriteMessage(3, a => a.WriteVarint(3, status)));

        public static byte[] AuthConfirm(byte[] confirmation, byte[] encryptedInfo) =>
            Build(Auth, 27, w => w.WriteMessage(3, a => a.WriteMessage(32, m => m.WriteBytes(1, confirmation).WriteBytes(2, encryptedInfo))));

        public static byte[] PhoneInfo(string model = "Windows", string region = "UK") =>
            new ProtoWriter().WriteVarint(1, 0).WriteFloat(2, 34.0f).WriteString(3, model).WriteVarint(4, 224).WriteString(5, region).Output;

        public static byte[] DeviceInfoRequest() => Build(System, 2);
        public static byte[] BatteryRequest() => Build(System, 1);
        public static byte[] WatchfaceListRequest() => Build(Watchface, 0);
        public static byte[] ActivateWatchface(string id) => Build(Watchface, 1, w => w.WriteMessage(6, m => m.WriteString(2, id)));
        public static byte[] DeleteWatchface(string id) => Build(Watchface, 2, w => w.WriteMessage(6, m => m.WriteString(2, id)));

        public static byte[] InstallRequest(string id, int size) =>
            Build(Watchface, 4, w => w.WriteMessage(6, f => f.WriteMessage(6, m => m.WriteString(1, id).WriteVarint(2, size))));

        public static byte[] UploadRequest(byte[] md5, int size, long type = UploadTypeWatchface) =>
            Build(DataUpload, 0, w => w.WriteMessage(24, d => d.WriteMessage(1, m => m.WriteVarint(1, type).WriteBytes(2, md5).WriteVarint(3, size))));
    }

    public sealed class WatchfaceEntry
    {
        public string Id; public bool IsActive; public bool CanDelete;

        static WatchfaceEntry From(ProtoMessage m)
        {
            var id = m.String(1);
            return id == null ? null : new WatchfaceEntry { Id = id, IsActive = m.Bool(3) ?? false, CanDelete = m.Bool(4) ?? false };
        }

        public static List<WatchfaceEntry> List(Command c)
        {
            var container = c.Root.MessageAt(6, 1);
            if (container != null)
            {
                var e = container.Messages(1).Select(From).Where(x => x != null).ToList();
                if (e.Count > 0) return e;
            }
            var six = c.Root.Message(6);
            return six == null ? new List<WatchfaceEntry>() : six.Messages(1).Select(From).Where(x => x != null).ToList();
        }
    }

    public sealed class UploadResponse
    {
        public long Status; public int ResumePosition; public int ChunkSize;
        public UploadResponse(Command c)
        {
            Status = c.Root.VarintAt(24, 2, 2) ?? 0;
            ResumePosition = (int)(c.Root.VarintAt(24, 2, 4) ?? 0);
            ChunkSize = (int)(c.Root.VarintAt(24, 2, 5) ?? 4096);
        }
    }

    public static class FileTransfer
    {
        public static byte[] Stream(byte[] file, byte[] md5, int resume = 0)
        {
            int start = System.Math.Min(System.Math.Max(resume, 0), file.Length);
            var body = new ByteBuilder().U8(0x00).U8(0x10).Add(md5).Le32(file.Length).Add(file, start, file.Length).ToArray();
            return new ByteBuilder().Add(body).Le32(Checksum.Crc32(body)).ToArray();
        }

        public static List<byte[]> Parts(byte[] stream, int chunkSize)
        {
            int partLen = chunkSize - 4;
            int total = (stream.Length + partLen - 1) / partLen;
            var parts = new List<byte[]>(total);
            int off = 0, index = 1;
            while (off < stream.Length)
            {
                int end = System.Math.Min(off + partLen, stream.Length);
                parts.Add(new ByteBuilder().Le16(total).Le16(index).Add(stream, off, end).ToArray());
                off = end; index++;
            }
            return parts;
        }

        public static List<byte[]> Parts(byte[] file, byte[] md5, int resume, int chunkSize) =>
            Parts(Stream(file, md5, resume), chunkSize);
    }
}
