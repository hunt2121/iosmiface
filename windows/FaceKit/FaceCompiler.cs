// SPDX-License-Identifier: MIT
// Публічний інтерфейс компілятора циферблатів (порт WatchfaceCompiler 0.9.8).

using System;
using System.Collections.Generic;
using System.Linq;

namespace BandFace.Faces
{
    public static class WatchfaceCompiler
    {
        public const string Version = "0.9.8";

        /// <summary>.bin → файли проєкту (manifest.xml, PNG, Lua тощо).</summary>
        public static FaceUnpacker Unpack(byte[] data, IFaceStorage storage, FaceCompilerOptions options = null, FaceCompilerLog log = null)
        {
            log = log ?? new FaceCompilerLog();
            log.Info("Loading watchface binary...");
            var u = new FaceUnpacker(data, options, log);
            log.Info("Loaded!");
            u.Save(storage);
            return u;
        }

        /// <summary>Файли проєкту → .bin.</summary>
        public static byte[] Build(IFaceStorage storage, FaceCompilerOptions options = null, FaceCompilerLog log = null)
            => new FaceBuilder(storage, options, log).Build();
    }

    /// <summary>Декодування зображень для збирання: PNG — власним декодером (як stb_image), інші формати — системою.</summary>
    public static class ImageDecoder
    {
        /// <summary>JPEG/BMP/GIF тощо: задає застосунок (WPF), RGBA без розмноження.</summary>
        public static Func<byte[], RgbaImage> Fallback;

        public static RgbaImage Decode(byte[] d)
        {
            var p = Png.Decode(d);
            if (p != null) return p;
            try { return Fallback?.Invoke(d); } catch (Exception) { return null; }
        }
    }

    /// <summary>Довідники для редактора.</summary>
    public static class FaceCatalog
    {
        /// <summary>Усі джерела даних: (назва, id) у порядку exe.</summary>
        public static IEnumerable<Tuple<string, ushort>> Sources => FaceTables.Sources;
        public static IEnumerable<string> JumpApps => FaceTables.JumpApps.Select(x => x.Item2);
        public static IEnumerable<string> FontIds => FaceTables.FontIds.Select(x => x.Item1);
        public static IEnumerable<string> FontWeights => FaceTables.FontWeights.Select(x => x.Item1);
        public static IEnumerable<string> AppWidgets => FaceTables.AppWidgets.Select(x => x.Item1);

        /// <summary>Кількість кольорів (до limit): чи вміщається зображення в indexed8.</summary>
        public static int ColorCount(byte[] rgba, int limit = 257)
        {
            var set = new HashSet<uint>();
            for (int i = 0; i + 3 < rgba.Length; i += 4)
            {
                set.Add(rgba[i] | (uint)rgba[i + 1] << 8 | (uint)rgba[i + 2] << 16 | (uint)rgba[i + 3] << 24);
                if (set.Count >= limit) break;
            }
            return set.Count;
        }
    }
}
