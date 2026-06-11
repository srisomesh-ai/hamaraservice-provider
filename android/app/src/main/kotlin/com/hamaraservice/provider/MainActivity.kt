package com.hamaraservice.provider

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity

class MainActivity: FlutterActivity() {
    override fun onStart() {
        super.onStart()
        createNotificationChannel()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)
            val channel = NotificationChannel(
                "booking_alerts",
                "Booking Alerts",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "New booking notifications"
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 500, 200, 500, 200, 500)
                enableLights(true)
                setShowBadge(true)
            }
            manager.createNotificationChannel(channel)
        }
    }
}
