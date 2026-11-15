package com.bandface.app

import android.util.Base64
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.security.MessageDigest
import java.security.SecureRandom

/** Браслет з акаунта Xiaomi і його ключ */
data class CloudDevice(val name: String, val model: String, val key: String)

/**
 * Ключ браслета з хмари Mi Fitness — той самий шлях, що й у Windows-версії, лише вхід не через QR,
 * а на сайті Xiaomi (LoginActivity). Після входу маємо passToken; з ним — ssecurity і serviceToken,
 * далі підписаний запит списку пристроїв. Нічого не зберігається.
 */
object XiaomiCloud {
    const val SID = "miothealth"
    const val CALLBACK = "https://sts-hlth.io.mi.com/healthapp/sts"
    private const val HEALTH_PATH = "/app/v1/source/get_source_list"
    private val regions = listOf("", "sg", "de", "us", "i2", "ru", "in")
    private val rnd = SecureRandom()

    /** Сторінка входу Xiaomi: після входу браузер переходить на CALLBACK */
    val loginUrl: String get() =
        "https://account.xiaomi.com/pass/serviceLogin?sid=$SID&_locale=" + java.util.Locale.getDefault().toLanguageTag().replace('-', '_') +
            "&callback=" + enc(CALLBACK)

    private class Login(val userId: String, val cUserId: String, val ssecurity: String, val nonce: String, val location: String)

    private fun enc(s: String) = URLEncoder.encode(s, "UTF-8")

    private fun agent(): String {
        fun chars(n: Int, from: Char, to: Char) = (1..n).map { (from + rnd.nextInt(to - from + 1)) }.joinToString("")
        return chars(18, 'a', 'z') + "-" + chars(13, 'A', 'E') + " APP/com.xiaomi.mihome APPV/10.5.201"
    }

    private fun json(text: String) = JSONObject(text.replace("&&&START&&&", ""))

    private fun open(url: String, agent: String, cookie: String? = null): HttpURLConnection =
        (URL(url).openConnection() as HttpURLConnection).apply {
            instanceFollowRedirects = false
            connectTimeout = 20_000; readTimeout = 30_000
            setRequestProperty("User-Agent", agent)
            if (cookie != null) setRequestProperty("Cookie", cookie)
        }

    /** Кукі сайту account.xiaomi.com після входу (userId, passToken) → список браслетів з ключами */
    fun devices(accountCookies: String, log: (String) -> Unit): List<CloudDevice> {
        val agent = agent()
        val login = serviceLogin(accountCookies, agent)
        log("xiaomi: login ok")
        val token = serviceToken(login, agent)
        log("xiaomi: service token ok")
        var variants = listOf("mihome", "stream")
        for (region in regions) {
            val host = if (region.isEmpty()) "hlth.io.mi.com" else "$region.hlth.io.mi.com"
            for (v in variants) {
                val res = runCatching { callHealth(host, v, login, token, agent) }
                    .onFailure { log("$host $v: ${it.message}") }.getOrNull()
                if (res == null || res.optInt("code", -1) != 0) { log("$host $v: no"); continue }
                variants = listOf(v)
                val list = parseList(res)
                log("$host $v: ok, ${list.size}")
                if (list.isNotEmpty()) return list
                break
            }
        }
        return emptyList()
    }

    private fun serviceLogin(cookies: String, agent: String): Login {
        val c = open("https://account.xiaomi.com/pass/serviceLogin?sid=$SID&_json=true", agent, cookies)
        val text = c.inputStream.bufferedReader().readText()
        val d = json(text)
        val ssecurity = d.optString("ssecurity")
        val location = d.optString("location")
        if (ssecurity.isEmpty() || location.isEmpty()) throw IllegalStateException("xiaomi: login code ${d.optInt("code", -1)}")
        return Login(d.optString("userId"), d.optString("cUserId"), ssecurity, d.optString("nonce"), location)
    }

    private fun serviceToken(l: Login, agent: String): String {
        val urls = mutableListOf(l.location)
        if (l.nonce.isNotEmpty() && !Regex("[?&]clientSign=").containsMatchIn(l.location))
            urls += l.location + (if ('?' in l.location) "&" else "?") + "clientSign=" + enc(Crypto.clientSign(l.nonce, l.ssecurity))
        for (first in urls) {
            var url: String? = first
            var hop = 0
            while (url != null && hop++ < 6) {
                val c = open(url, agent)
                val code = c.responseCode
                c.headerFields.entries.filter { it.key.equals("Set-Cookie", true) }.flatMap { it.value }.forEach { ck ->
                    Regex("^serviceToken=([^;]+)").find(ck)?.let { return it.groupValues[1] }
                }
                val next = c.getHeaderField("Location")
                url = if (code / 100 == 3 && next != null) URL(URL(url), next).toString() else null
                c.disconnect()
            }
        }
        throw IllegalStateException("xiaomi: no service token")
    }

    private fun callHealth(host: String, variant: String, l: Login, token: String, agent: String): JSONObject? {
        val nonce = Crypto.makeNonce()
        val data = "{\"page_size\":50,\"status\":1}"
        val mihome = variant == "mihome"
        val ps = if (mihome) Crypto.buildEnc(HEALTH_PATH, data, l.ssecurity, nonce) else Crypto.buildStream(HEALTH_PATH, data, l.ssecurity, nonce)
        val form = ps.joinToString("&") { enc(it.first) + "=" + enc(it.second) }
        val c = open(if (mihome) "https://$host$HEALTH_PATH?$form" else "https://$host$HEALTH_PATH",
            if (mihome) agent else "Android-12-9.8.348i-google-Pixel 4")
        c.requestMethod = "POST"
        c.doOutput = true
        c.setRequestProperty("Content-Type", "application/x-www-form-urlencoded")
        if (mihome) {
            c.setRequestProperty("MIOT-ENCRYPT-ALGORITHM", "ENCRYPT-RC4")
            c.setRequestProperty("Cookie", "userId=${l.userId}; cUserId=${l.cUserId}; yetAnotherServiceToken=$token; serviceToken=$token; locale=en_GB; channel=MI_APP_STORE")
            c.outputStream.use { }
        } else {
            c.setRequestProperty("region_tag", "ru")
            c.setRequestProperty("Cookie", "cUserId=${l.cUserId}; serviceToken=$token; locale=en_us")
            c.outputStream.use { it.write(form.toByteArray()) }
        }
        if (c.responseCode !in 200..299) return null
        val body = c.inputStream.bufferedReader().readText()
        return runCatching { json(Crypto.decrypt(l.ssecurity, nonce, body)) }.getOrNull()
    }

    private fun parseList(res: JSONObject): List<CloudDevice> {
        val out = ArrayList<CloudDevice>()
        val items = res.optJSONObject("result")?.optJSONArray("list") ?: return out
        for (i in 0 until items.length()) {
            val src = items.optJSONObject(i) ?: continue
            val detail = src.optJSONObject("detail")
                ?: src.optString("detail").takeIf { it.isNotEmpty() }?.let { runCatching { JSONObject(it) }.getOrNull() }
                ?: continue
            for (f in listOf("encrypt_key", "encryptKey", "auth_key", "authKey", "token")) {
                val raw = detail.optString(f).trim().lowercase().removePrefix("0x")
                if (Regex("^[0-9a-f]{32}$").matches(raw)) {
                    out += CloudDevice(src.optString("name").trim(), src.optString("model"), raw)
                    break
                }
            }
        }
        return out
    }

    /** Підписи й RC4-шифрування запитів (як CloudCrypto у Windows-версії) */
    private object Crypto {
        private fun b64(b: ByteArray) = Base64.encodeToString(b, Base64.NO_WRAP)
        private fun unb64(s: String) = Base64.decode(s, Base64.DEFAULT)
        private fun sha(alg: String, b: ByteArray) = MessageDigest.getInstance(alg).digest(b)

        /** RC4 з відкиданням перших 1024 байтів потоку ключа */
        fun rc4(key: ByteArray, data: ByteArray): ByteArray {
            val s = IntArray(256) { it }
            var j = 0
            for (k in 0 until 256) {
                j = (j + s[k] + (key[k % key.size].toInt() and 255)) and 255
                val t = s[k]; s[k] = s[j]; s[j] = t
            }
            val out = ByteArray(data.size)
            var i = 0; j = 0
            for (n in -1024 until data.size) {
                i = (i + 1) and 255; j = (j + s[i]) and 255
                val t = s[i]; s[i] = s[j]; s[j] = t
                if (n >= 0) out[n] = (data[n].toInt() xor s[(s[i] + s[j]) and 255]).toByte()
            }
            return out
        }

        fun signedNonce(ssecurity: String, nonce: String) = b64(sha("SHA-256", unb64(ssecurity) + unb64(nonce)))

        fun clientSign(nonce: String, ssecurity: String) = b64(sha("SHA-1", "nonce=$nonce&$ssecurity".toByteArray()))

        private fun encSig(path: String, signed: String, p: List<Pair<String, String>>): String {
            val parts = listOf("POST", path) + p.map { "${it.first}=${it.second}" } + signed
            return b64(sha("SHA-1", parts.joinToString("&").toByteArray()))
        }

        fun buildEnc(path: String, data: String, ssecurity: String, nonce: String): List<Pair<String, String>> {
            val signed = signedNonce(ssecurity, nonce)
            val key = unb64(signed)
            val plain = mutableListOf("data" to data)
            plain += "rc4_hash__" to encSig(path, signed, plain)
            val enc = plain.map { it.first to b64(rc4(key, it.second.toByteArray())) }.toMutableList()
            enc += "signature" to encSig(path, signed, enc)
            enc += "ssecurity" to ssecurity
            enc += "_nonce" to nonce
            return enc
        }

        fun buildStream(path: String, data: String, ssecurity: String, nonce: String): List<Pair<String, String>> {
            val signed = signedNonce(ssecurity, nonce)
            val hash = encSig(path, signed, listOf("data" to data))
            val all = sortedMapOf("data" to data, "rc4_hash__" to hash)
            val stream = rc4(unb64(signed), all.values.joinToString("").toByteArray())
            val out = mutableListOf<Pair<String, String>>()
            var at = 0
            for ((k, v) in all) {
                val len = v.toByteArray().size
                out += k to b64(stream.copyOfRange(at, at + len))
                at += len
            }
            out += "signature" to encSig(path, signed, out)
            out += "_nonce" to nonce
            return out
        }

        fun decrypt(ssecurity: String, nonce: String, body: String): String =
            String(rc4(unb64(signedNonce(ssecurity, nonce)), unb64(body.trim().trim('"'))), Charsets.UTF_8)

        /** 12 байтів: 8 випадкових + хвилини від епохи (big-endian) */
        fun makeNonce(): String {
            val n = ByteArray(12)
            rnd.nextBytes(n)
            val min = System.currentTimeMillis() / 60_000
            n[8] = (min shr 24).toByte(); n[9] = (min shr 16).toByte(); n[10] = (min shr 8).toByte(); n[11] = min.toByte()
            return b64(n)
        }
    }
}
