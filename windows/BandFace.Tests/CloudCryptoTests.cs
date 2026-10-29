using System.Linq;
using System.Text;
using BandFace.Protocol;
using Xunit;

public class CloudCryptoTests
{
    const string Ss = "AAECAwQFBgcICQoLDA0ODw==", Nonce = "AAECAwQFBgcICQoL";
    const string Path = "/app/v1/source/get_source_list";
    const string Data = "{\"page_size\":50,\"status\":1}";

    [Fact]
    public void Rc4Vector() =>
        Assert.Equal("muRmNo5+qPL1", System.Convert.ToBase64String(CloudCrypto.Rc4(Encoding.ASCII.GetBytes("Key"), Encoding.ASCII.GetBytes("Plaintext"))));

    [Fact]
    public void SignedNonceAndClientSign()
    {
        Assert.Equal("Nz6YMO70n75ITJeXTWpiyXXLp6IBZ0yT0/hEJB0FDOg=", CloudCrypto.SignedNonce(Ss, Nonce));
        Assert.Equal("3SaSBn5CnWdnPpC76P+D4+JtZpk=", CloudCrypto.ClientSign("abc", Ss));
    }

    [Fact]
    public void EncVariant()
    {
        var p = CloudCrypto.BuildEnc(Path, Data, Ss, Nonce).Select(x => x.Key + "=" + x.Value).ToArray();
        Assert.Equal(new[] {
            "data=Gjcp2s7UcCuQW/Gd6CvTStUrJeUjmCnJKNhK",
            "rc4_hash__=OXsuz4b2bhnSaKTwunKGIaIcHNcBtTiyQMJ2QA==",
            "signature=Dfg3Kv/TV0zuvqY/fOWiWZntKcA=",
            "ssecurity=" + Ss, "_nonce=" + Nonce }, p);
    }

    [Fact]
    public void StreamVariant()
    {
        var p = CloudCrypto.BuildStream(Path, Data, Ss, Nonce).Select(x => x.Key + "=" + x.Value).ToArray();
        Assert.Equal(new[] {
            "data=Gjcp2s7UcCuQW/Gd6CvTStUrJeUjmCnJKNhK",
            "rc4_hash__=JTr3ZUdVX62gxf3w3m8/ZuS/Pwb/iaa78XHCXw==",
            "signature=GXzAF9TA+nsvSWk712SUb4olFJ4=",
            "_nonce=" + Nonce }, p);
    }
}
