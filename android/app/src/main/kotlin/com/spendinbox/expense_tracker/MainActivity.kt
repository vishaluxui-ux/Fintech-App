package com.spendinbox.expense_tracker

import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.speech.RecognizerIntent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // A screenshot shared from a UPI app (or any app), copied into the cache.
    private var sharedImagePath: String? = null

    // Waiting for Android's speech screen to return what the user said.
    private var voiceResult: MethodChannel.Result? = null
    private val voiceRequestCode = 4301

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        captureShare(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        captureShare(intent)
    }

    @Suppress("DEPRECATION")
    private fun captureShare(intent: Intent?) {
        if (intent?.action != Intent.ACTION_SEND || intent.type?.startsWith("image/") != true) return
        val uri: Uri = intent.getParcelableExtra(Intent.EXTRA_STREAM) ?: return
        try {
            val ext = if (intent.type == "image/png") "png" else "jpg"
            val out = java.io.File(cacheDir, "shared_${System.currentTimeMillis()}.$ext")
            contentResolver.openInputStream(uri)?.use { input -> out.outputStream().use { input.copyTo(it) } }
            sharedImagePath = out.absolutePath
        } catch (_: Exception) { }
    }

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
                "recentSeen" -> result.success(UpiNotificationListener.recentSeen().map { n ->
                    val pkg = n["package"] as String
                    val label = try {
                        packageManager.getApplicationLabel(packageManager.getApplicationInfo(pkg, 0)).toString()
                    } catch (_: Exception) { pkg }
                    n + mapOf("label" to label)
                })
                "takeSharedImage" -> { result.success(sharedImagePath); sharedImagePath = null }
                else -> result.notImplemented()
            }
        }
        // Voice expense notes: Android's own speech screen handles the microphone,
        // so the app needs no microphone permission. Only the text comes back.
        MethodChannel(engine.dartExecutor.binaryMessenger, "spendinbox/voice").setMethodCallHandler { call, result ->
            when (call.method) {
                "listen" -> {
                    voiceResult?.success(null)
                    voiceResult = result
                    val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                        putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                        putExtra(RecognizerIntent.EXTRA_LANGUAGE, call.argument<String>("language") ?: "en-IN")
                        putExtra(RecognizerIntent.EXTRA_PROMPT, call.argument<String>("prompt") ?: "Say what you spent")
                        putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
                    }
                    try {
                        startActivityForResult(intent, voiceRequestCode)
                    } catch (_: ActivityNotFoundException) {
                        voiceResult = null
                        result.error("unavailable", "No speech recognition on this phone", null)
                    }
                }
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

    @Deprecated("Deprecated in Android; still the simplest way to get the speech screen's result")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != voiceRequestCode) return
        val text = if (resultCode == RESULT_OK)
            data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)?.firstOrNull() else null
        voiceResult?.success(text)
        voiceResult = null
    }

    private fun hasAccess(): Boolean {
        val flat = Settings.Secure.getString(contentResolver, "enabled_notification_listeners") ?: return false
        val me = ComponentName(this, UpiNotificationListener::class.java).flattenToString()
        return flat.split(":").any { it == me }
    }
}
