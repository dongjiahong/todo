package com.lele.navigator.notify

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.lele.navigator.MainActivity
import com.lele.navigator.model.DateUtils
import com.lele.navigator.model.TaskItem
import java.time.ZoneId

object ReminderScheduler {
    const val CHANNEL_ID = "todo_reminders"
    const val EXTRA_TASK_ID = "task_id"
    const val EXTRA_TITLE = "title"
    const val EXTRA_BODY = "body"

    fun ensureChannel(context: Context) {
        val mgr = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (mgr.getNotificationChannel(CHANNEL_ID) == null) {
            val ch = NotificationChannel(
                CHANNEL_ID,
                "TODO 任务提醒",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "任务到期准点提醒"
                enableVibration(true)
            }
            mgr.createNotificationChannel(ch)
        }
    }

    fun hasNotificationPermission(context: Context): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED
        } else {
            NotificationManagerCompat.from(context).areNotificationsEnabled()
        }
    }

    fun rescheduleAll(context: Context, tasks: List<TaskItem>, leadMinutes: Int = 0) {
        ensureChannel(context)
        val alarmMgr = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val nowMs = System.currentTimeMillis()

        for (task in tasks) {
            val reqCode = task.id.hashCode()
            val preReqCode = ("pre_" + task.id).hashCode()
            val intent = Intent(context, ReminderReceiver::class.java).apply {
                putExtra(EXTRA_TASK_ID, task.id)
                putExtra(EXTRA_TITLE, task.title.ifBlank { "任务到期" })
                putExtra(EXTRA_BODY, task.notes.ifBlank { "截止时间到了" })
            }
            val pending = PendingIntent.getBroadcast(
                context,
                reqCode,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            val preIntent = Intent(context, ReminderReceiver::class.java).apply {
                putExtra(EXTRA_TASK_ID, task.id)
                putExtra(EXTRA_TITLE, "即将到期：${task.title.ifBlank { "未命名任务" }}")
                putExtra(EXTRA_BODY, "距离截止还有 $leadMinutes 分钟")
            }
            val prePending = PendingIntent.getBroadcast(
                context,
                preReqCode,
                preIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            if (task.deleted || task.isDone || task.dueAt.isNullOrBlank()) {
                alarmMgr.cancel(pending)
                alarmMgr.cancel(prePending)
                continue
            }

            val dt = DateUtils.parseDue(task.dueAt) ?: continue
            val triggerAt = dt.atZone(ZoneId.systemDefault()).toInstant().toEpochMilli()
            if (triggerAt <= nowMs + 1000L) {
                alarmMgr.cancel(pending)
                alarmMgr.cancel(prePending)
                continue
            }

            runCatching {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !alarmMgr.canScheduleExactAlarms()) {
                    alarmMgr.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pending)
                } else {
                    alarmMgr.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pending)
                }
            }

            val preTriggerAt = triggerAt - leadMinutes * 60_000L
            if (leadMinutes > 0 && preTriggerAt > nowMs + 1000L) {
                runCatching {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !alarmMgr.canScheduleExactAlarms()) {
                        alarmMgr.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, preTriggerAt, prePending)
                    } else {
                        alarmMgr.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, preTriggerAt, prePending)
                    }
                }
            } else {
                alarmMgr.cancel(prePending)
            }
        }
    }

    fun sendTestNotification(context: Context) {
        ensureChannel(context)
        if (!hasNotificationPermission(context)) return
        val openIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val contentPi = PendingIntent.getActivity(
            context, 9999, openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val notif = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_popup_reminder)
            .setContentTitle("TODO 通知测试")
            .setContentText("后台定时提醒已生效，任务到期会准时通知你。")
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(contentPi)
            .build()
        NotificationManagerCompat.from(context).notify(9999, notif)
    }
}

class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        ReminderScheduler.ensureChannel(context)
        if (!ReminderScheduler.hasNotificationPermission(context)) return

        val taskId = intent.getStringExtra(ReminderScheduler.EXTRA_TASK_ID) ?: return
        val title = intent.getStringExtra(ReminderScheduler.EXTRA_TITLE) ?: "任务到期"
        val body = intent.getStringExtra(ReminderScheduler.EXTRA_BODY) ?: "截止时间到了"

        val openIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val contentPi = PendingIntent.getActivity(
            context, taskId.hashCode(), openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notif = NotificationCompat.Builder(context, ReminderScheduler.CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_popup_reminder)
            .setContentTitle(title)
            .setContentText(body)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(contentPi)
            .build()

        NotificationManagerCompat.from(context).notify(taskId.hashCode(), notif)
    }
}
