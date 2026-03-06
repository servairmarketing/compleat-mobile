package com.compleat.compleat_mobile

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import com.brother.ptouch.sdk.LabelInfo
import com.brother.ptouch.sdk.NetPrinter
import com.brother.ptouch.sdk.Printer
import com.brother.ptouch.sdk.PrinterInfo
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
                    result.error("NO_IP", "Printer IP not configured. Go to Settings to set it.", null)
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
            "discoverPrinters" -> {
                scope.launch {
                    try {
                        val printers = discoverPrinters()
                        withContext(Dispatchers.Main) { result.success(printers) }
                    } catch (e: Exception) {
                        withContext(Dispatchers.Main) { result.success(emptyList<String>()) }
                    }
                }
            }
            "testConnection" -> {
                val printerIp = call.argument<String>("printerIp") ?: ""
                if (printerIp.isEmpty()) {
                    result.error("NO_IP", "Printer IP not configured", null)
                    return
                }
                scope.launch {
                    try {
                        val reachable = withContext(Dispatchers.IO) {
                            java.net.InetAddress.getByName(printerIp).isReachable(3000)
                        }
                        withContext(Dispatchers.Main) { result.success(reachable) }
                    } catch (e: Exception) {
                        withContext(Dispatchers.Main) { result.success(false) }
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
        val printer = Printer()
        val printerInfo = PrinterInfo()
        printerInfo.printerModel = PrinterInfo.Model.QL_1110NWB
        printerInfo.port = PrinterInfo.Port.NET
        printerInfo.ipAddress = printerIp
        printerInfo.labelNameIndex = LabelInfo.QL700.W62.ordinal
        printerInfo.isAutoCut = true
        printerInfo.isCutAtEnd = true
        printerInfo.numberOfCopies = quantity
        printerInfo.orientation = PrinterInfo.Orientation.LANDSCAPE
        printer.setPrinterInfo(printerInfo)
        val bitmap = createLabelBitmap(productId, productName, parentRollId1, parentRollId2)
        val status = printer.printImage(bitmap)
        status.errorCode == PrinterInfo.ErrorCode.ERROR_NONE
    }

    private fun createLabelBitmap(productId: String, productName: String, parentRollId1: String, parentRollId2: String): Bitmap {
        val width = 696; val height = 270
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        canvas.drawColor(Color.WHITE)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        paint.color = Color.BLACK
        paint.textSize = 48f; paint.typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        canvas.drawText(productId, 20f, 60f, paint)
        paint.textSize = 32f; paint.typeface = Typeface.DEFAULT
        canvas.drawText(productName, 20f, 110f, paint)
        paint.strokeWidth = 2f
        canvas.drawLine(20f, 125f, (width - 20).toFloat(), 125f, paint)
        paint.textSize = 26f; paint.typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        canvas.drawText("Parent Roll:", 20f, 160f, paint)
        paint.typeface = Typeface.DEFAULT; paint.textSize = 28f
        val parentText = if (parentRollId2.isNotEmpty()) "$parentRollId1 / $parentRollId2" else parentRollId1
        canvas.drawText(parentText, 20f, 200f, paint)
        paint.textSize = 22f
        val date = java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.getDefault()).format(java.util.Date())
        canvas.drawText(date, 20f, 240f, paint)
        return bitmap
    }

    private suspend fun discoverPrinters(): List<String> = withContext(Dispatchers.IO) {
        val printer = Printer()
        val netPrinters: Array<NetPrinter> = printer.getNetPrinters(PrinterInfo.Model.QL_1110NWB.name)
        netPrinters.map { "${it.ipAddress} (${it.modelName})" }
    }
}
