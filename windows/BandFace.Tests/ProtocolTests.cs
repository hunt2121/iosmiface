using System.Linq;
using System.Text;
using BandFace.Protocol;
using Xunit;

// Вектори взято з Swift-тестів BandFaceKit (згенеровано незалежною реалізацією на Python).
public class ProtocolTests
{
    static byte[] H(string s) => Bytes.ParseHex(s);
    static byte[] Range(int from, int count) => Enumerable.Range(from, count).Select(x => (byte)x).ToArray();

    [Fact] public void Crc16() => Assert.Equal(0xBB3D, Checksum.Crc16(Encoding.ASCII.GetBytes("123456789")));
    [Fact] public void Crc32() => Assert.Equal(0xCBF43926L, Checksum.Crc32(Encoding.ASCII.GetBytes("123456789")));

    [Fact]
    public void SessionOpenFrame()
    {
        var open = SessionControl.DefaultOpen();
        Assert.Equal(22, open.Payload.Length);
        Assert.Equal(H("a5a5020016001d4d0101030001000002020000fc03020020000402001027"), new Frame(FrameType.Session, 0, open.Payload).Encoded());
        Assert.Equal(H("a5a502000100400103"), new Frame(FrameType.Session, 0, SessionControl.Close().Payload).Encoded());
        Assert.Equal(H("a5a5010700000000"), Frame.Ack(7).Encoded());
    }

    [Fact]
    public void ParserSplitsAndMerges()
    {
        var f1 = new Frame(FrameType.Data, 1, new byte[] { 1, 2, 3 }).Encoded();
        var f2 = Frame.Ack(2).Encoded();
        var all = Bytes.Concat(new byte[] { 0x00, 0x13 }, f1, f2);
        var p = new FrameParser();
        var got = p.Append(all.Slice(0, 7)).Concat(p.Append(all.Slice(7, all.Length))).ToList();
        Assert.Equal(2, got.Count);
        Assert.Equal(FrameType.Data, got[0].Type);
        Assert.Equal(new byte[] { 1, 2, 3 }, got[0].Payload);
        Assert.Equal(FrameType.Ack, got[1].Type);
    }

    [Fact]
    public void CommandEncodings()
    {
        Assert.Equal(H("0801101a1a15f201120a10101112131415161718191a1b1c1d1e1f"), Command.AuthPhoneNonce(Range(0x10, 16)));
        Assert.Equal(H("08021002"), Command.DeviceInfoRequest());
        Assert.Equal(H("080410043211320f0a093236363233353336391080a806"), Command.InstallRequest("266235369", 103424));
        Assert.Equal(H("08161000c201180a16081012105d41402abc4b2a76b9719d911017c5921805"),
            Command.UploadRequest(BandCrypto.Md5(Encoding.ASCII.GetBytes("hello")), 5));
        Assert.Equal(H("080015000008421a066950686f6e6520e0012a02554b"), Command.PhoneInfo("iPhone", "UK"));
    }

    [Fact]
    public void KeysAndCrypto()
    {
        var keys = new SessionKeys(Range(0, 16), Range(0x10, 16), Range(0x20, 16));
        Assert.Equal(H("d738074e6570abb50d001db70f497a37"), keys.DecryptionKey);
        Assert.Equal(H("923e295e02aecb7619a8e1b9f574c988"), keys.EncryptionKey);
        Assert.Equal(H("23869a15"), keys.EncryptionNonce);
        Assert.Equal(H("17aa8eecac21d9d71cba6ea653d126d77abc2f4d0357f1cce01d433d40e42235"), keys.ExpectedBandHmac(Range(0x10, 16), Range(0x20, 16)));
        Assert.Equal(H("7e6e4d786282c1af4441b2ed315da93c8ae2c820a72df584d62315d73913a9dc"), keys.PhoneConfirmation(Range(0x10, 16), Range(0x20, 16)));
        Assert.Equal(H("806dad1c238704c043431e48e043c1b650bf3ae4bdfb7cb2cfc2"), keys.EncryptPhoneInfo(Command.PhoneInfo("iPhone", "UK")));
        Assert.Equal(H("b7e6503e"), keys.EncryptCommand(H("08021002")));
        Assert.Equal(Range(0, 40), keys.DecryptCommand(H("050b16c236898af83e1fc7de57b5f584774d53576f9aac8ad27f4f799215ef5b170fb6f62adc0a25")));
    }

    [Fact]
    public void FileStreamAndParts()
    {
        var file = Enumerable.Range(0, 10000).Select(i => (byte)(i * 7)).ToArray();
        var md5 = BandCrypto.Md5(file);
        Assert.Equal(H("06a474d076d55fe5bdaafbb83017ffca"), md5);
        var stream = FileTransfer.Stream(file, md5);
        Assert.Equal(10026, stream.Length);
        Assert.Equal(H("608c8607"), stream.Slice(stream.Length - 4, stream.Length));
        var parts = FileTransfer.Parts(stream, 4096);
        Assert.Equal(3, parts.Count);
        Assert.Equal(H("03000100001006a474d076d5"), parts[0].Slice(0, 12));
        Assert.Equal(1846, parts[2].Length);
        Assert.Equal(5026, FileTransfer.Stream(file, md5, 5000).Length);
        Assert.Equal(H("99445ab8"), FileTransfer.Stream(file, md5, 5000).Slice(5022, 5026));
    }

    [Fact]
    public void FaceHeader()
    {
        var b = new byte[0x100];
        b[0] = 0x5A; b[1] = 0xA5;
        var id = Encoding.ASCII.GetBytes("266235369");
        for (int i = 0; i < id.Length; i++) b[0x28 + i] = id[i];
        var nm = Encoding.UTF8.GetBytes("Test");
        for (int i = 0; i < nm.Length; i++) b[0x68 + i] = nm[i];
        var f = new FaceFile(b);
        Assert.Equal("266235369", f.Id);
        Assert.Equal("Test", f.Name);
        Assert.Throws<BandException>(() => new FaceFile(new byte[10]));
    }
}
