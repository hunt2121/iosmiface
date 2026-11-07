using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows.Media.Imaging;
using BandFace.Creator;
using BandFace.Faces;

namespace BandFace
{
    sealed class PreviewShots
    {
        public readonly List<BitmapSource> Frames = new List<BitmapSource>();
        public int IntervalMs = 100;
    }

    /// <summary>
    /// Превʼю циферблата для вкладки «Циферблати», як в iOS: малюється з ресурсів .bin рушієм редактора,
    /// рівно під висоту капсули. Якщо на основному екрані є анімація (Sprite) — кадри з кроком її інтервалу (до 60).
    /// </summary>
    static class FacePreview
    {
        const int MaxFrames = 60;

        /// <returns>null — не вдалося намалювати (тоді показуємо вбудоване у файл превʼю).</returns>
        public static PreviewShots Render(byte[] bin, double heightPx)
        {
            try
            {
                var u = FaceProject.Unpack(bin);
                var p = new FaceProject("preview", null, u.Item1, u.Item2, new ProjectMeta());
                var r = new FaceRenderer(p);
                double scale = heightPx / p.Meta.Device.Height;
                var shots = new PreviewShots();

                var sprites = p.Layouts(0).Select(p.ElementOf).Where(e => e != null && e.Tag == "Sprite").ToList();
                int count = sprites.Count == 0 ? 1
                    : Math.Min(MaxFrames, sprites.Max(sp => Math.Max(1, r.Frames(p.ResourceRef(sp.Str("ref"))).Count)));
                if (sprites.Count > 0) shots.IntervalMs = Math.Max(30, sprites[0].Int("interval", 100));
                for (int i = 0; i < count; i++)
                {
                    r.Time = i * shots.IntervalMs / 1000.0;
                    shots.Frames.Add(r.Render(0, scale).Image);
                }
                return shots;
            }
            catch (Exception) { return null; }
        }
    }
}
