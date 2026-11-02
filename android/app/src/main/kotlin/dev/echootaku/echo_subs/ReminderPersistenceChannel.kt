package dev.echootaku.echo_subs

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec

/**
 * flutter_local_notifications 22.3.3 writes this exact SharedPreferences file
 * with apply(). Recheck the cache name and write semantics on plugin upgrades.
 * commit() on the same preferences waits for outstanding apply() writes and
 * reports persistence failure. The serial background task queue keeps disk IO
 * off the platform UI thread. This does not guarantee alarm delivery by the OS.
 */
internal class ReminderPersistenceChannel(context: Context, messenger: BinaryMessenger) {
    private val appContext = context.applicationContext
    private val channel = MethodChannel(
        messenger,
        "dev.echootaku.echo_subs/reminder_persistence",
        StandardMethodCodec.INSTANCE,
        messenger.makeBackgroundTaskQueue(),
    )

    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method != "flushScheduledNotifications") {
                result.notImplemented()
            } else {
                val persisted = try {
                    appContext.getSharedPreferences("scheduled_notifications", Context.MODE_PRIVATE)
                        .edit().commit()
                } catch (_: Exception) {
                    false
                }
                if (persisted) {
                    result.success(true)
                } else {
                    // No native exception, filesystem path or payload crosses the channel.
                    result.error("reminder_persistence", "提醒缓存持久化失败，请重试", null)
                }
            }
        }
    }

    fun close() { channel.setMethodCallHandler(null) }
}
