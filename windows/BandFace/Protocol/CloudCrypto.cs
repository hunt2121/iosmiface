using System;
using System.Collections.Generic;
using System.Security.Cryptography;
using System.Text;

namespace BandFace.Protocol
{
    /// <summary>Підписи й RC4-шифрування запитів до хмари Xiaomi (Mi Fitness).</summary>
    public static class CloudCrypto
    {
        static readonly UTF8Encoding Utf8 = new UTF8Encoding(false);

        /// <summary>RC4 з відкиданням перших 1024 байтів потоку ключа.</summary>
        public static byte[] Rc4(byte[] key, byte[] data)
        {
            var s = new byte[256];
            for (int k = 0; k < 256; k++) s[k] = (byte)k;
            for (int k = 0, j0 = 0; k < 256; k++)
            {
                j0 = (j0 + s[k] + key[k % key.Length]) & 255;
                byte t = s[k]; s[k] = s[j0]; s[j0] = t;
            }
            var o = new byte[data.Length];
            int i = 0, j = 0;
            for (int n = -1024; n < data.Length; n++)
            {
                i = (i + 1) & 255; j = (j + s[i]) & 255;
                byte t = s[i]; s[i] = s[j]; s[j] = t;
                if (n >= 0) o[n] = (byte)(data[n] ^ s[(s[i] + s[j]) & 255]);
            }
            return o;
        }

        static string B64(byte[] b) => Convert.ToBase64String(b);

        public static string SignedNonce(string ssecurity, string nonce)
        {
            var a = Convert.FromBase64String(ssecurity);
            var b = Convert.FromBase64String(nonce);
            var all = new byte[a.Length + b.Length];
            Buffer.BlockCopy(a, 0, all, 0, a.Length);
            Buffer.BlockCopy(b, 0, all, a.Length, b.Length);
            using (var h = SHA256.Create()) return B64(h.ComputeHash(all));
        }

        public static string ClientSign(string nonce, string ssecurity)
        {
            using (var h = SHA1.Create()) return B64(h.ComputeHash(Utf8.GetBytes("nonce=" + nonce + "&" + ssecurity)));
        }

        static string EncSig(string path, string signed, List<KeyValuePair<string, string>> p)
        {
            var parts = new List<string> { "POST", path };
            foreach (var kv in p) parts.Add(kv.Key + "=" + kv.Value);
            parts.Add(signed);
            using (var h = SHA1.Create()) return B64(h.ComputeHash(Utf8.GetBytes(string.Join("&", parts))));
        }

        static KeyValuePair<string, string> P(string k, string v) => new KeyValuePair<string, string>(k, v);

        /// <summary>Варіант «mihome»: кожне поле шифрується окремо, параметри йдуть у рядку запиту.</summary>
        public static List<KeyValuePair<string, string>> BuildEnc(string path, string data, string ssecurity, string nonce)
        {
            var signed = SignedNonce(ssecurity, nonce);
            var key = Convert.FromBase64String(signed);
            var plain = new List<KeyValuePair<string, string>> { P("data", data) };
            plain.Add(P("rc4_hash__", EncSig(path, signed, plain)));
            var enc = new List<KeyValuePair<string, string>>();
            foreach (var kv in plain) enc.Add(P(kv.Key, B64(Rc4(key, Utf8.GetBytes(kv.Value)))));
            enc.Add(P("signature", EncSig(path, signed, enc)));
            enc.Add(P("ssecurity", ssecurity));
            enc.Add(P("_nonce", nonce));
            return enc;
        }

        /// <summary>Варіант «stream»: один потік RC4 на всі впорядковані поля, тіло форми.</summary>
        public static List<KeyValuePair<string, string>> BuildStream(string path, string data, string ssecurity, string nonce)
        {
            var signed = SignedNonce(ssecurity, nonce);
            var plain = new List<KeyValuePair<string, string>> { P("data", data) };
            var hash = EncSig(path, signed, plain);
            var all = new SortedDictionary<string, string>(StringComparer.Ordinal) { { "data", data }, { "rc4_hash__", hash } };
            var sb = new StringBuilder();
            foreach (var kv in all) sb.Append(kv.Value);
            var stream = Rc4(Convert.FromBase64String(signed), Utf8.GetBytes(sb.ToString()));
            var outp = new List<KeyValuePair<string, string>>();
            int at = 0;
            foreach (var kv in all)
            {
                int len = Utf8.GetByteCount(kv.Value);
                var part = new byte[len];
                Buffer.BlockCopy(stream, at, part, 0, len);
                at += len;
                outp.Add(P(kv.Key, B64(part)));
            }
            outp.Add(P("signature", EncSig(path, signed, outp)));
            outp.Add(P("_nonce", nonce));
            return outp;
        }

        public static string Decrypt(string ssecurity, string nonce, string body)
        {
            var key = Convert.FromBase64String(SignedNonce(ssecurity, nonce));
            return Utf8.GetString(Rc4(key, Convert.FromBase64String(body.Trim().Trim('"'))));
        }

        /// <summary>12 байтів: 8 випадкових + хвилини від епохи (big-endian).</summary>
        public static string MakeNonce()
        {
            var n = new byte[12];
            using (var r = RandomNumberGenerator.Create()) r.GetBytes(n);
            long min = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds() / 60000;
            n[8] = (byte)(min >> 24); n[9] = (byte)(min >> 16); n[10] = (byte)(min >> 8); n[11] = (byte)min;
            return B64(n);
        }
    }
}
