package eu.kanade.tachiyomi.network

import android.annotation.SuppressLint
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.webkit.WebView
import kotlinx.coroutines.suspendCancellableCoroutine
import org.json.JSONArray
import kotlin.coroutines.resume

/**
 * Util for evaluating JavaScript in sources.
 *
 * Mihon runs this on QuickJS. PlayzAnime evaluates in a throwaway WebView instead,
 * which avoids shipping a second JS engine for the handful of sources that need one.
 */
@Suppress("UNUSED", "UNCHECKED_CAST")
class JavaScriptEngine(private val context: Context) {

    @SuppressLint("SetJavaScriptEnabled")
    suspend fun <T> evaluate(script: String): T = suspendCancellableCoroutine { cont ->
        Handler(Looper.getMainLooper()).post {
            val web = WebView(context)
            web.settings.javaScriptEnabled = true
            web.evaluateJavascript("(function(){return ($script);})()") { raw ->
                web.destroy()
                // evaluateJavascript hands back JSON; unwrap it to a Kotlin primitive.
                val value: Any? = runCatching { JSONArray("[$raw]").get(0) }.getOrNull()
                val out: Any? = when (value) {
                    org.json.JSONObject.NULL -> null
                    else -> value
                }
                if (cont.isActive) cont.resume(out as T)
            }
        }
    }
}
