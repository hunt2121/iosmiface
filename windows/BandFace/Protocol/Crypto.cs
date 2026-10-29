// SPDX-License-Identifier: MIT
using System;
using System.Security.Cryptography;
using System.Text;

namespace BandFace.Protocol
{
    public static class BandCrypto
    {
        static byte[] AesBlock(byte[] key, byte[] block)
        {
            using (var aes = Aes.Create())
            {
                aes.Mode = CipherMode.ECB;
                aes.Padding = PaddingMode.None;
                aes.Key = key;
                using (var enc = aes.CreateEncryptor()) return enc.TransformFinalBlock(block, 0, 16);
            }
        }

        /// <summary>AES-128-CTR; лічильник — увесь блок як big-endian число.</summary>
        public static byte[] AesCtr(byte[] key, byte[] iv, byte[] data)
        {
            var counter = (byte[])iv.Clone();
            var outp = new byte[data.Length];
            using (var aes = Aes.Create())
            {
                aes.Mode = CipherMode.ECB;
                aes.Padding = PaddingMode.None;
                aes.Key = key;
                using (var enc = aes.CreateEncryptor())
                {
                    for (int off = 0; off < data.Length; off += 16)
                    {
                        var ks = enc.TransformFinalBlock(counter, 0, 16);
                        int n = Math.Min(16, data.Length - off);
                        for (int k = 0; k < n; k++) outp[off + k] = (byte)(data[off + k] ^ ks[k]);
                        for (int i = 15; i >= 0; i--) { counter[i]++; if (counter[i] != 0) break; }
                    }
                }
            }
            return outp;
        }

        /// <summary>AES-128-CCM (RFC 3610) без додаткових даних: шифротекст ‖ тег.</summary>
        public static byte[] AesCcmEncrypt(byte[] key, byte[] nonce, byte[] plain, int tagLen = 4)
        {
            int l = 15 - nonce.Length;
            Func<int, byte[]> lenField = v =>
            {
                var r = new byte[l];
                for (int i = 0; i < l; i++) r[i] = (byte)(v >> (8 * (l - 1 - i)));
                return r;
            };
            byte flagsB0 = (byte)((((tagLen - 2) / 2) << 3) | (l - 1));
            var mac = AesBlock(key, Bytes.Concat(new[] { flagsB0 }, nonce, lenField(plain.Length)));
            for (int off = 0; off < plain.Length; off += 16)
            {
                var block = new byte[16];
                int n = Math.Min(16, plain.Length - off);
                Buffer.BlockCopy(plain, off, block, 0, n);
                for (int k = 0; k < 16; k++) mac[k] ^= block[k];
                mac = AesBlock(key, mac);
            }
            byte flagsA = (byte)(l - 1);
            Func<int, byte[]> ctr = i => Bytes.Concat(new[] { flagsA }, nonce, lenField(i));
            var outp = new byte[plain.Length + tagLen];
            int c = 1;
            for (int off = 0; off < plain.Length; off += 16, c++)
            {
                var s = AesBlock(key, ctr(c));
                int n = Math.Min(16, plain.Length - off);
                for (int k = 0; k < n; k++) outp[off + k] = (byte)(plain[off + k] ^ s[k]);
            }
            var s0 = AesBlock(key, ctr(0));
            for (int k = 0; k < tagLen; k++) outp[plain.Length + k] = (byte)(mac[k] ^ s0[k]);
            return outp;
        }

        public static byte[] HmacSha256(byte[] key, byte[] data)
        {
            using (var h = new HMACSHA256(key.Length == 0 ? new byte[1] : key)) return h.ComputeHash(data);
        }

        public static byte[] Md5(byte[] data)
        {
            using (var m = MD5.Create()) return m.ComputeHash(data);
        }

        public static byte[] Sha1(byte[] data)
        {
            using (var m = SHA1.Create()) return m.ComputeHash(data);
        }

        public static byte[] Sha256(byte[] data)
        {
            using (var m = SHA256.Create()) return m.ComputeHash(data);
        }

        /// <summary>HKDF-SHA256 (RFC 5869).</summary>
        public static byte[] Hkdf(byte[] ikm, byte[] salt, byte[] info, int length)
        {
            var prk = HmacSha256(salt, ikm);
            var okm = new byte[0];
            var prev = new byte[0];
            for (int c = 1; okm.Length < length; c++)
            {
                prev = HmacSha256(prk, Bytes.Concat(prev, info, new[] { (byte)c }));
                okm = Bytes.Concat(okm, prev);
            }
            return okm.Slice(0, length);
        }
    }

    /// <summary>Ключі однієї сесії, виведені з auth key та двох nonce.</summary>
    public sealed class SessionKeys
    {
        public byte[] DecryptionKey { get; }
        public byte[] EncryptionKey { get; }
        public byte[] EncryptionNonce { get; }

        public SessionKeys(byte[] authKey, byte[] phoneNonce, byte[] bandNonce)
        {
            var m = BandCrypto.Hkdf(authKey, Bytes.Concat(phoneNonce, bandNonce), Encoding.ASCII.GetBytes("miwear-auth"), 64);
            DecryptionKey = m.Slice(0, 16);
            EncryptionKey = m.Slice(16, 32);
            EncryptionNonce = m.Slice(36, 40);
        }

        public byte[] ExpectedBandHmac(byte[] phoneNonce, byte[] bandNonce) =>
            BandCrypto.HmacSha256(DecryptionKey, Bytes.Concat(bandNonce, phoneNonce));

        public byte[] PhoneConfirmation(byte[] phoneNonce, byte[] bandNonce) =>
            BandCrypto.HmacSha256(EncryptionKey, Bytes.Concat(phoneNonce, bandNonce));

        public byte[] EncryptPhoneInfo(byte[] plain) =>
            BandCrypto.AesCcmEncrypt(EncryptionKey, Bytes.Concat(EncryptionNonce, new byte[8]), plain, 4);

        public byte[] EncryptCommand(byte[] body) => BandCrypto.AesCtr(EncryptionKey, EncryptionKey, body);
        public byte[] DecryptCommand(byte[] body) => BandCrypto.AesCtr(DecryptionKey, DecryptionKey, body);
    }
}
