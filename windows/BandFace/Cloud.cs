using System;
using System.Collections.Generic;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using BandFace.Protocol;

namespace BandFace
{
    sealed class CloudDevice
    {
        public string Name, Model, Key;
        public override string ToString() => (string.IsNullOrEmpty(Name) ? Model : Name);
    }

    sealed class QrStart
    {
        public byte[] Image; public string LongPoll; public int Timeout;
    }

    sealed class QrLogin
    {
        public string UserId, CUserId, SSecurity, Location, Nonce;
    }

    /// <summary>
    /// Вхід в акаунт Xiaomi через QR і запит ключа браслета з хмари Mi Fitness.
    /// Сесія живе лише в пам'яті й нікуди не зберігається.
    /// </summary>
    static class XiaomiCloud
    {
        const string Sid = "miothealth";
        const string Callback = "https://sts-hlth.io.mi.com/healthapp/sts";
        const string HealthPath = "/app/v1/source/get_source_list";
        static readonly string[] Regions = { "", "sg", "de", "us", "i2", "ru", "in" };
        static readonly Random Rnd = new Random();

        static HttpClient NewClient()
        {
            ServicePointManager.SecurityProtocol |= (SecurityProtocolType)3072; // TLS 1.2
            var c = new HttpClient(new HttpClientHandler { AllowAutoRedirect = false, UseCookies = false }) { Timeout = TimeSpan.FromSeconds(70) };
            return c;
        }

        static Dictionary<string, object> Parse(string text) =>
            (Dictionary<string, object>)MiniJson.Parse(text.Replace("&&&START&&&", ""));

        static string Str(Dictionary<string, object> d, string k) => d.ContainsKey(k) && d[k] != null ? Convert.ToString(d[k]) : "";

        static string Chars(int n, int from, int to)
        {
            var sb = new StringBuilder();
            for (int i = 0; i < n; i++) sb.Append((char)Rnd.Next(from, to + 1));
            return sb.ToString();
        }

        static string Agent() => Chars(18, 97, 122) + "-" + Chars(13, 65, 69) + " APP/com.xiaomi.mihome APPV/10.5.201";

        public static async Task<QrStart> StartAsync()
        {
            using (var c = NewClient())
            {
                var q = "_qrsize=480&qs=" + Uri.EscapeDataString("?sid=" + Sid + "&_json=true") + "&callback=" + Uri.EscapeDataString(Callback)
                    + "&_hasLogo=false&sid=" + Sid + "&serviceParam=&_locale=en_GB&_dc=" + DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
                var text = await c.GetStringAsync("https://account.xiaomi.com/longPolling/loginUrl?" + q).ConfigureAwait(false);
                var d = Parse(text);
                var qr = Str(d, "qr"); var lp = Str(d, "lp");
                if (qr == "" || lp == "") throw new Exception("Xiaomi: no QR");
                var img = await c.GetByteArrayAsync(qr).ConfigureAwait(false);
                int t; if (!int.TryParse(Str(d, "timeout"), out t) || t <= 0) t = 300;
                return new QrStart { Image = img, LongPoll = lp, Timeout = t };
            }
        }

        /// <summary>Чекає, поки QR відскануюють і підтвердять.</summary>
        public static async Task<QrLogin> WaitAsync(QrStart qr, CancellationToken ct)
        {
            var host = new Uri(qr.LongPoll).Host;
            if (host != "account.xiaomi.com" && !host.EndsWith(".account.xiaomi.com")) throw new Exception("unexpected host");
            var deadline = DateTime.UtcNow.AddSeconds(qr.Timeout);
            using (var c = NewClient())
            {
                while (DateTime.UtcNow < deadline)
                {
                    ct.ThrowIfCancellationRequested();
                    try
                    {
                        var r = await c.GetAsync(qr.LongPoll, ct).ConfigureAwait(false);
                        if (r.StatusCode == HttpStatusCode.OK)
                        {
                            var d = Parse(await r.Content.ReadAsStringAsync().ConfigureAwait(false));
                            if (Str(d, "ssecurity") != "" && Str(d, "location") != "")
                                return new QrLogin { UserId = Str(d, "userId"), CUserId = Str(d, "cUserId"), SSecurity = Str(d, "ssecurity"), Location = Str(d, "location"), Nonce = Str(d, "nonce") };
                        }
                    }
                    catch (TaskCanceledException) { ct.ThrowIfCancellationRequested(); }
                    catch (HttpRequestException) { await Task.Delay(1500, ct).ConfigureAwait(false); }
                }
            }
            throw new TimeoutException();
        }

        static async Task<string> ServiceToken(HttpClient c, string location, string ssecurity, string nonce)
        {
            var urls = new List<string> { location };
            if (!string.IsNullOrEmpty(nonce) && !Regex.IsMatch(location, "[?&]clientSign="))
                urls.Add(location + (location.Contains("?") ? "&" : "?") + "clientSign=" + Uri.EscapeDataString(CloudCrypto.ClientSign(nonce, ssecurity)));
            foreach (var first in urls)
            {
                var url = first;
                for (int hop = 0; hop < 6 && url != null; hop++)
                {
                    var req = new HttpRequestMessage(HttpMethod.Get, url);
                    req.Headers.TryAddWithoutValidation("User-Agent", Agent());
                    var r = await c.SendAsync(req).ConfigureAwait(false);
                    IEnumerable<string> cookies;
                    if (r.Headers.TryGetValues("Set-Cookie", out cookies))
                        foreach (var ck in cookies)
                        {
                            var m = Regex.Match(ck, "^serviceToken=([^;]+)");
                            if (m.Success) return m.Groups[1].Value;
                        }
                    url = (int)r.StatusCode / 100 == 3 && r.Headers.Location != null ? new Uri(new Uri(url), r.Headers.Location).ToString() : null;
                }
            }
            throw new Exception("no service token");
        }

        static async Task<Dictionary<string, object>> CallHealth(HttpClient c, string host, string variant, QrLogin l, string token, string agent)
        {
            var nonce = CloudCrypto.MakeNonce();
            const string data = "{\"page_size\":50,\"status\":1}";
            bool mihome = variant == "mihome";
            var ps = mihome ? CloudCrypto.BuildEnc(HealthPath, data, l.SSecurity, nonce) : CloudCrypto.BuildStream(HealthPath, data, l.SSecurity, nonce);
            var form = string.Join("&", ps.Select(p => Uri.EscapeDataString(p.Key) + "=" + Uri.EscapeDataString(p.Value)));
            var req = new HttpRequestMessage(HttpMethod.Post, mihome ? "https://" + host + HealthPath + "?" + form : "https://" + host + HealthPath);
            req.Headers.TryAddWithoutValidation("User-Agent", mihome ? agent : "Android-12-9.8.348i-google-Pixel 4");
            if (mihome)
            {
                req.Headers.TryAddWithoutValidation("MIOT-ENCRYPT-ALGORITHM", "ENCRYPT-RC4");
                req.Headers.TryAddWithoutValidation("Cookie", "userId=" + l.UserId + "; cUserId=" + l.CUserId + "; yetAnotherServiceToken=" + token + "; serviceToken=" + token + "; locale=en_GB; channel=MI_APP_STORE");
                req.Content = new StringContent("", Encoding.UTF8, "application/x-www-form-urlencoded");
            }
            else
            {
                req.Headers.TryAddWithoutValidation("region_tag", "ru");
                req.Headers.TryAddWithoutValidation("Cookie", "cUserId=" + l.CUserId + "; serviceToken=" + token + "; locale=en_us");
                req.Content = new StringContent(form, Encoding.UTF8, "application/x-www-form-urlencoded");
            }
            var r = await c.SendAsync(req).ConfigureAwait(false);
            if (!r.IsSuccessStatusCode) return null;
            try { return Parse(CloudCrypto.Decrypt(l.SSecurity, nonce, await r.Content.ReadAsStringAsync().ConfigureAwait(false))); }
            catch (Exception) { return null; }
        }

        public static async Task<List<CloudDevice>> DevicesAsync(QrLogin l, Action<string> log)
        {
            using (var c = NewClient())
            {
                var token = await ServiceToken(c, l.Location, l.SSecurity, l.Nonce).ConfigureAwait(false);
                log("service token ok");
                var agent = Agent();
                var variants = new List<string> { "mihome", "stream" };
                foreach (var region in Regions)
                {
                    var host = region == "" ? "hlth.io.mi.com" : region + ".hlth.io.mi.com";
                    foreach (var v in variants.ToArray())
                    {
                        Dictionary<string, object> res = null;
                        try { res = await CallHealth(c, host, v, l, token, agent).ConfigureAwait(false); }
                        catch (Exception ex) { log(host + " " + v + ": " + ex.Message); }
                        object code;
                        if (res == null || !res.TryGetValue("code", out code) || Convert.ToInt32(code) != 0) { log(host + " " + v + ": no"); continue; }
                        variants = new List<string> { v };
                        var list = ParseList(res);
                        log(host + " " + v + ": ok, " + list.Count);
                        if (list.Count > 0) return list;
                        break;
                    }
                }
            }
            return new List<CloudDevice>();
        }

        static List<CloudDevice> ParseList(Dictionary<string, object> res)
        {
            var outp = new List<CloudDevice>();
            var result = res.ContainsKey("result") ? res["result"] as Dictionary<string, object> : null;
            var items = result != null && result.ContainsKey("list") ? result["list"] as System.Collections.IEnumerable : null;
            if (items == null) return outp;
            foreach (var o in items)
            {
                var src = o as Dictionary<string, object>;
                if (src == null) continue;
                Dictionary<string, object> detail = null;
                if (src.ContainsKey("detail"))
                {
                    detail = src["detail"] as Dictionary<string, object>;
                    var s = src["detail"] as string;
                    if (detail == null && s != null) { try { detail = Parse(s); } catch (Exception) { } }
                }
                if (detail == null) continue;
                foreach (var f in new[] { "encrypt_key", "encryptKey", "auth_key", "authKey", "token" })
                {
                    var raw = Str(detail, f).Trim().ToLowerInvariant();
                    if (raw.StartsWith("0x")) raw = raw.Substring(2);
                    if (Regex.IsMatch(raw, "^[0-9a-f]{32}$"))
                    {
                        outp.Add(new CloudDevice { Name = Str(src, "name").Trim(), Model = Str(src, "model"), Key = raw });
                        break;
                    }
                }
            }
            return outp;
        }
    }
}
