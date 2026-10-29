using System;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using Microsoft.Win32;

namespace BandFace
{
    /// <summary>Світла/темна тема за налаштуваннями Windows.</summary>
    static class Theme
    {
        [DllImport("dwmapi.dll")]
        static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);

        public static bool SystemIsDark()
        {
            try
            {
                using (var k = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"))
                    return k != null && Convert.ToInt32(k.GetValue("AppsUseLightTheme", 1)) == 0;
            }
            catch (Exception) { return false; }
        }

        static SolidColorBrush B(string hex) => new SolidColorBrush((Color)ColorConverter.ConvertFromString(hex));

        public static void Apply(Window window)
        {
            bool dark = SystemIsDark();
            var r = Application.Current.Resources;
            r["Bg"] = B(dark ? "#202020" : "#F3F3F3");
            r["Card"] = B(dark ? "#2B2B2B" : "#FFFFFF");
            r["CardBorder"] = B(dark ? "#3A3A3A" : "#E3E3E3");
            r["Text"] = B(dark ? "#F2F2F2" : "#1B1B1B");
            r["Sub"] = B(dark ? "#A8A8A8" : "#5D5D5D");
            r["Accent"] = B(dark ? "#7AA2F0" : "#2D5DA8");
            r["AccentText"] = B(dark ? "#0B1B3A" : "#FFFFFF");
            r["BtnBg"] = B(dark ? "#383838" : "#FDFDFD");
            r["BtnHover"] = B(dark ? "#444444" : "#F0F0F0");
            r["BtnBorder"] = B(dark ? "#4A4A4A" : "#D1D1D1");
            r["Track"] = B(dark ? "#444444" : "#E1E1E1");
            r["NavSel"] = B(dark ? "#333333" : "#E6E6E6");
            r["Ok"] = B(dark ? "#6CCB6C" : "#107C10");
            r["Err"] = B(dark ? "#FF8A80" : "#B3261E");
            r["Field"] = B(dark ? "#323232" : "#FFFFFF");
            if (window != null)
            {
                var h = new WindowInteropHelper(window).Handle;
                if (h != IntPtr.Zero)
                {
                    int v = dark ? 1 : 0;
                    DwmSetWindowAttribute(h, 20, ref v, 4);
                }
            }
        }
    }
}
