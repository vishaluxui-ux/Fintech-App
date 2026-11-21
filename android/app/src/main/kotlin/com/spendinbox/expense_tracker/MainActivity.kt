package com.spendinbox.expense_tracker

import android.content.ComponentName
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        MethodChannel(engine.dartExecutor.binaryMessenger, "spendinbox/notifications").setMethodCallHandler { call, result ->
            when (call.method) {
                "hasAccess" -> result.success(hasAccess())
                "openSettings" -> {
                    startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                    result.success(null)
                }
                "drain" -> result.success(UpiNotificationListener.drain(applicationContext))
                else -> result.notImplemented()
            }
        }
        EventChannel(engine.dartExecutor.binaryMessenger, "spendinbox/notifications/events").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, sink: EventChannel.EventSink) {
                    val main = Handler(Looper.getMainLooper())
                    UpiNotificationListener.onNew = { main.post { sink.success(true) } }
                }
                override fun onCancel(args: Any?) { UpiNotificationListener.onNew = null }
            })
    }

    private fun hasAccess(): Boolean {
        val flat = Settings.Secure.getString(contentResolver, "enabled_notification_listeners") ?: return false
        val me = ComponentName(this, UpiNotificationListener::class.java).flattenToString()
        return flat.split(":").any { it == me }
    }
}
