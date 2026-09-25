package com.compleat.compleat_mobile

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.KeyEvent
import io.flutter.plugin.common.EventChannel

/**
 * Zebra DataWedge scanner-status bridge (Joe's ruling 2026-09-25, option 1 —
 * "no-read = skip": a trigger pull with nothing to decode advances the cursor
 * on the Receive screen).
 *
 * DataWedge's keystroke output sends NOTHING on a no-read, so the app cannot
 * hear a failed pull from the text field. The one documented signal is the
 * DataWedge Notification API (DataWedge >= 6.4): the app registers for
 * SCANNER_STATUS and receives WAITING / SCANNING / IDLE / CONNECTED /
 * DISCONNECTED / DISABLED as the scanner changes state. The Dart side turns
 * "SCANNING then WAITING with no keystrokes" into a no-read.
 *
 * Also forwards every hardware key event the Activity sees (diagnostics for
 * the TC22 walkthrough: does the trigger key ever reach the app?).
 *
 * GRACEFUL DEGRADATION (Joe's requirement 1): on a device without DataWedge
 * the REGISTER broadcast has no receiver and simply does nothing; the
 * broadcast receiver never fires; nothing here blocks, throws or delays —
 * every call is wrapped so a failure only logs.
 */
class ScannerStatusPlugin(private val context: Context) : EventChannel.StreamHandler {

    companion object {
        const val CHANNEL = "com.compleat/scanner_status"
        private const val TAG = "ScannerStatus"
        private const val DW_ACTION = "com.symbol.datawedge.api.ACTION"
        private const val DW_REGISTER = "com.symbol.datawedge.api.REGISTER_FOR_NOTIFICATION"
        private const val DW_UNREGISTER = "com.symbol.datawedge.api.UNREGISTER_FOR_NOTIFICATION"
        private const val DW_NOTIFICATION_ACTION = "com.symbol.datawedge.api.NOTIFICATION_ACTION"
        private const val DW_NOTIFICATION = "com.symbol.datawedge.api.NOTIFICATION"
        private const val DW_TYPE_SCANNER_STATUS = "SCANNER_STATUS"
    }

    private val main = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null
    private var receiver: BroadcastReceiver? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
        try {
            val r = object : BroadcastReceiver() {
                override fun onReceive(ctx: Context?, intent: Intent?) {
                    try {
                        if (intent?.action != DW_NOTIFICATION_ACTION) return
                        val b: Bundle = intent.getBundleExtra(DW_NOTIFICATION) ?: return
                        val type = b.getString("NOTIFICATION_TYPE") ?: return
                        if (type != DW_TYPE_SCANNER_STATUS) return
                        emit(mapOf(
                            "type" to "status",
                            "status" to (b.getString("STATUS") ?: ""),
                            "profile" to (b.getString("PROFILE_NAME") ?: ""),
                            "t" to System.currentTimeMillis(),
                        ))
                    } catch (e: Exception) {
                        Log.w(TAG, "notification parse failed: $e")
                    }
                }
            }
            val filter = IntentFilter(DW_NOTIFICATION_ACTION)
            // DataWedge is another app, so the receiver must be exported (API 33+ flag).
            if (Build.VERSION.SDK_INT >= 33) {
                context.registerReceiver(r, filter, Context.RECEIVER_EXPORTED)
            } else {
                @Suppress("UnspecifiedRegisterReceiverFlag")
                context.registerReceiver(r, filter)
            }
            receiver = r
            sendDw(DW_REGISTER)
            emit(mapOf("type" to "listening", "t" to System.currentTimeMillis()))
        } catch (e: Exception) {
            // Non-Zebra device or anything unexpected: stay silent, never crash.
            Log.w(TAG, "listen setup failed (no DataWedge?): $e")
        }
    }

    override fun onCancel(arguments: Any?) {
        try {
            sendDw(DW_UNREGISTER)
            receiver?.let { context.unregisterReceiver(it) }
        } catch (e: Exception) {
            Log.w(TAG, "cancel failed: $e")
        }
        receiver = null
        sink = null
    }

    /** Diagnostics: MainActivity forwards every KeyEvent it dispatches. */
    fun onKeyEvent(event: KeyEvent) {
        if (sink == null) return
        try {
            emit(mapOf(
                "type" to "key",
                "keyCode" to event.keyCode,
                "keyName" to KeyEvent.keyCodeToString(event.keyCode),
                "action" to event.action,          // 0 = down, 1 = up
                "scanCode" to event.scanCode,
                "source" to event.source,
                "repeat" to event.repeatCount,
                "t" to System.currentTimeMillis(),
            ))
        } catch (e: Exception) {
            Log.w(TAG, "key forward failed: $e")
        }
    }

    private fun sendDw(extra: String) {
        // Zebra's documented API: an implicit broadcast carrying a Bundle of
        // {APPLICATION_NAME, NOTIFICATION_TYPE}. No DataWedge → no receiver → no-op.
        val b = Bundle().apply {
            putString("com.symbol.datawedge.api.APPLICATION_NAME", context.packageName)
            putString("com.symbol.datawedge.api.NOTIFICATION_TYPE", DW_TYPE_SCANNER_STATUS)
        }
        val i = Intent(DW_ACTION).apply { putExtra(extra, b) }
        context.sendBroadcast(i)
    }

    private fun emit(payload: Map<String, Any?>) {
        val s = sink ?: return
        if (Looper.myLooper() == Looper.getMainLooper()) s.success(payload)
        else main.post { sink?.success(payload) }
    }
}
