package com.compleat.compleat_mobile

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import com.brother.sdk.lmprinter.Channel
import com.brother.sdk.lmprinter.OpenChannelError
import com.brother.sdk.lmprinter.PrinterDriverGenerator
import com.brother.sdk.lmprinter.PrinterModel
import com.brother.sdk.lmprinter.setting.QLPrintSettings
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class BrotherPrinterPlugin(
    private val context: Context,
    private val scope: CoroutineScope
) : MethodChannel.MethodCallHandler {

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "printLabel" -> {
                val productId = call.argument<String>("productId") ?: ""
                val productName = call.argument<String>("productName") ?: ""
                val parentRollId1 = call.argument<String>("parentRollId1") ?: ""
                val parentRollId2 = call.argument<String>("parentRollId2") ?: ""
                val quantity = call.argument<Int>("quantity") ?: 1
                val printerIp = call.argument<String>("printerIp") ?: ""
                if (printerIp.isEmpty()) {
                    result.error("NO_IP", "Printer IP not configured", null)
                    return
                }
                scope.launch {
                    try {
                        val success = printLabel(productId, productName, parentRollId1, parentRollId2, quantity, printerIp)
                        withContext(Dispatchers.Main) { result.success(success) }
                    } catch (e: Exception) {
                        withContext(Dispatchers.Main) { result.error("PRINT_ERROR", e.message ?: "Unknown error", null) }
                    }
                }
            }
            "getPrinterStatus" -> {
                val printerIp = call.argument<String>("printerIp") ?: ""
                if (printerIp.isEmpty()) { result.success("OFFLINE"); return }
                scope.launch {
                    val statusStr = withContext(Dispatchers.IO) {
                        try {
                            val socket = java.net.Socket()
                            socket.connect(java.net.InetSocketAddress(printerIp, 9100), 2000)
                            socket.close()
                            "READY"
                        } catch (e: Exception) {
                            "OFFLINE"
                        }
                    }
                    withContext(Dispatchers.Main) { result.success(statusStr) }
                }
            }
            "testConnection" -> {
                val printerIp = call.argument<String>("printerIp") ?: ""
                if (printerIp.isEmpty()) { result.error("NO_IP", "No IP", null); return }
                scope.launch {
                    try {
                        val reachable = withContext(Dispatchers.IO) {
                            try {
                                val socket = java.net.Socket()
                                socket.connect(java.net.InetSocketAddress(printerIp, 9100), 2000)
                                socket.close()
                                true
                            } catch (e: Exception) { false }
                        }
                        withContext(Dispatchers.Main) { result.success(reachable) }
                    } catch (e: Exception) {
                        withContext(Dispatchers.Main) { result.success(false) }
                    }
                }
            }
            "discoverPrinters" -> {
                scope.launch {
                    try {
                        val printers = withContext(Dispatchers.IO) {
                            try {
                                val channel = Channel.newWifiChannel("255.255.255.255")
                                val generateResult = PrinterDriverGenerator.openChannel(channel)
                                if (generateResult.error.code == OpenChannelError.ErrorCode.NoError) {
                                    generateResult.driver.closeChannel()
                                    listOf("192.168.2.181 (QL-1110NWB)")
                                } else emptyList()
                            } catch (e: Exception) { emptyList<String>() }
                        }
                        withContext(Dispatchers.Main) { result.success(printers) }
                    } catch (e: Exception) {
                        withContext(Dispatchers.Main) { result.success(emptyList<String>()) }
                    }
                }
            }
            else -> result.notImplemented()
        }
    }

    private suspend fun printLabel(
        productId: String, productName: String,
        parentRollId1: String, parentRollId2: String,
        quantity: Int, printerIp: String
    ): Boolean = withContext(Dispatchers.IO) {
        try { val s=java.net.Socket(); s.connect(java.net.InetSocketAddress(printerIp,9100),3000); s.close() } catch(e:Exception) { throw Exception("Printer unreachable: ${e.message}") }
        val channel = Channel.newWifiChannel(printerIp)
        val generateResult = PrinterDriverGenerator.openChannel(channel)
        if (generateResult.error.code != OpenChannelError.ErrorCode.NoError) {
            throw Exception("Cannot open channel: ${generateResult.error.code}")
        }
        val driver = generateResult.driver
        try {
            val workDir = context.cacheDir.absolutePath
            val printSettings = QLPrintSettings(PrinterModel.QL_1110NWB)
            printSettings.labelSize = QLPrintSettings.LabelSize.RollW62
            printSettings.workPath = workDir
            printSettings.isAutoCut = true
            printSettings.isCutAtEnd = true
            printSettings.autoCutForEachPageCount = 1
            val bitmap = createLabelBitmap(productId, productName, parentRollId1, parentRollId2)
            val printError = driver.printImage(bitmap, printSettings)
            printError.code.toString() == "NoError"
        } finally {
            driver.closeChannel()
        }
    }

    private fun createLabelBitmap(
        productId: String, productName: String,
        parentRollId1: String, parentRollId2: String
    ): Bitmap {
        val width = 696; val height = 270
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        canvas.drawColor(Color.WHITE)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        paint.color = Color.BLACK
        paint.textSize = 48f
        paint.typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        canvas.drawText(productId, 20f, 60f, paint)
        paint.textSize = 32f
        paint.typeface = Typeface.DEFAULT
        canvas.drawText(productName, 20f, 110f, paint)
        paint.strokeWidth = 2f
        canvas.drawLine(20f, 125f, (width - 20).toFloat(), 125f, paint)
        paint.textSize = 26f
        paint.typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        canvas.drawText("Parent Roll:", 20f, 160f, paint)
        paint.typeface = Typeface.DEFAULT
        paint.textSize = 28f
        val parentText = if (parentRollId2.isNotEmpty()) "$parentRollId1 / $parentRollId2" else parentRollId1
        canvas.drawText(parentText, 20f, 200f, paint)
        paint.textSize = 22f
        val date = java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.getDefault()).format(java.util.Date())
        canvas.drawText(date, 20f, 240f, paint)
        return bitmap
    }
}
