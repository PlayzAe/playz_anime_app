package tv.playzae.playzanime

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Build
import android.os.IBinder

/** Notification channels, the "now playing" card and the finished-download note. */
object Notify {
    const val DOWNLOADS = "downloads"
    const val PLAYBACK = "playback"
    const val DONE = "downloads_done"
    private const val PLAYING_ID = 7101
    const val DOWNLOAD_ID = 7102
    private var doneId = 7200

    var onAction: ((String) -> Unit)? = null
    private var session: MediaSession? = null

    fun channels(ctx: Context) {
        if (Build.VERSION.SDK_INT < 26) return
        val nm = ctx.getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(
            NotificationChannel(DOWNLOADS, "Downloads in progress", NotificationManager.IMPORTANCE_LOW).apply {
                setShowBadge(false)
            },
        )
        nm.createNotificationChannel(
            NotificationChannel(DONE, "Finished downloads", NotificationManager.IMPORTANCE_DEFAULT),
        )
        nm.createNotificationChannel(
            NotificationChannel(PLAYBACK, "Now playing", NotificationManager.IMPORTANCE_LOW).apply {
                setShowBadge(false)
            },
        )
    }

    fun builder(ctx: Context, channel: String): Notification.Builder =
        if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(ctx, channel)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(ctx)
        }

    fun openApp(ctx: Context): PendingIntent = PendingIntent.getActivity(
        ctx,
        0,
        Intent(ctx, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )

    private fun action(ctx: Context, name: String, code: Int): PendingIntent = PendingIntent.getBroadcast(
        ctx,
        code,
        Intent(ctx, MediaReceiver::class.java).setAction("tv.playzae.playzanime.$name"),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )

    fun nowPlaying(ctx: Context, title: String, text: String, playing: Boolean, hasNext: Boolean) {
        val s = session ?: MediaSession(ctx, "PlayzAnime").also {
            it.setCallback(object : MediaSession.Callback() {
                override fun onPlay() { onAction?.invoke("play") }
                override fun onPause() { onAction?.invoke("pause") }
                override fun onSkipToNext() { onAction?.invoke("next") }
                override fun onFastForward() { onAction?.invoke("forward") }
                override fun onRewind() { onAction?.invoke("back") }
            })
            session = it
        }
        s.isActive = true
        s.setPlaybackState(
            PlaybackState.Builder()
                .setActions(
                    PlaybackState.ACTION_PLAY or PlaybackState.ACTION_PAUSE or PlaybackState.ACTION_PLAY_PAUSE or
                        PlaybackState.ACTION_SKIP_TO_NEXT or PlaybackState.ACTION_FAST_FORWARD or PlaybackState.ACTION_REWIND,
                )
                .setState(
                    if (playing) PlaybackState.STATE_PLAYING else PlaybackState.STATE_PAUSED,
                    PlaybackState.PLAYBACK_POSITION_UNKNOWN,
                    1f,
                )
                .build(),
        )
        val b = builder(ctx, PLAYBACK)
            .setSmallIcon(R.drawable.ic_stat_playz)
            .setContentTitle(title)
            .setContentText(text)
            .setContentIntent(openApp(ctx))
            .setOngoing(playing)
            .setShowWhen(false)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .addAction(Notification.Action.Builder(null, "Back 5s", action(ctx, "back", 1)).build())
            .addAction(
                Notification.Action.Builder(
                    null,
                    if (playing) "Pause" else "Play",
                    action(ctx, if (playing) "pause" else "play", 2),
                ).build(),
            )
        if (hasNext) b.addAction(Notification.Action.Builder(null, "Next", action(ctx, "next", 3)).build())
        val compact = if (hasNext) intArrayOf(0, 1, 2) else intArrayOf(0, 1)
        b.setStyle(Notification.MediaStyle().setMediaSession(s.sessionToken).setShowActionsInCompactView(*compact))
        runCatching { ctx.getSystemService(NotificationManager::class.java).notify(PLAYING_ID, b.build()) }
    }

    fun stopPlaying(ctx: Context) {
        runCatching { ctx.getSystemService(NotificationManager::class.java).cancel(PLAYING_ID) }
        session?.release()
        session = null
    }

    fun finished(ctx: Context, title: String, text: String) {
        val n = builder(ctx, DONE)
            .setSmallIcon(R.drawable.ic_stat_playz)
            .setContentTitle(title)
            .setContentText(text)
            .setContentIntent(openApp(ctx))
            .setAutoCancel(true)
            .build()
        runCatching { ctx.getSystemService(NotificationManager::class.java).notify(doneId++, n) }
    }
}

class MediaReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val name = intent.action?.substringAfterLast('.') ?: return
        Notify.onAction?.invoke(name)
    }
}

/**
 * Keeps the process alive while episodes download in the background and shows the
 * progress. The downloading itself happens in Dart; this only holds the foreground slot.
 */
class DownloadService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val n = build(
            this,
            intent?.getStringExtra("title") ?: "Downloading",
            intent?.getStringExtra("text") ?: "",
            intent?.getIntExtra("percent", -1) ?: -1,
        )
        if (Build.VERSION.SDK_INT >= 29) {
            startForeground(Notify.DOWNLOAD_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            startForeground(Notify.DOWNLOAD_ID, n)
        }
        return START_NOT_STICKY
    }

    override fun onTimeout(startId: Int, fgsType: Int) {
        // Android 15 caps dataSync services; the Dart queue resumes on the next launch.
        stopSelf()
    }

    companion object {
        private var running = false

        fun build(ctx: Context, title: String, text: String, percent: Int): Notification =
            Notify.builder(ctx, Notify.DOWNLOADS)
                .setSmallIcon(android.R.drawable.stat_sys_download)
                .setContentTitle(title)
                .setContentText(text)
                .setContentIntent(Notify.openApp(ctx))
                .setOnlyAlertOnce(true)
                .setOngoing(true)
                .setShowWhen(false)
                .setProgress(100, percent.coerceIn(0, 100), percent < 0)
                .build()

        fun update(ctx: Context, title: String, text: String, percent: Int, active: Int) {
            if (active <= 0) return stop(ctx)
            if (!running) {
                running = true
                val i = Intent(ctx, DownloadService::class.java)
                    .putExtra("title", title)
                    .putExtra("text", text)
                    .putExtra("percent", percent)
                runCatching {
                    if (Build.VERSION.SDK_INT >= 26) ctx.startForegroundService(i) else ctx.startService(i)
                }.onFailure { running = false }
                return
            }
            runCatching {
                ctx.getSystemService(NotificationManager::class.java)
                    .notify(Notify.DOWNLOAD_ID, build(ctx, title, text, percent))
            }
        }

        fun stop(ctx: Context) {
            if (!running) return
            running = false
            runCatching { ctx.stopService(Intent(ctx, DownloadService::class.java)) }
        }
    }
}
