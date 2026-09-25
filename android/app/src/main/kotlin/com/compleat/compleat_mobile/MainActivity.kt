package com.compleat.compleat_mobile

import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob

class MainActivity : FlutterActivity() {
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private var scannerStatus: ScannerStatusPlugin? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.compleat/printer"
        ).setMethodCallHandler(BrotherPrinterPlugin(applicationContext, scope))

        // Zebra DataWedge scanner status + key-event diagnostics (see ScannerStatusPlugin).
        val plugin = ScannerStatusPlugin(applicationContext)
        scannerStatus = plugin
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            ScannerStatusPlugin.CHANNEL
        ).setStreamHandler(plugin)
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        // Diagnostics only (Joe's requirement 2): report every hardware key the
        // Activity sees, then let Flutter handle it exactly as before.
        scannerStatus?.onKeyEvent(event)
        return super.dispatchKeyEvent(event)
    }
}
