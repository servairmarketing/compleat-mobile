package com.compleat.compleat_mobile

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Typeface
import android.util.Log
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

    // QL-1110NWB has a 1296-pin (162-byte) print head.
    // W62 tape sits 56 pins (7 bytes) from the RIGHT edge of the head.
    // Byte 0 MSB = rightmost pin → data is right-edge-first.
    // W62 raster line layout:
    //   7 bytes right margin (56 pins) + 87 bytes image (696 pins, rightmost pixel first) + 68 bytes left unused (544 pins) = 162 bytes
    private val PRINT_WIDTH_PX     = 696
    private val RIGHT_MARGIN_BYTES = 7    // offset_r(12) + additional_offset_r(44) = 56 pins = 7 bytes
    private val IMAGE_BYTES        = 87   // 696 / 8 = 87 exactly
    private val BYTES_PER_LINE     = 162  // 1296 / 8 = 162 (full head width)
    private val PRINTER_PORT      = 9100

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
                    val detail = try {
                        printLabelRawTcp(
                            productId, productName, parentRollId1, parentRollId2, quantity, printerIp
                        )
                    } catch (e: Exception) {
                        "ERROR: ${e.message ?: "Unknown error"}"
                    }
                    withContext(Dispatchers.Main) { result.success(detail) }
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
    ): String = withContext(Dispatchers.IO) {
        val log = StringBuilder()
        val ts = java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss", java.util.Locale.getDefault())
            .format(java.util.Date())
        log.appendLine("=== BrotherPrint debug $ts ===")

        val bitmap = createLabelBitmap(productId, productName, parentRollId1, parentRollId2)
        val rasterJob = buildRasterJob(bitmap, quantity)
        bitmap.recycle()
        log.appendLine("jobBytes=${rasterJob.size}")
        Log.d("BrotherPrint", "Job built: ${rasterJob.size} bytes")

        var socketConnected = false
        var dataSent = false
        var errorMsg: String? = null

        try {
            val socket = Socket()
            socket.connect(InetSocketAddress(printerIp, PRINTER_PORT), 5000)
            socketConnected = true
            Log.d("BrotherPrint", "Socket connected to $printerIp:$PRINTER_PORT")
            log.appendLine("socketConnected=true  ip=$printerIp:$PRINTER_PORT")
            socket.soTimeout = 15000
            try {
                val out: OutputStream = socket.getOutputStream()

                Log.d("BrotherPrint", "Writing job: ${rasterJob.size} bytes total")
                out.write(rasterJob)
                out.flush()
                dataSent = true
                Log.d("BrotherPrint", "Data flushed")
                log.appendLine("dataSent=true")
                Thread.sleep(2000)
                Log.d("BrotherPrint", "Drain sleep done")
                log.appendLine("drainSleepDone=true")
            } finally {
                socket.close()
                Log.d("BrotherPrint", "Socket closed")
                log.appendLine("socketClosed=true")
            }
        } catch (e: Exception) {
            errorMsg = e.message ?: "Unknown error"
            Log.e("BrotherPrint", "Exception: $errorMsg")
            log.appendLine("error=$errorMsg")
        }

        val detail = if (errorMsg == null) {
            "OK: jobBytes=${rasterJob.size}, socketConnected=$socketConnected, dataSent=$dataSent"
        } else {
            "ERROR: $errorMsg | jobBytes=${rasterJob.size}, socketConnected=$socketConnected, dataSent=$dataSent"
        }
        log.appendLine("result=$detail")

        // Write debug info to /sdcard/brother_print_debug.txt
        try {
            java.io.File("/sdcard/brother_print_debug.txt").writeText(log.toString())
        } catch (e: Exception) {
            Log.w("BrotherPrint", "Could not write debug file: ${e.message}")
        }

        detail
    }

    /**
     * Builds the complete binary raster job per the official QL-1100/1110NWB spec.
     *
     * ESC i z parameter layout (10 bytes):
     *   [0] flags     0x8E  — marks media type + width + length + quality valid
     *   [1] media     0x0B  — die-cut label
     *   [2] width mm  62    — DK-1202 label width
     *   [3] length mm 0x64  — 100mm (DK-1202 die-cut length)
     *   [4-7] raster line count as 4-byte little-endian uint32
     *   [8] color     0x00
     *   [9] reserved  0x00
     */
    private fun buildRasterJob(bitmap: Bitmap, copies: Int): ByteArray {
        val rasterRows  = bitmapToRasterRows(bitmap)
        val labelHeight = rasterRows.size
        val h0 = labelHeight          and 0xFF
        val h1 = (labelHeight shr  8) and 0xFF
        val h2 = (labelHeight shr 16) and 0xFF
        val h3 = (labelHeight shr 24) and 0xFF

        val job = mutableListOf<Byte>()

        // 1. Invalidate — 200 null bytes (QL-1110NWB default per brother_ql library / models.py)
        repeat(200) { job.add(0x00) }

        // 2. Initialize — ESC @
        job.addAll(byteListOf(0x1B, 0x40))

        // 3. Raster mode — ESC i a 01
        job.addAll(byteListOf(0x1B, 0x69, 0x61, 0x01))

        // 4. Auto-status off — ESC i ! 00
        job.addAll(byteListOf(0x1B, 0x69, 0x21, 0x00))

        // 5. Print information — ESC i z + 10 parameter bytes
        job.addAll(byteListOf(0x1B, 0x69, 0x7A))
        job.addAll(byteListOf(
            0x8E,  // flags: media type, width, length, quality all valid
            0x0B,  // media type: die-cut label (DK-1202)
            62,    // width: 62 mm
            0x64,  // length: 100 mm (DK-1202)
            h0,    // n5: raster line count byte 0 (LSB)
            h1,    // n6: raster line count byte 1
            h2,    // n7: raster line count byte 2
            h3,    // n8: raster line count byte 3 (MSB)
            0x00,  // color
            0x00   // reserved
        ))

        // 6. Various mode — auto-cut on — ESC i M 40
        job.addAll(byteListOf(0x1B, 0x69, 0x4D, 0x40))

        // 7. Cut each 1 label — ESC i A 01
        job.addAll(byteListOf(0x1B, 0x69, 0x41, 0x01))

        // 8. Expanded mode — cut at end — ESC i K 08
        job.addAll(byteListOf(0x1B, 0x69, 0x4B, 0x08))

        // 9. Margin = 0 dots — ESC i d 00 00 (die-cut label, no feed margin needed)
        job.addAll(byteListOf(0x1B, 0x69, 0x64, 0x00, 0x00))

        // 10. No compression — M 00
        job.addAll(byteListOf(0x4D, 0x00))

        // 11 + 12. Raster lines + print command, once per copy
        for (copy in 1..copies) {
            for (row in rasterRows) {
                // Always send full 'g' raster line — 'Z' is only valid in TIFF mode
                job.add(0x67)                      // 'g' command
                job.add(0x00)                      // fixed 0x00
                job.add(BYTES_PER_LINE.toByte())   // data length = 162 (0xA2)
                row.forEach { job.add(it) }        // 162 bytes of pixel data (with margins)
            }
            // 0x0C = FF print (intermediate copies), 0x1A = print+feed (last copy)
            job.add(if (copy < copies) 0x0C else 0x1A)
        }

        return job.map { it.toByte() }.toByteArray()
    }

    /**
     * Converts Android Bitmap to 1-bit packed raster rows for QL-1110NWB.
     * Each row is 162 bytes. Byte 0 MSB = rightmost pin of the print head.
     * W62 tape occupies bytes 7–93: RIGHT_MARGIN_BYTES(7) + IMAGE_BYTES(87).
     * Pixel x=0 (leftmost image pixel) maps to the LAST bit of byte 93;
     * pixel x=695 (rightmost) maps to the MSB of byte 7 — i.e. the image is
     * horizontally mirrored in the byte stream so it prints correctly.
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
            val rowBytes = ByteArray(BYTES_PER_LINE) // 162 bytes, zero-initialised (margins stay 0x00)
            for (x in 0 until PRINT_WIDTH_PX) {
                val argb = pixels[x]
                val r = (argb shr 16) and 0xFF
                val g = (argb shr 8)  and 0xFF
                val b = argb           and 0xFF
                val lum = (0.299 * r + 0.587 * g + 0.114 * b).toInt()
                if (lum < 128) {
                    // Rightmost image pixel (x=695) → byte 7 MSB; leftmost (x=0) → byte 93 bit 0.
                    // Mirrors the image so it prints left-to-right on the label.
                    val mirrored = PRINT_WIDTH_PX - 1 - x
                    val byteIdx  = RIGHT_MARGIN_BYTES + mirrored / 8
                    val bitPos   = mirrored % 8
                    rowBytes[byteIdx] = (rowBytes[byteIdx].toInt() or (1 shl (7 - bitPos))).toByte()
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
    // Label bitmap — landscape barcode layout
    // -------------------------------------------------------------------------

    private fun createLabelBitmap(
        productId: String,
        productName: String,
        parentRollId1: String,
        parentRollId2: String
    ): Bitmap {
        // Landscape: 1296px wide × 600px tall (fits W62 at 300dpi landscape)
        // The printer prints this landscape — no rotation needed in software
        val width = 1296
        val height = 600
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        canvas.drawColor(Color.WHITE)

        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        paint.color = Color.BLACK

        // ── RIGHT SECTION: Product ID text (large bold) ──
        paint.textSize = 120f
        paint.typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        val pidX = 1050f
        val pidY = 400f
        // Rotate canvas to draw text vertically (reading bottom-to-top)
        canvas.save()
        canvas.rotate(-90f, pidX, pidY)
        canvas.drawText(productId, pidX - 200f, pidY + 40f, paint)
        canvas.restore()

        // ── CENTER SECTION: Barcode of productId (rotated 90° to run vertically) ──
        val barcodeBitmap = generateBarcode(productId, 600, 400)
        if (barcodeBitmap != null) {
            val rotMatrix = Matrix()
            rotMatrix.postRotate(90f)
            val rotatedBarcode = Bitmap.createBitmap(
                barcodeBitmap, 0, 0, barcodeBitmap.width, barcodeBitmap.height, rotMatrix, true
            )
            barcodeBitmap.recycle()
            val barcodeX = (width / 2 - rotatedBarcode.width / 2).toFloat()
            val barcodeY = (height / 2 - rotatedBarcode.height / 2).toFloat()
            canvas.drawBitmap(rotatedBarcode, barcodeX, barcodeY, null)
            rotatedBarcode.recycle()
        }

        // ── LEFT SECTION: Parent Roll ID ──
        paint.textSize = 80f
        paint.typeface = Typeface.create(Typeface.DEFAULT, Typeface.NORMAL)
        val parentText = if (parentRollId2.isNotEmpty()) "$parentRollId1 / $parentRollId2" else parentRollId1
        val parentX = 150f
        val parentY = 400f
        canvas.save()
        canvas.rotate(-90f, parentX, parentY)
        canvas.drawText(parentText, parentX - 150f, parentY + 30f, paint)
        canvas.restore()

        return bitmap
    }

    private fun generateBarcode(data: String, targetWidth: Int, targetHeight: Int): Bitmap? {
        return try {
            val writer = com.google.zxing.MultiFormatWriter()
            val matrix = writer.encode(data, com.google.zxing.BarcodeFormat.CODE_128, targetWidth, targetHeight)
            val barcodeWidth = matrix.width
            val barcodeHeight = matrix.height
            val pixels = IntArray(barcodeWidth * barcodeHeight)
            for (y in 0 until barcodeHeight) {
                for (x in 0 until barcodeWidth) {
                    pixels[y * barcodeWidth + x] = if (matrix[x, y]) Color.BLACK else Color.WHITE
                }
            }
            val bmp = Bitmap.createBitmap(barcodeWidth, barcodeHeight, Bitmap.Config.ARGB_8888)
            bmp.setPixels(pixels, 0, barcodeWidth, 0, 0, barcodeWidth, barcodeHeight)
            bmp
        } catch (e: Exception) {
            null
        }
    }
}
