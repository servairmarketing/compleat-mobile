package com.compleat.compleat_mobile

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import com.brother.ptouch.sdk.LabelInfo
import com.brother.ptouch.sdk.NetPrinter
import com.brother.ptouch.sdk.Printer
import com.brother.ptouch.sdk.PrinterInfo
import com.brother.ptouch.sdk.PrinterStatus
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class BrotherPrinterPlugin(private val scope: CoroutineScope) : MethodChannel.MethodCallHandler {

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "printLabel" -> {
                val productId = call.argument<String>("productId") ?: ""
                val productName = call.argument<String>("productName") ?: ""
                val parentRollId1 = call.argument<String>("parentRollId1") ?: ""
                val parentRollId2 = call.argument<String>("parentRollId2") ?: ""
                val quantity = call.argument<Int>("quantity") ?: 1
                val printerIp = call.argument<String>("printerIp") ?: ""

                scope.launch {
                    val success = printLabel(productId, productName, parentRollId1, parentRollId2, quantity, printerIp)
                    withContext(Dispatchers.Main) {
                        if (success) result.success(true)
                        else result.error("PRINT_ERROR", "Failed to print label", null)
                    }
                }
            }
            "discoverPrinters" -> {
                scope.launch {
                    val printers = discoverPrinters()
                    withContext(Dispatchers.Main) {
                        result.success(printers)
                    }
                }
            }
            else -> result.notImplemented()
        }
    }

    private suspend fun printLabel(
        productId: String,
        productName: String,
        parentRollId1: String,
        parentRollId2: String,
        quantity: Int,
        printerIp: String
    ): Boolean = withContext(Dispatchers.IO) {
        try {
            val printer = Printer()
            val printerInfo = PrinterInfo()
            printerInfo.printerModel = PrinterInfo.Model.QL_1110NWBc
            printerInfo.port = PrinterInfo.Port.NET
            printerInfo.ipAddress = printerIp
            printerInfo.labelNameIndex = LabelInfo.QL700.W62.ordinal
            printerInfo.isAutoCut = true
            printerInfo.isCutAtEnd = true
            printerInfo.numberOfCopies = quantity
            printerInfo.orientation = PrinterInfo.Orientation.LANDSCAPE
            printer.setPrinterInfo(printerInfo)

            // Build label bitmap
            val bitmap = createLabelBitmap(productId, productName, parentRollId1, parentRollId2)
            val status: PrinterStatus = printer.printImage(bitmap)
            status.errorCode == PrinterInfo.ErrorCode.ERROR_NONE
        } catch (e: Exception) {
            false
        }
    }

    private fun createLabelBitmap(
        productId: String,
        productName: String,
        parentRollId1: String,
        parentRollId2: String
    ): Bitmap {
        // Label size for 62mm roll, landscape: ~696 x 270 px at 300dpi
        val width = 696
        val height = 270
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        canvas.drawColor(Color.WHITE)

        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        paint.color = Color.BLACK

        // Product ID - large bold
        paint.textSize = 48f
        paint.typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        canvas.drawText(productId, 20f, 60f, paint)

        // Product Name
        paint.textSize = 32f
        paint.typeface = Typeface.DEFAULT
        canvas.drawText(productName, 20f, 110f, paint)

        // Divider line
        paint.strokeWidth = 2f
        canvas.drawLine(20f, 125f, (width - 20).toFloat(), 125f, paint)

        // Parent Roll label
        paint.textSize = 26f
        paint.typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        canvas.drawText("Parent Roll:", 20f, 160f, paint)

        paint.typeface = Typeface.DEFAULT
        paint.textSize = 28f
        val parentText = if (parentRollId2.isNotEmpty()) "$parentRollId1 / $parentRollId2" else parentRollId1
        canvas.drawText(parentText, 20f, 200f, paint)

        // Date
        paint.textSize = 22f
        val date = java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.getDefault()).format(java.util.Date())
        canvas.drawText(date, 20f, 240f, paint)

        return bitmap
    }

    private suspend fun discoverPrinters(): List<String> = withContext(Dispatchers.IO) {
        try {
            val printer = Printer()
            val netPrinters: Array<NetPrinter> = printer.getNetPrinters(PrinterInfo.Model.QL_1110NWBc.name)
            netPrinters.map { "${it.ipAddress} (${it.modelName})" }
        } catch (e: Exception) {
            emptyList()
        }
    }
}
