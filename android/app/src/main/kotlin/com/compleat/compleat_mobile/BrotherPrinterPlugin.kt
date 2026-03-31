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
    // Printable width = 696 pixels at 300 dpi
    // Bytes per raster line = ceil(696 / 8) = 87
    private val PRINT_WIDTH_PX = 696
    private val BYTES_PER_LINE = 87   // 696 / 8 = 87 exactly
    private val PRINTER_PORT = 9100

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "printLabel" -> {
                val productId    = call.argument<String>("productId")    ?: ""
                val productName  = call.argument<String>("productName")  ?: ""
                val parentRollId1 = call.argument<String>("parentRollId1") ?: ""
                val parentRollId2 = call.argument<String>("parentRollId2") ?: ""
                val quantity     = call.argument<Int>("quantity")        ?: 1
                val printerIp    = call.argument<String>("printerIp")    ?: ""
                if (printerIp.isEmpty()) {
                    result.error("NO_IP", "Printer IP not configured", null)
                    return
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
                            val socket = Socket()
                            socket.connect(InetSocketAddress(printerIp, PRINTER_PORT), 2000)
                            socket.close()
                            "READY"
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
                                val socket = Socket()
                                socket.connect(InetSocketAddress(printerIp, PRINTER_PORT), 2000)
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
                // SDK is only used here for discovery — not on the print path,
                // so it cannot crash the app during normal use.
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

    // -------------------------------------------------------------------------
    // Raw TCP raster printing — no Brother SDK involvement whatsoever.
    // Implements the QL-1100/1110NWB raster command protocol documented in:
    // "Software Developer's Manual – Raster Command Reference QL-1100/1110NWB/1115NWB"
    // -------------------------------------------------------------------------

    private suspend fun printLabelRawTcp(
        productId: String,
        productName: String,
        parentRollId1: String,
        parentRollId2: String,
        quantity: Int,
        printerIp: String
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
            // Give the printer time to process before we close the connection
            Thread.sleep(500)
        } finally {
            socket.close()
        }
        true
    }

    /**
     * Builds the complete binary raster command sequence for the QL-1110NWB.
     *
     * Sequence (per the official Brother raster spec for QL-1100/1110NWB):
     *   1. Invalidate      — 200 × 0x00  (flush any junk in printer buffer)
     *   2. Initialize      — ESC @       (1B 40)
     *   3. Raster mode     — ESC i a 01  (1B 69 61 01)
     *   4. Auto-status off — ESC i ! 00  (1B 69 21 00)
     *   5. Print info      — ESC i z … (media type, width, page count)
     *   6. Various mode    — ESC i M 40  (auto-cut on)
     *   7. Cut each N      — ESC i A 01  (cut after every label)
     *   8. Expanded mode   — ESC i K 08  (cut-at-end flag)
     *   9. Margin amount   — ESC i d 00 00 (zero feed margin)
     *  10. No compression  — M 00        (4D 00)
     *  11. Raster lines    — 'g' 00 NN <87 bytes> per row, or 'Z' for blank row
     *  12. Print + feed    — 0x1A
     *
     * For multiple copies the control block + raster block is repeated,
     * with the final copy using 0x1A (print+feed) and intermediate copies
     * using 0x0C (FF — print without feeding).
     */
    private fun buildRasterJob(bitmap: Bitmap, copies: Int): ByteArray {
        val rasterRows = bitmapToRasterRows(bitmap)
        val labelHeight = rasterRows.size   // number of dot rows

        val job = mutableListOf<Byte>()

        // ── 1. Invalidate (200 null bytes) ────────────────────────────────────
        repeat(200) { job.add(0x00) }

        // ── 2. Initialize ─────────────────────────────────────────────────────
        job.addAll(listOf(0x1B, 0x40))

        // ── 3. Switch to raster mode ──────────────────────────────────────────
        job.addAll(listOf(0x1B, 0x69, 0x61, 0x01))

        // ── 4. Disable auto status notification ───────────────────────────────
        job.addAll(listOf(0x1B, 0x69, 0x21, 0x00))

        // ── 5. Print information command (ESC i z) ────────────────────────────
        //   Byte layout (13 bytes total after ESC i z):
        //     [0]  flags    : 0x8E  (valid bits: media type, width, length, quality)
        //     [1]  media    : 0x0A  (continuous roll)
        //     [2]  width    : 62    (mm)
        //     [3]  length   : 0     (0 = continuous)
        //     [4–5] raster lines low/high (label height in dots, little-endian)
        //     [6–7] page number (0x00 0x00 = page 1)
        //     [8–9] reserved  0x00 0x00
        //     [10] color    : 0x00 (black only, no red)
        //     [11] ink      : 0x00
        //     [12] quality  : 0x00 (standard)
        val heightLow  = (labelHeight and 0xFF).toByte()
        val heightHigh = ((labelHeight shr 8) and 0xFF).toByte()
        job.addAll(listOf(0x1B, 0x69, 0x7A))
        job.addAll(listOf(
            0x8E.toByte(), // flags
            0x0A,          // media type: continuous roll
            62,            // width mm
            0x00,          // length mm (0 = continuous)
            heightLow,
            heightHigh,
            0x00, 0x00,    // page number
            0x00, 0x00,    // reserved
            0x00,          // color
            0x00,          // ink
            0x00           // quality
        ))

        // ── 6. Various mode — enable auto-cut ─────────────────────────────────
        job.addAll(listOf(0x1B, 0x69, 0x4D, 0x40))

        // ── 7. Cut each label (every 1 label) ─────────────────────────────────
        job.addAll(listOf(0x1B, 0x69, 0x41, 0x01))

        // ── 8. Expanded mode — cut at end ─────────────────────────────────────
        job.addAll(listOf(0x1B, 0x69, 0x4B, 0x08))

        // ── 9. Margin / feed amount — 0 dots ──────────────────────────────────
        job.addAll(listOf(0x1B, 0x69, 0x64, 0x00, 0x00))

        // ── 10. Compression mode — none ───────────────────────────────────────
        job.addAll(listOf(0x4D, 0x00))

        // ── 11 + 12. Raster data + print command, repeated for each copy ──────
        for (copy in 1..copies) {
            for (row in rasterRows) {
                val isBlank = row.all { it == 0.toByte() }
                if (isBlank) {
                    // 'Z' command — zero raster (blank line, 1 byte)
                    job.add(0x5A)
                } else {
                    // 'g' command — raster graphics transfer
                    //   0x67  0x00  <length byte>  <length bytes of data>
                    job.add(0x67)
                    job.add(0x00)
                    job.add(BYTES_PER_LINE.toByte())
                    row.forEach { job.add(it) }
                }
            }
            // Print command: 0x1A = print + feed (last / only copy)
            //                0x0C = FF print without extra feed (intermediate copies)
            if (copy < copies) {
                job.add(0x0C)  // FF — print, advance to next label, continue
            } else {
                job.add(0x1A)  // Control-Z — print + feed + cut final label
            }
        }

        return job.map { it.toByte() }.toByteArray()
    }

    /**
     * Converts an Android [Bitmap] to a list of 1-bit packed raster rows.
     *
     * Rules:
     *   - Bitmap is scaled to exactly [PRINT_WIDTH_PX] pixels wide if needed.
     *   - Each row is [BYTES_PER_LINE] bytes (87 bytes for 696 px).
     *   - A pixel is BLACK (1-bit = 1) when its luminance is < 128.
     *   - Bit order: MSB first within each byte (leftmost pixel = bit 7 of byte 0).
     */
    private fun bitmapToRasterRows(src: Bitmap): List<ByteArray> {
        // Ensure exact print width
        val bmp = if (src.width != PRINT_WIDTH_PX) {
            val scaled = Bitmap.createScaledBitmap(src, PRINT_WIDTH_PX, src.height, true)
            scaled
        } else {
            src
        }

        val rows = mutableListOf<ByteArray>()
        val pixels = IntArray(PRINT_WIDTH_PX)

        for (y in 0 until bmp.height) {
            bmp.getPixels(pixels, 0, PRINT_WIDTH_PX, 0, y, PRINT_WIDTH_PX, 1)
            val rowBytes = ByteArray(BYTES_PER_LINE) { 0x00 }

            for (x in 0 until PRINT_WIDTH_PX) {
                val argb = pixels[x]
                val r = (argb shr 16) and 0xFF
                val g = (argb shr 8)  and 0xFF
                val b = argb           and 0xFF
                // Standard luminance formula
                val luminance = (0.299 * r + 0.587 * g + 0.114 * b).toInt()

                if (luminance < 128) {
                    // Dark pixel → print dot (bit = 1)
                    val byteIndex = x / 8
                    val bitIndex  = 7 - (x % 8)   // MSB first
                    rowBytes[byteIndex] = (rowBytes[byteIndex].toInt() or (1 shl bitIndex)).toByte()
                }
                // Light pixel → leave as 0 (no dot)
            }
            rows.add(rowBytes)
        }

        if (bmp !== src) bmp.recycle()
        return rows
    }

    // -------------------------------------------------------------------------
    // Label bitmap — unchanged from original
    // -------------------------------------------------------------------------

    private fun createLabelBitmap(
        productId: String,
        productName: String,
        parentRollId1: String,
        parentRollId2: String
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
