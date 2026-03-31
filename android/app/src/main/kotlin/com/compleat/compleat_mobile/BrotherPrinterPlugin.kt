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
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.OutputStream
import java.net.InetSocketAddress
import java.net.Socket

class BrotherPrinterPlugin(
    private val context: Context,
    private val scope: CoroutineScope
) : MethodChannel.MethodCallHandler {

    // QL-1110NWB with W62 (62mm) continuous roll:
    // Printable width = 696 pixels at 300 dpi = 87 bytes per raster line
    private val PRINT_WIDTH_PX = 696
    private val BYTES_PER_LINE = 87  // 696 / 8 = 87 exactly
    private val PRINTER_PORT = 9100

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "printLabel" -> {
                val productId     = call.argument<String>("productId")     ?: ""
                val productName   = call.argument<String>("productName")   ?: ""
                val parentRollId1 = call.argument<String>("parentRollId1") ?: ""
                val parentRollId2 = call.argument<String>("parentRollId2") ?: ""
                val quantity      = call.argument<Int>("quantity")         ?: 1
                val printerIp     = call.argument<String>("printerIp")     ?: ""
                if (printerIp.isEmpty()) {
                    result.error("NO_IP", "Printer IP not configured", null); return
                }
                scope.launch {
                    try {
                        val success = printLabelRawTcp(
                            productId, productName, parentRollId1, parentRollId2, quantity, printerIp
                        )
                        withContext(Dispatchers.Main) { result.success(success) }
                    } catch (e: Exception) {
                        withContext(Dispatchers.Main) {
                            result.error("PRINT_ERROR", e.message ?: "Unknown error", null)
                        }
                    }
                }
            }
            "getPrinterStatus" -> {
                val printerIp = call.argument<String>("printerIp") ?: ""
                if (printerIp.isEmpty()) { result.success("OFFLINE"); return }
                scope.launch {
                    val statusStr = withContext(Dispatchers.IO) {
                        try {
                            val s = Socket()
                            s.connect(InetSocketAddress(printerIp, PRINTER_PORT), 2000)
                            s.close(); "READY"
                        } catch (e: Exception) { "OFFLINE" }
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
                                val s = Socket()
                                s.connect(InetSocketAddress(printerIp, PRINTER_PORT), 2000)
                                s.close(); true
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
                                val r = PrinterDriverGenerator.openChannel(channel)
                                if (r.error.code == OpenChannelError.ErrorCode.NoError) {
                                    r.driver.closeChannel()
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

    // -------------------------------------------------------------------------
    // Raw TCP raster printing — zero Brother SDK involvement on the print path.
    // Protocol: Brother QL-1100/1110NWB/1115NWB Raster Command Reference v1.00
    // -------------------------------------------------------------------------

    private suspend fun printLabelRawTcp(
        productId: String, productName: String,
        parentRollId1: String, parentRollId2: String,
        quantity: Int, printerIp: String
    ): Boolean = withContext(Dispatchers.IO) {
        val bitmap = createLabelBitmap(productId, productName, parentRollId1, parentRollId2)
        val rasterJob = buildRasterJob(bitmap, quantity)
        bitmap.recycle()

        val socket = Socket()
        socket.connect(InetSocketAddress(printerIp, PRINTER_PORT), 5000)
        socket.soTimeout = 15000
        try {
            val out: OutputStream = socket.getOutputStream()
            out.write(rasterJob)
            out.flush()
            Thread.sleep(500)
        } finally {
            socket.close()
        }
        true
    }

    /**
     * Builds the complete binary raster job per the official QL-1100/1110NWB spec.
     *
     * FIXES applied vs previous version:
     *  1. Invalidate = 350 null bytes (spec says 350, not 200)
     *  2. ESC i z sends exactly 10 bytes of parameters (not 13)
     *  3. No 'Z' zero-raster command — only valid in TIFF mode.
     *     Every row is sent as a full 'g' raster line, even blank ones.
     *
     * ESC i z parameter layout (10 bytes):
     *   [0] flags     0x8E  — marks media type + width + length + quality valid
     *   [1] media     0x0A  — continuous roll (not die-cut)
     *   [2] width mm  62    — W62 label
     *   [3] length mm 0     — 0 = continuous (no fixed length)
     *   [4] raster lines low byte
     *   [5] raster lines high byte
     *   [6] page number (1-based)
     *   [7] page count total
     *   [8] color     0x00
     *   [9] reserved  0x00
     */
    private fun buildRasterJob(bitmap: Bitmap, copies: Int): ByteArray {
        val rasterRows  = bitmapToRasterRows(bitmap)
        val labelHeight = rasterRows.size
        val heightLow   = (labelHeight and 0xFF).toByte()
        val heightHigh  = ((labelHeight shr 8) and 0xFF).toByte()

        val job = mutableListOf<Byte>()

        // 1. Invalidate — 350 null bytes (spec explicitly says 350)
        repeat(350) { job.add(0x00) }

        // 2. Initialize — ESC @
        job.addAll(byteListOf(0x1B, 0x40))

        // 3. Raster mode — ESC i a 01
        job.addAll(byteListOf(0x1B, 0x69, 0x61, 0x01))

        // 4. Auto-status off — ESC i ! 00
        job.addAll(byteListOf(0x1B, 0x69, 0x21, 0x00))

        // 5. Print information — ESC i z + 10 parameter bytes
        job.addAll(byteListOf(0x1B, 0x69, 0x7A))
        job.addAll(byteListOf(
            0x8E,       // flags: media type, width, length, quality all valid
            0x0A,       // media type: continuous roll
            62,         // width: 62 mm
            0x00,       // length: 0 = continuous
            heightLow,  // raster line count LSB
            heightHigh, // raster line count MSB
            0x01,       // page number (1)
            0x01,       // total pages (1)
            0x00,       // color
            0x00        // reserved
        ))

        // 6. Various mode — auto-cut on — ESC i M 40
        job.addAll(byteListOf(0x1B, 0x69, 0x4D, 0x40))

        // 7. Cut each 1 label — ESC i A 01
        job.addAll(byteListOf(0x1B, 0x69, 0x41, 0x01))

        // 8. Expanded mode — cut at end — ESC i K 08
        job.addAll(byteListOf(0x1B, 0x69, 0x4B, 0x08))

        // 9. Margin = 0 — ESC i d 00 00
        job.addAll(byteListOf(0x1B, 0x69, 0x64, 0x00, 0x00))

        // 10. No compression — M 00
        job.addAll(byteListOf(0x4D, 0x00))

        // 11 + 12. Raster lines + print command, once per copy
        for (copy in 1..copies) {
            for (row in rasterRows) {
                // Always send full 'g' raster line — 'Z' is only valid in TIFF mode
                job.add(0x67)                      // 'g' command
                job.add(0x00)                      // fixed 0x00
                job.add(BYTES_PER_LINE.toByte())   // data length = 87
                row.forEach { job.add(it) }        // 87 bytes of pixel data
            }
            // 0x0C = FF print (intermediate copies), 0x1A = print+feed (last copy)
            job.add(if (copy < copies) 0x0C else 0x1A)
        }

        return job.map { it.toByte() }.toByteArray()
    }

    /**
     * Converts Android Bitmap to 1-bit packed raster rows (MSB first, black=1).
     * Scales to PRINT_WIDTH_PX wide if needed.
     */
    private fun bitmapToRasterRows(src: Bitmap): List<ByteArray> {
        val bmp = if (src.width != PRINT_WIDTH_PX)
            Bitmap.createScaledBitmap(src, PRINT_WIDTH_PX, src.height, true)
        else src

        val rows   = mutableListOf<ByteArray>()
        val pixels = IntArray(PRINT_WIDTH_PX)

        for (y in 0 until bmp.height) {
            bmp.getPixels(pixels, 0, PRINT_WIDTH_PX, 0, y, PRINT_WIDTH_PX, 1)
            val rowBytes = ByteArray(BYTES_PER_LINE)
            for (x in 0 until PRINT_WIDTH_PX) {
                val argb = pixels[x]
                val r = (argb shr 16) and 0xFF
                val g = (argb shr 8)  and 0xFF
                val b = argb           and 0xFF
                val lum = (0.299 * r + 0.587 * g + 0.114 * b).toInt()
                if (lum < 128) {
                    // Dark pixel → print dot (bit = 1, MSB first)
                    rowBytes[x / 8] = (rowBytes[x / 8].toInt() or (1 shl (7 - x % 8))).toByte()
                }
            }
            rows.add(rowBytes)
        }

        if (bmp !== src) bmp.recycle()
        return rows
    }

    /** Helper to create a List<Byte> from Int varargs (avoids toByte() noise inline) */
    private fun byteListOf(vararg ints: Int): List<Byte> = ints.map { it.toByte() }

    // -------------------------------------------------------------------------
    // Label bitmap — unchanged
    // -------------------------------------------------------------------------

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
