# Label Print Specification — Standing Invariants
Last updated: 2026-04-02

## Purpose
This file defines all standing requirements for label printing in BrotherPrinterPlugin.kt.
Every Claude Code instruction touching BrotherPrinterPlugin.kt must begin by reading this file
and must complete the pre-commit checklist before committing.
If any instruction contradicts this spec, STOP and report it — do not resolve it yourself.

## Bitmap Dimensions
- createLabelBitmap() must return a bitmap exactly PRINT_WIDTH_PX (1296) wide
- Height is flexible (current target: 1181px portrait before rotation)
- After 90° rotation the returned bitmap will be 1181px wide × 1296px tall — bitmapToRasterRows then scales it to 1296px wide proportionally
- bitmapToRasterRows() scales using proportional formula: new height = (src.height * PRINT_WIDTH_PX / src.width)

## Orientation
- Final printed label must be LANDSCAPE
- Achieved by: drawing portrait bitmap (1296×1181) then rotating 90° at end of createLabelBitmap()

## Content — 3 Proportional Zones
Zones run top-to-bottom in the portrait bitmap:
- Zone 1 (22% of height): Product ID — bold, dynamic font, centered horizontally
- Zone 2 (52% of height): Barcode — full available width, centered horizontally
- Zone 3 (26% of height): Parent Roll ID — centered horizontally

## Barcode
- Format: CODE_128
- Encodes: productId — NEVER parentRollId1 or parentRollId2
- ZXing EncodeHintType.MARGIN = 0
- Generated via generateBarcode(productId, width, height)

## Font Sizing — Dynamic Only
- fitTextToWidth() must be used for ALL text — never hardcode font sizes
- Starts at maxSize, steps down 2f until text fits availW
- Minimum floor: 40f

## Text Alignment — Center Only
- All text centered using: x = (width - paint.measureText(text)) / 2f

## Barcode Alignment — Center Only
- Barcode centered using: x = (width - barcodeBitmap.width) / 2f

## Parent Roll IDs — Both Cases Required
- parentRollId2 empty → single line, parentRollId1 only, large font
- parentRollId2 non-empty → try single line "ID1  /  ID2" first
  - fitTextToWidth >= 60f: draw as one line
  - fitTextToWidth < 60f: draw as two lines, same font size

## Functions — Protection Levels
Must NEVER be modified:
- buildRasterJob()
- printLabelRawTcp()
- byteListOf()

May ONLY be modified for proportional scaling fix:
- bitmapToRasterRows()

May be modified when instruction explicitly requests it:
- createLabelBitmap()
- generateBarcode()
- fitTextToWidth()

## Pre-Commit Checklist
State the result of every item before committing:
- [ ] createLabelBitmap() returned bitmap width after rotation = 1181px (state actual)
- [ ] bitmapToRasterRows will scale 1181px wide bitmap to 1296px proportionally (confirm)
- [ ] Final printed orientation will be landscape (confirm)
- [ ] Barcode encodes productId (confirm)
- [ ] fitTextToWidth() used for all text, no hardcoded sizes (confirm)
- [ ] Single parent ID case works (confirm)
- [ ] Two parent ID case works (confirm)
- [ ] All text center aligned (confirm)
- [ ] Barcode center aligned (confirm)
- [ ] buildRasterJob() unchanged (confirm)
- [ ] printLabelRawTcp() unchanged (confirm)

## Change Log
2026-04-02 — LABEL_SPEC.md created
2026-04-02 — Landscape rotation added to createLabelBitmap()
2026-04-02 — bitmapToRasterRows() proportional scaling fix applied
