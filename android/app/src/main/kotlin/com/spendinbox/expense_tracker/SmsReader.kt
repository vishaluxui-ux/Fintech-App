package com.spendinbox.expense_tracker

import android.content.Context
import android.net.Uri

/**
 * Reads bank transaction SMS for the opt-in bank SMS feature (N-01).
 * Only messages from DLT sender headers (like "AD-HDFCBK" or "VM-SBIUPI-S") are returned;
 * SMS from phone numbers (personal messages) are skipped here and never reach the app.
 * Nothing is stored or sent: the Flutter side parses the payment on the phone.
 */
object SmsReader {
    private val DLT_SENDER = Regex("^[A-Za-z]{2}-[A-Za-z0-9]{6}(-[A-Za-z])?$")
    private const val MAX_ROWS = 500

    fun bankSmsSince(ctx: Context, sinceMillis: Long): List<Map<String, Any>> {
        val out = mutableListOf<Map<String, Any>>()
        ctx.contentResolver.query(
            Uri.parse("content://sms/inbox"),
            arrayOf("address", "body", "date"),
            "date > ?",
            arrayOf(sinceMillis.toString()),
            "date DESC"
        )?.use { c ->
            val a = c.getColumnIndex("address")
            val b = c.getColumnIndex("body")
            val d = c.getColumnIndex("date")
            while (c.moveToNext() && out.size < MAX_ROWS) {
                val address = c.getString(a) ?: continue
                if (!DLT_SENDER.matches(address.trim())) continue
                out.add(mapOf("address" to address.trim(), "body" to (c.getString(b) ?: ""), "date" to c.getLong(d)))
            }
        }
        return out
    }
}
