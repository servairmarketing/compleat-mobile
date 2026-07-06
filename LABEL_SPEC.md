# Label Print Specification — Standing Invariants
Last updated: 2026-05-06 (Parent-only label format added for Stock Take)

## Purpose
This file defines all standing requirements for label printing in BrotherPrinterPlugin.kt.
Every Claude Code instruction touching BrotherPrinterPlugin.kt must begin by reading this file
and must complete the pre-commit checklist before committing.
If any instruction contradicts this spec, STOP and report it — do not resolve it yourself.

## Bitmap Dimensions
- createLabelBitmap() draws into a 1109 × 696 landscape canvas BEFORE the final 90° rotation
- After postRotate(90°) the returned bitmap is 696 × 1109 — width matches PRINT_WIDTH_PX exactly
- bitmapToRasterRows() therefore performs zero scaling on this bitmap
- PRINT_WIDTH_PX = 696 (W62 tape image width on the 1296-pin print head)

## Orientation
- Final printed label must be LANDSCAPE
- Achieved by: drawing the 1109 × 696 design canvas then rotating 90° at end of createLabelBitmap()

## Content — 3 Vertical Zones (pre-rotation canvas, 1109 × 696)
20px bleed reserved on all four sides → usable area 1069 × 656 (x: 20..1089, y: 20..676).
Zone heights are proportional to usable height (not fixed pixel ranges).

| Zone | Name                  | Share of usable height | Notes                                                                 |
|------|-----------------------|------------------------|-----------------------------------------------------------------------|
| A    | Product ID text       | top 40% (≈ 262 px)     | Bold, CENTERED, SINGLE LINE. Dynamic font size: largest that fits the usable horizontal width AND does not exceed the zone height (zone height is the cap). Edge-to-edge horizontally for long IDs; zone-height tall for short IDs — whichever constraint binds first wins. fitTextToBox helper. |
| B    | Composite barcode     | middle 40% (≈ 262 px)  | CODE_128, CENTERED, NOT rotated (bars run vertically — barcode reads same direction as text). Encodes "ProductID-ParentID". |
| C    | Parent ID text        | bottom 20% (≈ 131 px)  | Plain weight, CENTERED, single line, vertically centered in zone, fitTextToWidth. |

## Barcodes
- Format: CODE_128 (single composite barcode per label)
- Encodes the composite string `"ProductID-ParentID"` — one label = one product + one parent
- ZXing EncodeHintType.MARGIN = 0
- Generated via generateBarcode(data, width, height) sized to the zone, drawn UNROTATED
- Centered within Zone B:
  bx = bcZoneX + (bcZoneW - barcodeBitmap.width) / 2f
  by = bcZoneY + (zoneBcH - barcodeBitmap.height) / 2f

## Font Sizing — Dynamic Only
- All text must use a dynamic-fit helper — never hardcode font sizes
- fitTextToWidth(): width-only cap. Starts at maxSize, steps down 2f until text
  fits availW. Minimum floor: 40f. Used for Zone C (Parent ID).
- fitTextToBox(): width AND height cap. Measures at a reference size, then scales
  by min(maxWidth/measuredW, maxHeight/measuredH) so whichever constraint binds
  first wins. Used for Zone A (Product ID).

## Text Alignment
- Zone A (Product ID text): CENTERED horizontally and vertically within the zone;
  single line
- Zone C (Parent ID text): CENTERED horizontally within the zone; vertically centered

## Two-Parent Rule — Loop in Dart, N Labels Per Parent
- Each label carries exactly ONE parent ID encoded inside the composite barcode
- When two-parent mode is on in production_screen.dart, the Dart side prints N labels
  for parent 1, then N labels for parent 2 → 2N labels total. Each physical child roll
  receives BOTH labels (operator sticks both on the roll).
- Single-parent mode: N labels, all encoding "ProductID-Parent1ID"
- createLabelBitmap() takes a single parentId; there is no parentRollId2 parameter

## Parent-Only Label
A second label format coexists with the composite label. Used by Stock Take
when operator-entered parent IDs need physical labels for warehouse use
(no product information is encoded — just the parent ID).

- Pre-rotation canvas: 1109 × 696 (same as composite — 696 width matches
  PRINT_WIDTH_PX so bitmapToRasterRows performs zero scaling)
- 20px bleed all sides → usable area 1069 × 656
- 2-zone vertical layout, 50/50 split of usable height:

| Zone | Name             | Share of usable height | Notes                                                                 |
|------|------------------|------------------------|-----------------------------------------------------------------------|
| P    | Parent ID text   | top 50% (≈ 328 px)     | Bold, CENTERED, SINGLE LINE. Same fitTextToBox helper as composite Zone A — width-cap or zone-height-cap, whichever binds first wins. |
| B    | Parent barcode   | bottom 50% (≈ 328 px)  | CODE_128, CENTERED, NOT rotated, encodes parentId only (no composite). Same generateBarcode helper as composite label. |

After drawing, postRotate(90°) → 696 × 1109 → rasterize via existing
bitmapToRasterRows. PRINT_WIDTH_PX = 696 unchanged.

Function: `createParentOnlyLabelBitmap(parentId: String): Bitmap`
TCP path: `printParentOnlyLabelRawTcp(parentId, quantity, printerIp)` —
mirrors `printLabelRawTcp` but calls `createParentOnlyLabelBitmap` instead
of `createLabelBitmap`. Both label formats coexist; the composite
`createLabelBitmap` and existing print loop are UNCHANGED.

Method channel: `printParentOnlyLabel` with args `parentId`, `quantity`,
`printerIp`. Dart accessor: `PrinterService.printParentOnlyLabel(...)`.

## Functions — Protection Levels
Must NEVER be modified:
- buildRasterJob()
- printLabelRawTcp()
- byteListOf()
- bitmapToRasterRows()

May be modified when instruction explicitly requests it:
- createLabelBitmap()
- createParentOnlyLabelBitmap()
- generateBarcode()
- fitTextToWidth()
- fitTextToBox()

## Pre-Commit Checklist
State the result of every item before committing:
- [ ] createLabelBitmap() pre-rotation bitmap = 1109 × 696 (state actual)
- [ ] createLabelBitmap() returned bitmap (post-rotation) = 696 × 1109 (state actual)
- [ ] bitmapToRasterRows scales 0% (src.width == PRINT_WIDTH_PX) (confirm)
- [ ] Final printed orientation will be landscape (confirm)
- [ ] Composite barcode encodes "ProductID-ParentID" (confirm)
- [ ] Composite barcode is NOT rotated (drawn upright, reads same direction as text) (confirm)
- [ ] Zone A (Product ID text) and Zone C (Parent ID text) CENTERED (confirm)
- [ ] All text uses a dynamic-fit helper (fitTextToWidth or fitTextToBox), no hardcoded sizes (confirm)
- [ ] Two-parent case handled by Dart loop printing N labels per parent (2N total) (confirm)
- [ ] Composite barcode CENTERED within Zone B (confirm)
- [ ] buildRasterJob() unchanged (confirm)
- [ ] printLabelRawTcp() unchanged except for the single createLabelBitmap() call line whose
      arguments had to follow the createLabelBitmap signature change (confirm)
- [ ] bitmapToRasterRows() unchanged (confirm)

## Change Log
2026-04-02 — LABEL_SPEC.md created
2026-04-02 — Landscape rotation added to createLabelBitmap()
2026-04-02 — bitmapToRasterRows() proportional scaling fix applied
2026-05-01 — Dual-barcode redesign: 4 fixed-coordinate zones, parent ID barcode added,
             two-parent mode now loops in Dart instead of combining on one label,
             pre-rotation canvas changed from 1181 × 696 to 1109 × 696
2026-05-01 — Zone 2 (Product ID text) grown 580×450 → 580×526 (y=20..546); Zone 4
             (Parent ID text) tightened 850×186 → 850×110 (y=566..676). Product ID
             now renders on 2 lines split at the first "-" with each line independently
             fit; falls back to single-line render if no "-" present. Zones 1 and 3
             unchanged. Pre-rotation canvas 1109 × 696 unchanged.
2026-05-01 — Label tweaks v1.0.24+25: Zone 4 restored 580×110 → 850×186 (y=490..676)
             so Parent ID font reverts to v1.0.22+23 size (max ≈ 158f); Zone 2 reduced
             580×526 → 580×450 (y=20..470) to make room. Zone 2 lines now LEFT-aligned
             and stacked tightly from top (10px top pad, 8px inter-line gap) instead of
             centered in halves. Zone 4 text now LEFT-aligned (was centered). Zones 1
             and 3 unchanged. Pre-rotation canvas 1109 × 696 unchanged.
2026-05-06 — Composite-barcode redesign (v1.0.35+36): dual side-by-side barcodes
             collapsed into a single composite CODE_128 encoding "ProductID-ParentID".
             Layout switches from 4 fixed-coordinate side-by-side zones to 3 vertical
             zones proportional to usable height: top 40% Product ID text (centered,
             2-line split at first "-"), middle 40% composite barcode (centered, NOT
             rotated), bottom 20% Parent ID text (centered, single line). Two-parent
             mode now prints N labels per parent (2N total) instead of 1 per parent.
             createLabelBitmap() signature changed from
             (productId, productName, parentRollId1, parentRollId2) to
             (productId, parentId) — full body rewrite as an explicit exception to
             rule #5 (every coordinate, zone count, signature, and barcode encoding
             changed; targeted line edit not feasible). Pre-rotation canvas 1109 × 696
             unchanged.
2026-05-06 — Product ID renders single-line, dynamic font size with width-cap and
             height-cap (cap = zone height) — v1.0.37+38. Removes the 2-line split
             at first "-"; the full product_id is now a single centered line.
             Font is computed by new fitTextToBox helper as the largest size such
             that text width fits prodZoneW AND text height does not exceed
             zoneProdH; whichever constraint binds first wins. Zones B and C and
             zone proportions (40/40/20) unchanged. Operator feedback: long IDs
             should fill the width edge-to-edge, short IDs should fill the zone
             height. Pre-rotation canvas 1109 × 696 unchanged. createLabelBitmap()
             signature unchanged.
2026-05-06 — Parent-only label format added for Stock Take (v1.0.41+42). New
             function createParentOnlyLabelBitmap(parentId) draws a single-purpose
             label: top 50% Parent ID text (bold, centered, fitTextToBox), bottom
             50% CODE_128 barcode encoding parentId only (centered, NOT rotated).
             Pre-rotation canvas 1109 × 696, postRotate(90°) → 696 × 1109. New
             method channel "printParentOnlyLabel" routes to a new
             printParentOnlyLabelRawTcp that mirrors printLabelRawTcp but invokes
             createParentOnlyLabelBitmap. The composite label format (3-zone
             40/40/20 layout) and createLabelBitmap signature/body are
             UNCHANGED — both formats coexist. buildRasterJob, byteListOf and
             bitmapToRasterRows unchanged. PRINT_WIDTH_PX unchanged.
