package tw.exposure.assistant

import android.Manifest
import android.app.*
import android.content.*
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.*
import android.provider.Settings
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.json.JSONObject
import java.util.UUID
import kotlin.math.roundToLong

data class TimerState(
    val id: String = "", val status: String = "idle", val endElapsed: Long = 0,
    val durationMs: Long = 0, val boot: Int = -1, val background: Boolean = false,
    val sound: Boolean = true, val vibration: Boolean = true
) {
    fun encode() = JSONObject().put("id", id).put("status", status).put("endElapsed", endElapsed).put("durationMs", durationMs).put("boot", boot).put("background", background).put("sound", sound).put("vibration", vibration).toString()
    companion object {
        fun decode(text: String?): TimerState = runCatching {
            val j = JSONObject(text ?: "{}")
            TimerState(j.optString("id"), j.optString("status", "idle"), j.optLong("endElapsed"), j.optLong("durationMs"), j.optInt("boot", -1), j.optBoolean("background"), j.optBoolean("sound", true), j.optBoolean("vibration", true))
        }.getOrDefault(TimerState())
    }
}
class TimerController(private val context: Context, private val repository: Repository) {
    private val alarm = context.getSystemService(AlarmManager::class.java)
    private val manager = context.getSystemService(NotificationManager::class.java)
    companion object {
        private val mutex = Mutex()
        const val NOTIFICATION_ID = 100
        const val MAX_SECONDS = 604800.0
        fun channelId(sound: Boolean, vibration: Boolean) = "exposure_end_${sound}_${vibration}"
    }
    fun exactAllowed(): Boolean = Build.VERSION.SDK_INT < 31 || alarm.canScheduleExactAlarms()
    fun notificationsAllowed(): Boolean = NotificationManagerCompat.from(context).areNotificationsEnabled() &&
        (Build.VERSION.SDK_INT < 33 || ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED)
    fun backgroundAvailable(sound: Boolean, vibration: Boolean): Boolean {
        createChannel(sound, vibration)
        return exactAllowed() && notificationsAllowed() && manager.getNotificationChannel(channelId(sound,vibration)).importance != NotificationManager.IMPORTANCE_NONE
    }
    private fun bootCount() = Settings.Global.getInt(context.contentResolver, Settings.Global.BOOT_COUNT, -1)
    private fun pending(id: String) = PendingIntent.getBroadcast(context, 1, Intent(context, TimerReceiver::class.java).putExtra("id", id), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    private fun openApp() = PendingIntent.getActivity(context, 2, Intent(context, MainActivity::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    private fun schedule(t: TimerState) {
        // AlarmClock is intentionally user-visible and avoids idle alarm frequency batching.
        val wall = System.currentTimeMillis() + (t.endElapsed - SystemClock.elapsedRealtime()).coerceAtLeast(1)
        alarm.setAlarmClock(AlarmManager.AlarmClockInfo(wall, openApp()), pending(t.id))
    }
    suspend fun start(seconds: Double, useBackground: Boolean, sound: Boolean, vibration: Boolean) = mutex.withLock {
        require(seconds.isFinite() && seconds >= 0.1 && seconds <= MAX_SECONDS) { "計時支援 0.1 秒至 7 天；更長時間請分段安排。" }
        require(repository.timer.first().status != "active") { "已有曝光正在計時，請先取消。" }
        require(!useBackground || backgroundAvailable(sound,vibration)) { "背景提醒尚未就緒，請授權或選擇前景計時。" }
        val ms = (seconds * 1000).roundToLong()
        var t = TimerState(UUID.randomUUID().toString(), "active", SystemClock.elapsedRealtime() + ms, ms, bootCount(), useBackground, sound, vibration)
        repository.changeTimer { t }
        if (useBackground) {
            try { schedule(t) } catch (_: SecurityException) {
                t = t.copy(background = false)
                repository.changeTimer { t }
            }
        }
        manager.cancel(NOTIFICATION_ID)
    }
    suspend fun cancel() = mutex.withLock {
        val t = repository.timer.first()
        alarm.cancel(pending(t.id))
        repository.changeTimer { it.copy(status = "idle") }
        manager.cancel(NOTIFICATION_ID)
    }
    suspend fun checkBoot() = mutex.withLock {
        val t = repository.timer.first()
        if (t.status == "active" && t.boot != bootCount()) repository.changeTimer { it.copy(status = "interrupted", background = false) }
    }
    suspend fun interruptedByBoot() = mutex.withLock {
        repository.changeTimer { if (it.status == "active") it.copy(status = "interrupted", background = false) else it }
    }
    suspend fun reconcile() {
        checkBoot()
        mutex.withLock {
            val t = repository.timer.first()
            if (t.status == "active" && t.background) {
                if (!backgroundAvailable(t.sound,t.vibration)) repository.changeTimer { it.copy(background = false) }
                else if (t.endElapsed > SystemClock.elapsedRealtime()) runCatching { schedule(t) }.onFailure { repository.changeTimer { it.copy(background = false) } }
            }
        }
    }
    suspend fun finish(id: String, foreground: Boolean = false) = mutex.withLock {
        val t = repository.timer.first()
        if (t.id != id || t.status != "active") return@withLock
        if (t.boot != bootCount()) { repository.changeTimer { it.copy(status = "interrupted", background = false) }; return@withLock }
        if (SystemClock.elapsedRealtime() < t.endElapsed) return@withLock
        repository.changeTimer { it.copy(status = "completed") }
        alarm.cancel(pending(id))
        createChannel(t.sound, t.vibration)
        if (notificationsAllowed()) {
            val n = NotificationCompat.Builder(context, channelId(t.sound,t.vibration))
                .setSmallIcon(R.drawable.ic_timer_notification).setContentTitle("曝光時間已到")
                .setContentText("${number(t.durationMs / 1000.0)} 秒已結束，請手動關閉相機快門。")
                .setContentIntent(openApp()).setAutoCancel(true).setCategory(NotificationCompat.CATEGORY_ALARM)
                .setPriority(NotificationCompat.PRIORITY_HIGH).build()
            try { manager.notify(NOTIFICATION_ID, n) } catch (_: SecurityException) { if (foreground) foregroundSignal(t) }
        } else if (foreground) foregroundSignal(t)
    }
    private fun createChannel(sound: Boolean, vibration: Boolean) {
        val channel = NotificationChannel(channelId(sound,vibration), "曝光結束${if(sound) "・聲音" else "・靜音"}${if(vibration) "・震動" else ""}", NotificationManager.IMPORTANCE_HIGH)
        channel.description = "曝光倒數結束時提醒；聲音仍受系統音量與勿擾模式控制。"
        channel.enableVibration(vibration)
        if (vibration) channel.vibrationPattern = longArrayOf(0,500,250,500)
        channel.setSound(if(sound) RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM) else null,
            AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM).setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build())
        manager.createNotificationChannel(channel)
    }
    private fun foregroundSignal(t: TimerState) {
        if (t.vibration) {
            @Suppress("DEPRECATION") val vibrator = context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            vibrator.vibrate(VibrationEffect.createWaveform(longArrayOf(0,500,250,500), -1))
        }
        if (t.sound) runCatching {
            val ring = RingtoneManager.getRingtone(context, RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM))
            ring.audioAttributes = AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM).build()
            ring.play()
            Handler(Looper.getMainLooper()).postDelayed({ ring.stop() }, 6000)
        }
    }
}
class TimerReceiver: BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val pending = goAsync()
        CoroutineScope(SupervisorJob() + Dispatchers.IO).launch {
            try { TimerController(context.applicationContext, Repository(context)).finish(intent.getStringExtra("id") ?: "") }
            finally { pending.finish() }
        }
    }
}
class DeviceReceiver: BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val pending = goAsync()
        CoroutineScope(SupervisorJob() + Dispatchers.IO).launch {
            try {
                val timer = TimerController(context.applicationContext, Repository(context))
                if (intent.action == Intent.ACTION_BOOT_COMPLETED) timer.interruptedByBoot() else timer.reconcile()
            } finally { pending.finish() }
        }
    }
}
