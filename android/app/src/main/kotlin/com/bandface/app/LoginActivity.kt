package com.bandface.app

import android.annotation.SuppressLint
import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.webkit.CookieManager
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.LinearLayout
import android.widget.TextView
import androidx.activity.ComponentActivity
import androidx.activity.enableEdgeToEdge
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat

/**
 * Вхід в акаунт Xiaomi на сайті Xiaomi (логін, пароль, код із SMS — усе вводиться на їхній сторінці).
 * Коли сайт переходить на адресу Mi Fitness (вхід завершено), повертаємо кукі account.xiaomi.com.
 */
class LoginActivity : ComponentActivity() {
    companion object { const val COOKIES = "cookies" }

    private var finished = false

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        val cookies = CookieManager.getInstance()
        // щоразу новий вхід: без чужої чи старої сесії
        cookies.removeAllCookies(null)
        cookies.setAcceptCookie(true)

        val pad = (16 * resources.displayMetrics.density).toInt()
        val title = TextView(this).apply {
            setText(R.string.xiaomi_login_title); textSize = 18f
            setPadding(pad, pad, pad, pad)
            setCompoundDrawablesRelativeWithIntrinsicBounds(android.R.drawable.ic_menu_close_clear_cancel, 0, 0, 0)
            compoundDrawablePadding = pad
            setOnClickListener { setResult(Activity.RESULT_CANCELED); finish() }
        }
        val web = WebView(this).apply {
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            cookies.setAcceptThirdPartyCookies(this, true)
            webViewClient = object : WebViewClient() {
                override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean = check(request.url.toString())
                override fun onPageStarted(view: WebView, url: String, favicon: android.graphics.Bitmap?) { check(url) }
            }
            loadUrl(XiaomiCloud.loginUrl)
        }
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            addView(title)
            addView(web, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f))
        }
        ViewCompat.setOnApplyWindowInsetsListener(root) { v, insets ->
            val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.ime())
            v.setPadding(bars.left, bars.top, bars.right, bars.bottom)
            insets
        }
        setContentView(root)
    }

    /** Вхід завершено, коли сайт іде на адресу Mi Fitness або вже видав passToken */
    private fun check(url: String): Boolean {
        if (finished) return true
        val account = CookieManager.getInstance().getCookie("https://account.xiaomi.com") ?: ""
        // є passToken і сайт уже пішов з account.xiaomi.com (на адресу Mi Fitness чи будь-яку іншу) — вхід завершено
        val done = url.startsWith(XiaomiCloud.CALLBACK) ||
            (account.contains("passToken=") && !android.net.Uri.parse(url).host.orEmpty().endsWith("account.xiaomi.com"))
        if (!done) return false
        finished = true
        setResult(Activity.RESULT_OK, Intent().putExtra(COOKIES, account))
        finish()
        return true
    }
}
