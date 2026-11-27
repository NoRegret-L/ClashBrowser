package io.github.noregretl.clashbrowser

import android.content.Context
import android.net.Uri
import android.webkit.*
import android.widget.FrameLayout
import androidx.webkit.ProxyConfig
import androidx.webkit.ProxyController
import androidx.webkit.WebViewFeature
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import org.json.JSONObject
import java.util.concurrent.Executor

private const val TYPE = "clashbrowser/webview/v2"

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        WebView.setWebContentsDebuggingEnabled(false)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "clashbrowser/storage/v1")
            .setMethodCallHandler { call, result ->
                if (call.method == "directory") result.success(filesDir.absolutePath)
                else result.notImplemented()
            }
        flutterEngine.platformViewsController.registry.registerViewFactory(
            TYPE, BrowserFactory(flutterEngine.dartExecutor.binaryMessenger))
    }
}

private class BrowserFactory(private val messenger: BinaryMessenger) :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView =
        BrowserView(context, messenger, viewId, args as? String ?: "")
}

private class BrowserView(context: Context, messenger: BinaryMessenger, id: Int, input: String) :
    PlatformView {
    private val frame = FrameLayout(context)
    private val web = WebView(context)
    private val channel = MethodChannel(messenger, "$TYPE/$id")
    @Volatile private var state = "pending"
    @Volatile private var closed = false
    private var authAttempted = false
    private var destroyed = false
    private var mainFrameFailed = false
    private fun navigationError() {
        mainFrameFailed = true
        emit("loadError")
    }

    private fun safe(raw: String): Boolean {
        val uri = Uri.parse(raw)
        val host = uri.host ?: return false
        return uri.scheme == "https" && uri.userInfo == null &&
            Regex("^[a-zA-Z0-9-]+(\\.[a-zA-Z0-9-]+)+$").matches(host) &&
            host.any { it.isLetter() } && !host.endsWith(".localhost", true)
    }
    private fun emit(value: String) {
        if (value == "ready" || value == "pending" || value == "failed") state = value
        if (!closed) channel.invokeMethod("state", value)
    }
    init {
        frame.addView(web, FrameLayout.LayoutParams(-1, -1))
        web.settings.apply {
            javaScriptEnabled = false
            allowFileAccess = false
            allowContentAccess = false
            mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
            setSupportMultipleWindows(false)
            domStorageEnabled = false
            javaScriptCanOpenWindowsAutomatically = false
            setGeolocationEnabled(false)
            blockNetworkLoads = true
        }
        channel.setMethodCallHandler { call, result ->
            if (call.method == "status") { result.success(state); return@setMethodCallHandler }
            if (call.method == "close") { close(); result.success(true); return@setMethodCallHandler }
            if (closed || state != "ready") { result.success(false); return@setMethodCallHandler }
            val ok = when (call.method) {
                "load" -> {
                    val url = call.arguments as? String
                    if (url != null && safe(url)) { authAttempted = false; mainFrameFailed = false; web.loadUrl(url); true } else false
                }
                "back" -> if (web.canGoBack()) { mainFrameFailed = false; web.goBack(); true } else false
                "forward" -> if (web.canGoForward()) { mainFrameFailed = false; web.goForward(); true } else false
                "reload" -> if (web.url?.let(::safe) == true) { authAttempted = false; mainFrameFailed = false; web.reload(); true } else false
                "stop" -> { web.stopLoading(); true }
                else -> { result.notImplemented(); return@setMethodCallHandler }
            }
            result.success(ok)
        }
        try {
            val args = JSONObject(input)
            val port = args.getInt("port")
            val user = args.getString("username")
            val pass = args.getString("password")
            require(port in 1..65535 && user == "browser" && pass.matches(Regex("[a-f0-9]{64}")))
            require(WebViewFeature.isFeatureSupported(WebViewFeature.PROXY_OVERRIDE))
            web.webViewClient = object : WebViewClient() {
                override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean =
                    closed || state != "ready" || !safe(request.url.toString())
                override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? {
                    if (!closed && state == "ready" && safe(request.url.toString())) return null
                    return WebResourceResponse("text/plain", "UTF-8", java.io.ByteArrayInputStream(ByteArray(0)))
                }
                override fun onReceivedHttpAuthRequest(view: WebView, handler: HttpAuthHandler, host: String, realm: String) {
                    if (closed || state != "ready" || authAttempted ||
                        (host != "127.0.0.1" && host != "127.0.0.1:$port") || realm.isNotEmpty()) {
                        handler.cancel(); mainFrameFailed = true; emit("authError"); return
                    }
                    authAttempted = true
                    handler.proceed(user, pass)
                }
                override fun onReceivedSslError(view: WebView, handler: SslErrorHandler, error: android.net.http.SslError) {
                    handler.cancel(); navigationError()
                }
                override fun onReceivedError(view: WebView, request: WebResourceRequest, error: WebResourceError) {
                    if (request.isForMainFrame) navigationError()
                }
                override fun onReceivedHttpError(view: WebView, request: WebResourceRequest, errorResponse: WebResourceResponse) {
                    if (request.isForMainFrame) navigationError()
                }
                override fun onPageStarted(view: WebView, url: String, favicon: android.graphics.Bitmap?) {
                    if (!closed && safe(url)) {
                        mainFrameFailed = false
                        channel.invokeMethod("state", "loading")
                    }
                }
                override fun onPageFinished(view: WebView, url: String) {
                    if (!closed && !mainFrameFailed && safe(url) && view.url == url)
                        channel.invokeMethod("url", url)
                }
            }
            web.webChromeClient = object : WebChromeClient() {
                override fun onPermissionRequest(request: PermissionRequest) { request.deny() }
                override fun onGeolocationPermissionsShowPrompt(origin: String, callback: GeolocationPermissions.Callback) {
                    callback.invoke(origin, false, false)
                }
            }
            val config = ProxyConfig.Builder().addProxyRule("http://127.0.0.1:$port").removeImplicitRules().build()
            ProxyController.getInstance().setProxyOverride(config, Executor { frame.post(it) }) {
                if (!closed) { web.settings.blockNetworkLoads = false; emit("ready") }
            }
        } catch (_: Exception) { emit("failed") }
    }
    private fun close() {
        if (closed) return
        closed = true; state = "failed"
        web.settings.blockNetworkLoads = true
        web.stopLoading()
        frame.removeView(web)
        if (!destroyed) { destroyed = true; web.destroy() }
        // Never clear the override while the renderer may be draining.
    }
    override fun getView() = frame
    override fun dispose() { close(); channel.setMethodCallHandler(null) }
}
