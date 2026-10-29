using System;
using System.IO;
using System.Security.Cryptography;
using System.Text;

namespace BandFace
{
    /// <summary>Ключ браслета: файл у %AppData%\BandFace, зашифрований DPAPI (лише для цього користувача Windows).</summary>
    static class Storage
    {
        static string PathOf(string name)
        {
            var dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "BandFace");
            Directory.CreateDirectory(dir);
            return Path.Combine(dir, name);
        }

        public static string LoadKey()
        {
            try
            {
                var p = PathOf("key.bin");
                if (!File.Exists(p)) return "";
                return Encoding.ASCII.GetString(ProtectedData.Unprotect(File.ReadAllBytes(p), null, DataProtectionScope.CurrentUser));
            }
            catch (Exception) { return ""; }
        }

        public static void SaveKey(string hex)
        {
            try { File.WriteAllBytes(PathOf("key.bin"), ProtectedData.Protect(Encoding.ASCII.GetBytes(hex), null, DataProtectionScope.CurrentUser)); }
            catch (Exception) { }
        }

        public static bool LoadDev()
        {
            try { return File.Exists(PathOf("dev.flag")); } catch (Exception) { return false; }
        }

        public static void SaveDev(bool on)
        {
            try { var p = PathOf("dev.flag"); if (on) File.WriteAllText(p, "1"); else if (File.Exists(p)) File.Delete(p); }
            catch (Exception) { }
        }
    }
}
