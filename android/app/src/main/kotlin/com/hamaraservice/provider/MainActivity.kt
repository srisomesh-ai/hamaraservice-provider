package com.hamaraservice.provider

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity

class MainActivity: FlutterActivity() {
    override fun onStart() {
        super.onStart()
        createNotificationChannels()
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)

            // High priority channel — matches AndroidManifest + FCM config
            val channel = NotificationChannel(
                "hamaraservice_high_priority",
                "HamaraService Alerts",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "New job alerts and payment notifications"
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 500, 200, 500, 200, 500)
                enableLights(true)
                setShowBadge(true)
                lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
                setBypassDnd(false)
            }
            manager.createNotificationChannel(channel)

            // Also create old channel ID for backward compatibility
            val oldChannel = NotificationChannel(
                "booking_alerts",
                "Booking Alerts",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "New booking notifications"
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 500, 200, 500)
                enableLights(true)
            }
            manager.createNotificationChannel(oldChannel)
        }
    }
}
