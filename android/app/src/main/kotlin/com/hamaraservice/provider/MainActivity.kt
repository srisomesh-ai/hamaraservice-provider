package com.hamaraservice.provider

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity

class MainActivity: FlutterActivity() {
    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannels()
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)

            // Primary high-priority channel — new jobs, OTP, payments
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
                setBypassDnd(true)  // Show even in Do Not Disturb
            }
            manager.createNotificationChannel(channel)

            // Backward-compat channel
            val oldChannel = NotificationChannel(
                "booking_alerts",
                "Booking Alerts",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "New booking notifications"
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 500, 200, 500)
                enableLights(true)
                setBypassDnd(true)
            }
            manager.createNotificationChannel(oldChannel)
        }
    }
}
