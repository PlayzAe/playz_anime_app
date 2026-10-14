package tv.playzae.playzanime

import android.Manifest
import android.app.PictureInPictureParams
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.Settings
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class MainActivity : FlutterActivity() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var system: MethodChannel? = null

    /** Auto-enter picture-in-picture when the user leaves mid-episode. */
    private var pipArmed = false
    private var pipRatio = Rational(16, 9)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ExtHost.init(application)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(messenger, "playz/ext").setMethodCallHandler(::onExt)
        system = MethodChannel(messenger, "playz/system").also { it.setMethodCallHandler(::onSystem) }
        Notify.onAction = { action -> runOnUiThread { system?.invokeMethod("media", action) } }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Notify.channels(this)
    }

    // ── Extensions ──────────────────────────────────────────────────────────

    private fun onExt(call: MethodCall, result: MethodChannel.Result) {
        scope.launch {
            try {
                val out: Any? = withContext(Dispatchers.IO) {
                    val id = call.argument<Any>("id")
                    val page = call.argument<Int>("page") ?: 1
                    when (call.method) {
                        "installed" -> ExtHost.installed()
                        "install" -> ExtHost.install(call.argument("url")!!, call.argument("pkg")!!)
                        "uninstall" -> ExtHost.uninstall(call.argument("pkg")!!)
                        "popular" -> ExtHost.popular(id, page)
                        "latest" -> ExtHost.latest(id, page)
                        "search" -> ExtHost.search(id, call.argument("query") ?: "", page)
                        "details" -> ExtHost.details(id, call.argument("url")!!, call.argument("title"))
                        "update" -> ExtHost.update(id, call.argument("url")!!, call.argument("title"), details = true, chapters = true)
                        "chapters" -> ExtHost.chapters(id, call.argument("url")!!, call.argument("title"))
                        "pages" -> ExtHost.pages(id, call.argument("url")!!, call.argument("name"))
                        "image" -> ExtHost.image(id, call.argument("index") ?: 0, call.argument("url"), call.argument("imageUrl"))
                        "fetch" -> ExtHost.fetch(id, call.argument("url")!!)
                        "headers" -> ExtHost.headers(id)
                        else -> throw NotImplementedError(call.method)
                    }
                }
                result.success(out)
            } catch (e: NotImplementedError) {
                result.notImplemented()
            } catch (e: Throwable) {
                val root = generateSequence(e) { it.cause }.last()
                result.error("ext", root.message ?: root.javaClass.simpleName, e.javaClass.name)
            }
        }
    }

    // ── System ──────────────────────────────────────────────────────────────

    private fun onSystem(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "setIcon" -> {
                getSharedPreferences("playz", MODE_PRIVATE).edit()
                    .putString("icon", call.argument<String>("accent") ?: "shu").apply()
                result.success(null)
            }
            "pipSupported" -> result.success(
                Build.VERSION.SDK_INT >= 26 && packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE),
            )
            "pip" -> result.success(enterPip())
            "armPip" -> {
                pipArmed = call.argument<Boolean>("on") == true
                val w = call.argument<Int>("w") ?: 16
                val h = call.argument<Int>("h") ?: 9
                pipRatio = Rational(w.coerceAtLeast(1), h.coerceAtLeast(1))
                if (Build.VERSION.SDK_INT >= 31) {
                    runCatching { setPictureInPictureParams(pipParams().setAutoEnterEnabled(pipArmed).build()) }
                }
                result.success(null)
            }
            "getBrightness" -> {
                val own = window.attributes.screenBrightness
                val v = if (own >= 0) own else runCatching {
                    Settings.System.getInt(contentResolver, Settings.System.SCREEN_BRIGHTNESS) / 255f
                }.getOrDefault(0.5f)
                result.success(v.toDouble())
            }
            "setBrightness" -> {
                val v = (call.argument<Double>("value") ?: -1.0).toFloat()
                window.attributes = window.attributes.apply { screenBrightness = if (v < 0) -1f else v.coerceIn(0.01f, 1f) }
                result.success(null)
            }
            "getVolume" -> {
                val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                val max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC).toDouble()
                result.success(am.getStreamVolume(AudioManager.STREAM_MUSIC) / max)
            }
            "setVolume" -> {
                val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                val max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                val v = ((call.argument<Double>("value") ?: 0.0) * max).toInt().coerceIn(0, max)
                am.setStreamVolume(AudioManager.STREAM_MUSIC, v, 0)
                result.success(null)
            }
            "permissions" -> result.success(permissionState())
            "requestNotifications" -> {
                if (Build.VERSION.SDK_INT >= 33) {
                    requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 41)
                }
                result.success(null)
            }
            "requestFiles" -> {
                if (Build.VERSION.SDK_INT >= 30) {
                    val intent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION, Uri.parse("package:$packageName"))
                    runCatching { startActivity(intent) }.onFailure {
                        startActivity(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION))
                    }
                } else {
                    requestPermissions(
                        arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE, Manifest.permission.READ_EXTERNAL_STORAGE),
                        42,
                    )
                }
                result.success(null)
            }
            "openAppSettings" -> {
                startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName")))
                result.success(null)
            }
            "downloadProgress" -> {
                DownloadService.update(
                    this,
                    call.argument<String>("title") ?: "",
                    call.argument<String>("text") ?: "",
                    call.argument<Int>("percent") ?: -1,
                    call.argument<Int>("active") ?: 0,
                )
                result.success(null)
            }
            "downloadDone" -> {
                DownloadService.stop(this)
                val title = call.argument<String>("title")
                if (!title.isNullOrEmpty()) Notify.finished(this, title, call.argument<String>("text") ?: "")
                result.success(null)
            }
            "nowPlaying" -> {
                Notify.nowPlaying(
                    this,
                    call.argument<String>("title") ?: "",
                    call.argument<String>("text") ?: "",
                    call.argument<Boolean>("playing") == true,
                    call.argument<Boolean>("hasNext") == true,
                )
                result.success(null)
            }
            "stopPlaying" -> {
                Notify.stopPlaying(this)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun permissionState(): Map<String, Boolean> {
        val notif = Build.VERSION.SDK_INT < 33 ||
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        val files = when {
            Build.VERSION.SDK_INT >= 30 -> Environment.isExternalStorageManager()
            else -> checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED
        }
        return mapOf("notifications" to notif, "files" to files)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        system?.invokeMethod("permissions", permissionState())
    }

    override fun onResume() {
        super.onResume()
        // Coming back from the "All files access" screen.
        system?.invokeMethod("permissions", permissionState())
    }

    // ── Picture-in-picture ──────────────────────────────────────────────────

    private fun pipParams(): PictureInPictureParams.Builder =
        PictureInPictureParams.Builder().setAspectRatio(pipRatio)

    private fun enterPip(): Boolean {
        if (Build.VERSION.SDK_INT < 26) return false
        return runCatching { enterPictureInPictureMode(pipParams().build()) }.getOrDefault(false)
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (pipArmed) {
            if (Build.VERSION.SDK_INT in 26..30) enterPip()
            return
        }
        // Swapping the launcher alias ends the task on most launchers, so it only
        // happens when the user leaves on purpose (Home / Recents) — never when
        // the app opens a system screen like the permission page.
        applyIcon()
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        system?.invokeMethod("pip", isInPictureInPictureMode)
    }

    // ── Launcher icon ───────────────────────────────────────────────────────

    private fun applyIcon() {
        val want = getSharedPreferences("playz", MODE_PRIVATE).getString("icon", "shu") ?: "shu"
        val pm = packageManager
        for (accent in ACCENTS) {
            val component = ComponentName(this, "tv.playzae.playzanime.Icon_$accent")
            val state = if (accent == want) {
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED
            } else {
                PackageManager.COMPONENT_ENABLED_STATE_DISABLED
            }
            runCatching {
                if (pm.getComponentEnabledSetting(component) != state) {
                    pm.setComponentEnabledSetting(component, state, PackageManager.DONT_KILL_APP)
                }
            }
        }
    }

    override fun onDestroy() {
        if (isFinishing) {
            Notify.stopPlaying(this)
            applyIcon()
        }
        super.onDestroy()
    }

    companion object {
        val ACCENTS = listOf("shu", "matcha", "ai", "yamabuki", "sakura")
    }
}
