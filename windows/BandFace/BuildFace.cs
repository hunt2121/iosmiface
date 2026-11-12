// SPDX-License-Identifier: MIT
// Збирання циферблата з теки проєкту без вікна (для збіркового сервера): --build-face=<тека>|<файл.bin>
// Поруч пише журнал компілятора й кадри кожної теми, намальовані вже з готового .bin (перевірка повного кола).

using System;
using System.IO;
using System.Linq;
using System.Windows.Media.Imaging;
using BandFace.Creator;

namespace BandFace
{
    static class BuildFace
    {
        public static int Run(string spec)
        {
            var parts = spec.Split('|');
            var folder = parts[0]; var outBin = parts.Length > 1 ? parts[1] : Path.Combine(folder, "face.bin");
            try
            {
                var p = FaceProject.Load(folder);
                if (p == null) { File.WriteAllText(outBin + ".log", "cannot load " + folder); return 2; }
                p.Meta.Edited = true;                     // превʼю для браслета малюються заново
                var r = p.Compile();
                File.WriteAllBytes(outBin, r.Item1);
                File.WriteAllLines(outBin + ".log", r.Item2.DefaultIfEmpty("no warnings"));
                var u = FaceProject.Unpack(r.Item1);
                var q = new FaceProject("check", null, u.Item1, u.Item2, new ProjectMeta());
                for (int t = 0; t < q.Themes.Count; t++)
                {
                    var img = new FaceRenderer(q).Render(t, 2).Image;
                    var enc = new PngBitmapEncoder(); enc.Frames.Add(BitmapFrame.Create(img));
                    using (var fs = File.Create(outBin + ".theme" + t + ".png")) enc.Save(fs);
                }
                return 0;
            }
            catch (Exception ex) { File.WriteAllText(outBin + ".log", ex.ToString()); return 1; }
        }
    }
}
