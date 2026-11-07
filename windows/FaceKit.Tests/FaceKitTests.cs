// SPDX-License-Identifier: MIT
// Перевірки C#-порту компілятора: ті самі, що в Swift-версії, і прогін справжніх циферблатів.

using System.Collections.Generic;
using System.IO;
using System.Text;
using BandFace.Faces;
using Xunit;

public class FaceKitTests
{
    static byte[] U(string s) => Encoding.UTF8.GetBytes(s);

    [Fact]
    public void ToIntLikeTinyXml()
    {
        Assert.Equal(12, Num.ToInt(U(" 12px")));
        Assert.Equal(-7, Num.ToInt(U("-7")));
        Assert.Equal(31, Num.ToInt(U("0x1F")));
        Assert.Null(Num.ToInt(U("abc")));
        Assert.True(Num.ToBool(U("True")));
        Assert.True(Num.ToBool(U("2")));
    }

    [Fact]
    public void RleRoundtrip()
    {
        var raw = new List<byte>();
        for (int i = 0; i < 5000; i++) { raw.Add((byte)((i / 37) % 7)); raw.Add((byte)(i % 3)); raw.Add(9); }
        var block = Rle.Block(raw.ToArray(), 3);
        Assert.Equal(raw.ToArray(), Rle.Decompress(block, 8, raw.Count, 3));
    }

    [Fact]
    public void PngRoundtrip()
    {
        int w = 37, h = 23;
        var px = new byte[w * h * 4];
        for (int i = 0; i < px.Length; i++) px[i] = (byte)((i * 7 + i / 13) & 0xFF);
        var img = Png.Decode(Png.Encode(w, h, px));
        Assert.NotNull(img);
        Assert.Equal(w, img.W); Assert.Equal(h, img.H); Assert.Equal(px, img.Px);
    }

    [Fact]
    public void IndexedPngDecodes()
    {
        var idx = new byte[] { 0, 1, 1, 0 };
        var pal = new byte[] { 255, 0, 0, 0, 0, 255 };
        var img = Png.Decode(Png.EncodeIndexed(2, 2, idx, pal));
        Assert.Equal(new byte[] { 255, 0, 0, 255, 0, 0, 255, 255, 0, 0, 255, 255, 255, 0, 0, 255 }, img.Px);
    }

    /// <summary>Новий циферблат із нуля → .bin → розпакування → знову .bin: результат однаковий (як у Swift-тесті).</summary>
    [Fact]
    public void BuildUnpackBuild()
    {
        int w = 20, h = 10;
        var px = new byte[w * h * 4];
        for (int i = 0; i < px.Length; i += 4) { px[i] = 200; px[i + 1] = (byte)(i % 256); px[i + 2] = 40; px[i + 3] = 255; }
        var manifest = @"<?xml version=""1.0"" encoding=""UTF-8""?>
<Watchface id=""123456789"" name=""Test"">
    <Resources>
        <Image name=""bg"" src=""bg.png"" compressMethod=""RLEReversed"" format=""indexed8"" recolorEnable=""false""/>
        <ImageArray name=""digits"" compressMethod=""RLEReversed"" format=""indexed8"" recolorEnable=""false"">
            <Image src=""d/0.png""/>
            <Image src=""d/1.png""/>
        </ImageArray>
        <DataItemImageNumber name=""hour"" source=""timeHour"" ref=""@digits"" totalDigits=""2"" decimalDigits=""0"" align=""left"" leadingZero=""true"" trailingZero=""false"" renderRule=""alwaysShow"" rotation=""0"" decimalOffsetX=""0"" space=""1""/>
        <DataItemText name=""t"" color=""#FF8800"" opacity=""80"" fontId=""misans"" fontWeight=""bold"" letterSpace=""1"" align=""center"" longMode=""clip"" style=""normal"" lineSpace=""2"" w=""100"" h=""30"" rotation=""0"" string=""Hi %s"">
            <Content source=""timeHour""/>
        </DataItemText>
    </Resources>
    <Theme type=""normal"" name=""main"" bgColor=""#000000"">
        <Layout ref=""@bg"" x=""0"" y=""0""/>
        <Layout ref=""@hour"" x=""10"" y=""20""/>
        <Layout ref=""@t"" x=""0"" y=""50""/>
    </Theme>
</Watchface>";
        var png = Png.Encode(w, h, px);
        var st = new MemoryStorage(new Dictionary<string, byte[]> { ["manifest.xml"] = U(manifest), ["bg.png"] = png, ["d/0.png"] = png, ["d/1.png"] = png });
        var bin = WatchfaceCompiler.Build(st);
        var o = new MemoryStorage();
        WatchfaceCompiler.Unpack(bin, o);
        Assert.True(o.Files.ContainsKey("manifest.xml"));
        Assert.Equal(bin, WatchfaceCompiler.Build(o));
    }

    /// <summary>Справжні циферблати: після першого розпакування й збирання наступні кола дають той самий .bin
    /// (перше коло може змінитися — RGB565A8 у exe не ідемпотентний).</summary>
    [Theory]
    [InlineData("BigWatch_UA.bin")]
    [InlineData("WhatTime_UA.bin")]
    public void RealFacesAreStable(string file)
    {
        var src = File.ReadAllBytes(Path.Combine(System.AppContext.BaseDirectory, "Faces", file));
        var a = new MemoryStorage();
        WatchfaceCompiler.Unpack(src, a);
        var bin1 = WatchfaceCompiler.Build(a);
        Assert.Equal(0x1234A55Au, bin1.U32(0));
        var b = new MemoryStorage();
        WatchfaceCompiler.Unpack(bin1, b);
        var bin2 = WatchfaceCompiler.Build(b);
        var c = new MemoryStorage();
        WatchfaceCompiler.Unpack(bin2, c);
        Assert.Equal(bin2, WatchfaceCompiler.Build(c));
        // маніфест розпакованого оригіналу й зібраного порту однаковий
        Assert.Equal(Encoding.UTF8.GetString(a.Files["manifest.xml"]), Encoding.UTF8.GetString(b.Files["manifest.xml"]));
    }
}
