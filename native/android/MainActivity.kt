package io.github.noregretl.clashbrowser

import android.app.Dialog
import android.net.Uri
import android.os.Bundle
import android.view.ViewGroup
import android.webkit.*
import android.widget.*
import androidx.webkit.ProxyConfig
import androidx.webkit.ProxyController
import androidx.webkit.WebViewFeature
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executor

class MainActivity : FlutterActivity() {
    private var browser: Dialog? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "clashbrowser/browser/v1")
            .setMethodCallHandler { call, result ->
                if (call.method != "open") { result.notImplemented(); return@setMethodCallHandler }
                val port = call.argument<Int>("port")
                val user = call.argument<String>("username")
                val pass = call.argument<String>("password")
                if (browser != null || port == null || port !in 1..65535 ||
                    user != "browser" || pass.isNullOrEmpty() ||
                    !WebViewFeature.isFeatureSupported(WebViewFeature.PROXY_OVERRIDE)) {
                    result.error("UNAVAILABLE", "Proxy not available", null)
                    return@setMethodCallHandler
                }
                openBrowser(port, user, pass, result)
            }
    }
    private fun safeUrl(raw: String): Boolean {
        val uri = Uri.parse(raw)
        val host = uri.host ?: return false
        return uri.scheme == "https" && uri.userInfo == null &&
            host.contains('.') && host.any { it.isLetter() } &&
            !host.endsWith(".localhost", true) && !host.equals("localhost", true)
    }
    private fun openBrowser(port: Int, user: String, pass: String, result: MethodChannel.Result) {
        val dialog = Dialog(this, android.R.style.Theme_Material_Light_NoActionBar)
        browser = dialog
        val column = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        val row = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        val address = EditText(this).apply { singleLine(); hint = "https://example.com" }
        val go = Button(this).apply { text = "打开"; isEnabled = false }
        val close = Button(this).apply { text = "关闭" }
        val status = TextView(this).apply { text = "正在配置应用内代理…"; }
        val web = WebView(this)
        var ready = false
        var closed = false
        var authAttempted = false
        web.settings.apply {
            javaScriptEnabled = false
            allowFileAccess = false
            allowContentAccess = false
            mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
            setSupportMultipleWindows(false)
            domStorageEnabled = false
            blockNetworkLoads = true
        }
        web.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean =
                !ready || !safeUrl(request.url.toString())
            override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? {
                if (safeUrl(request.url.toString())) return null
                return WebResourceResponse("text/plain", "UTF-8", java.io.ByteArrayInputStream(ByteArray(0)))
            }
            override fun onReceivedHttpAuthRequest(view: WebView, handler: HttpAuthHandler, host: String, realm: String) {
                // Android does not expose an isProxy flag. Never send proxy credentials
                // to a remote origin or to a nonempty realm.
                if (!ready || authAttempted || (host != "127.0.0.1" && host != "127.0.0.1:$port") || realm.isNotEmpty()) {
                    handler.cancel(); status.text = "认证失败或不兼容"; return
                }
                authAttempted = true
                handler.proceed(user, pass)
            }
            override fun onReceivedSslError(view: WebView, handler: SslErrorHandler, error: android.net.http.SslError) {
                handler.cancel(); status.text = "TLS 验证失败"
            }
            override fun onReceivedError(view: WebView, request: WebResourceRequest, error: WebResourceError) {
                if (request.isForMainFrame) status.text = "网页加载失败（无直连回退）"
            }
            override fun onPageFinished(view: WebView, url: String) {
                if (safeUrl(url)) address.setText(url)
            }
        }
        web.webChromeClient = object : WebChromeClient() {
            override fun onPermissionRequest(request: PermissionRequest) { request.deny() }
            override fun onGeolocationPermissionsShowPrompt(origin: String, callback: GeolocationPermissions.Callback) {
                callback.invoke(origin, false, false)
            }
        }
        row.addView(address, LinearLayout.LayoutParams(0, -2, 1f))
        row.addView(go); row.addView(close)
        column.addView(row); column.addView(status)
        column.addView(web, LinearLayout.LayoutParams(-1, 0, 1f))
        dialog.setContentView(column)
        close.setOnClickListener { dialog.dismiss() }
        go.setOnClickListener {
            val url = address.text.toString().trim().let { if (it.contains("://")) it else "https://$it" }
            if (ready && safeUrl(url)) { authAttempted = false; status.text = "实验浏览模式"; web.loadUrl(url) }
            else status.text = "仅支持 HTTPS 域名"
        }
        dialog.setOnDismissListener {
            closed = true; ready = false
            web.settings.blockNetworkLoads = true
            web.stopLoading(); column.removeView(web); web.destroy()
            browser = null
            // Leave the override in place: clearing it while the engine is
            // still draining could permit a direct connection.
            result.success(true)
        }
        dialog.show()
        dialog.window?.setLayout(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
        try {
            val config = ProxyConfig.Builder().addProxyRule("http://127.0.0.1:$port").removeImplicitRules().build()
            ProxyController.getInstance().setProxyOverride(config, Executor { runOnUiThread(it) }) {
                if (!closed) { ready = true; web.settings.blockNetworkLoads = false; go.isEnabled = true; status.text = "代理配置已应用 · 实验模式" }
            }
        } catch (_: Exception) {
            status.text = "代理配置失败，网页保持禁用"
        }
    }
}
