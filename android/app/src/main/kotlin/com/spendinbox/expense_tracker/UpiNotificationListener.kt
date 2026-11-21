package com.spendinbox.expense_tracker

import android.app.Notification
import android.content.Context
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import org.json.JSONArray
import org.json.JSONObject

/**
 * Reads notifications from supported UPI and bank apps only (CAP-01, CAP-05).
 * Every other app's notification is dropped immediately and never stored.
 * Matching ones are queued on the device until the Flutter side drains them.
 * Keep SUPPORTED in sync with lib/domain/upi_parser.dart.
 */
class UpiNotificationListener : NotificationListenerService() {
    companion object {
        val SUPPORTED = setOf(
            "com.google.android.apps.nbu.paisa.user", "com.phonepe.app", "net.one97.paytm",
            "in.org.npci.upiapp", "in.amazon.mShop.android.shopping", "com.dreamplug.androidapp",
            "com.csam.icici.bank.imobile", "com.snapwork.hdfc", "com.sbi.lotusintouch", "com.axis.mobile"
        )
        private const val PREFS = "upi_queue"
        private const val KEY = "items"
        var onNew: (() -> Unit)? = null

        @Synchronized
        fun drain(ctx: Context): List<Map<String, Any>> {
            val p = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val arr = JSONArray(p.getString(KEY, "[]"))
            p.edit().putString(KEY, "[]").apply()
            return (0 until arr.length()).map { i ->
                val o = arr.getJSONObject(i)
                mapOf("package" to o.getString("package"), "title" to o.optString("title"),
                    "text" to o.optString("text"), "postedAt" to o.getLong("postedAt"))
            }
        }

        @Synchronized
        private fun enqueue(ctx: Context, o: JSONObject) {
            val p = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val arr = JSONArray(p.getString(KEY, "[]"))
            // The same alert can be re-posted when updated; skip exact repeats.
            for (i in 0 until arr.length()) {
                val e = arr.getJSONObject(i)
                if (e.getString("key") == o.getString("key") && e.optString("text") == o.optString("text")) return
            }
            arr.put(o)
            p.edit().putString(KEY, arr.toString()).apply()
        }
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        if (sbn.packageName !in SUPPORTED) return
        val extras = sbn.notification.extras
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
        val text = (extras.getCharSequence(Notification.EXTRA_BIG_TEXT)
            ?: extras.getCharSequence(Notification.EXTRA_TEXT))?.toString() ?: ""
        if (title.isBlank() && text.isBlank()) return
        enqueue(applicationContext, JSONObject()
            .put("key", sbn.key).put("package", sbn.packageName)
            .put("title", title).put("text", text).put("postedAt", sbn.postTime))
        onNew?.invoke()
    }
}
