# Com-Pleat IMS — Master Project Specification
Last updated: 2026-05-06 (Phase E — Stock Take screen + parent-only label)

## Purpose
This file defines all standing requirements for the Com-Pleat IMS mobile app.
Every Claude Code instruction must begin by reading this file.
If any new instruction contradicts anything in this file, STOP and report
the contradiction in your summary. Do not resolve it yourself.

## Technology Stack
- Flutter mobile app — target device: Zebra TC22 (Android)
- Backend: FastAPI on Google Cloud Run
- Database: Firestore
- Repo: github.com/servairmarketing/compleat-mobile
- Build: GitHub Actions ONLY — never run flutter build in Cloud Shell
- Printer: Brother QL-1110NWBc — raw TCP raster port 9100 — print head is 1296 pins (162 bytes) wide; PRINT_WIDTH_PX = 696 (W62 tape image width — bytes 7..93 of each raster line)

## API Base URL
The base URL is selected at compile time via `--dart-define=API_BASE=<url>`.
Default = prod, so a plain release build keeps pointing at prod.

- prod (default): https://compleat-inventory-api-793462624071.northamerica-northeast2.run.app
- test:           https://compleat-inventory-api-477414435007.northamerica-northeast2.run.app

A second compile-time flag `--dart-define=APP_ENV=<label>` (default `prod`)
sets `appEnvironment` in `lib/services/api_service.dart`. When the value is
not `prod`, the home screen renders an amber `<ENV> ENVIRONMENT` banner under
the top bar so testers always know which backend the APK is hitting.

## Cloud Run
- Prod project: project-f05aa3b5-e37d-4c19-a03
- Test project: compleat-ims-test (separate, mirrored data; used by Patrol E2E)
- Region: northamerica-northeast2 (not northeast1)
- Service name: compleat-inventory-api (same in both projects)

## Test Build / E2E APK
GitHub Actions builds two APKs on every push to `main`:

- Job `build` → `app-release.apk` → published as a GitHub Release (prod).
- Job `build-test-apk` → `app-test-release.apk` → uploaded as a workflow
  artifact only (no GitHub Release). This is the APK to install on E2E
  hardware. It is built with `--dart-define=API_BASE=<test_url>` and
  `--dart-define=APP_ENV=test`.

How to identify the test APK on a device:
- Open the app and look at the top of the Home screen — a thin amber
  `TEST ENVIRONMENT` strip appears below the blue header. Prod builds
  show no such strip.

Side-by-side install with prod APK is NOT supported yet — both builds use
`applicationId = com.compleat.compleat_mobile`, so installing the test APK
replaces the prod APK and vice versa. Adding `applicationIdSuffix = ".test"`
via Android build flavors is the right fix when this becomes a need.

## Known API Endpoints
- POST /auth/login
- GET /masters/vendors → response key: records[]
- GET /masters/products → response key: records[]
- GET /masters/widths → response key: values[]
- GET /masters/material_types → response key: values[]
- GET /masters/basis_weights → response key: values[]
- POST /rolls/receive
- POST /stocktake/parent → creates parent roll doc (source='stocktake')
- POST /stocktake/child → creates child roll doc (source='stocktake'); does NOT auto-create parents
- POST /stocktake/scan → records a scan in stock_take collection
- GET /stocktake/list → admin: all; non-admin: scoped to scanned_by
- GET /stocktake/lookup_child?product_id=X&parent_roll_ids=Y[,Z] → order-insensitive child lookup

## Mobile App Screens

### Receive Parent Roll Screen
Fields (in this order):
1. Roll ID — text input, optional, hint "Auto-generated if empty"
2. Vendor — dropdown from /masters/vendors, required
3. PO Number — free text, optional
4. Material Type — dropdown of unique material_type values from /masters/products, required
5. Basis Weight — dropdown of unique basis_weight values from /masters/products, required
6. Width (in) — dropdown of unique width values from /masters/products, required
7. Length (ft) — number input, required
8. Weight (lbs) — number input, required
9. Notes — multiline text, optional

Rules:
- All 3 dropdowns fetch fresh from API on every screen load
- No hardcoded lists anywhere

### Printer Settings Screen
- Printer IP input
- Test connection button
- NO blank test button (removed — do not add back)

## Label Printing
See LABEL_SPEC.md for full detail.
Summary:
- Orientation: LANDSCAPE
- createLabelBitmap() draws into a 1109 × 696 pre-rotation canvas, then postRotate(90°) → 696 × 1109; the 696 width matches PRINT_WIDTH_PX so bitmapToRasterRows() does zero scaling
- Single composite CODE_128 barcode per label, drawn UNROTATED (bars vertical, reads same direction as text). Encodes "ProductID-ParentID" — one product + one parent per label
- 3-zone vertical layout (proportional to usable height after 20px bleed): top 40% Product ID text (single line, centered, dynamic font sized by both width-cap and zone-height-cap), middle 40% composite barcode (centered), bottom 20% Parent ID text (centered)
- Two-parent mode: Dart loops the print call N times for parent 1, then N times for parent 2 → 2N labels total. Each child roll receives both labels.
- Functions that must never be modified: buildRasterJob(), printLabelRawTcp(), byteListOf(), bitmapToRasterRows()

## Production Screen Validation
- Label Printing tab: product dropdown is filtered by parent roll — only shows products
  matching parent's material_type, basis_weight (string compare), and width <= parent.width
  (parsed via double.tryParse). Dropdown is empty until parent roll 1 is validated.
  The post-selection validator at the onChanged handler is preserved as a backstop.
- Label Printing tab: when selected product width < parent.width, an AlertDialog
  ("Confirm narrower child roll") asks the operator to confirm before the selection
  commits. Cancel clears the selection.
- Roll Production tab: scan handler enforces material/basis_weight/width-not-greater
  rejection. When scanned product width < parent.width, the same confirmation dialog is
  shown (worded for scan context). Cancel skips counter increment and item add.
- Two-parent mode: the Parent Roll 2 cross-check rejects w2 < w1, so parent 1 is always
  the narrower-or-equal parent — width comparisons against parent 1 are the binding case.
- Defensive: confirmation is skipped if either width is 0 / unparseable.

## Rules for Every Instruction
1. Read PROJECT_SPEC.md and LABEL_SPEC.md before touching any file
2. If the instruction contradicts either spec, report it — do not resolve it
3. State explicitly what changed and what was preserved
4. For any change to BrotherPrinterPlugin.kt, complete the LABEL_SPEC.md checklist before committing
5. Never rewrite entire functions — make only the specific lines requested
6. Build is via GitHub Actions — never suggest running flutter build locally

## DROPDOWN UX RULES
All DropdownSearch / dropdown widgets must have
`maxHeight: MediaQuery.of(context).size.height * 0.4` to prevent covering
previously-entered fields when the keyboard is up. This applies to every
screen with a multi-field form.

## BUILD & COMMIT RULES
Mobile builds happen via GitHub Actions, NEVER locally.
- Claude Code's workflow: edit code → commit to git → push to main
- GitHub Actions auto-triggers the build on push
- NEVER run `flutter build` locally — disk space is constrained on this Cloud Shell environment
- compleat-mobile IS a git repo — always commit and push there
- compleat-inventory (backend + web) is NOT a git repo — deploy from disk via gcloud / firebase commands
- After every code change in compleat-mobile, the commit MUST be made and pushed in the same session — never leave uncommitted changes

## Change Log
2026-04-02 — PROJECT_SPEC.md created
2026-04-02 — LABEL_SPEC.md created
2026-04-02 — Blank test button removed from printer settings
2026-04-01 — Label: 3-zone proportional layout, dynamic fonts, centered text
2026-04-01 — Brother SDK replaced with raw TCP raster implementation
2026-05-01 — Dual-barcode label redesign (DK-1202): 4 fixed-coordinate zones with separate
             parent-ID and product-ID CODE_128 barcodes, both rotated 90° CCW; two-parent
             mode now loops in Dart instead of combining IDs on one label; pre-rotation
             canvas changed from 1181 × 696 to 1109 × 696. createLabelBitmap() was rewritten
             in full as an explicit exception to rule #5 (every coordinate, zone count, and
             two-parent text path changed — a targeted line edit was not feasible).
2026-05-01 — PRINT_WIDTH_PX constants in this spec corrected from 1296 to 696. The change
             happened in code on 2026-04-02 (commit 3387328) but was never reflected here.
2026-05-06 — Composite-barcode label redesign (v1.0.35+36): dual side-by-side CODE_128
             barcodes replaced with a single composite barcode encoding
             "ProductID-ParentID", drawn UNROTATED. Layout switches from 4 fixed-
             coordinate side-by-side zones to 3 vertical zones proportional to usable
             height (40% / 40% / 20% — Product text / composite barcode / Parent text,
             all centered). createLabelBitmap() signature changed from
             (productId, productName, parentRollId1, parentRollId2) to
             (productId, parentId); the createLabelBitmap call inside printLabelRawTcp
             updated to match (a single-line consequential edit — printLabelRawTcp
             logic itself is otherwise unchanged). Two-parent mode now prints N labels
             per parent (2N total) instead of 1 per parent. createLabelBitmap() was
             rewritten in full as an explicit exception to rule #5 (every zone,
             coordinate, signature, and barcode encoding changed — targeted line edit
             was not feasible). Pre-rotation canvas 1109 × 696 unchanged.
2026-05-06 — Label Product ID layout refined per operator feedback. Single line,
             dynamic font size (v1.0.37+38). Zone A no longer splits at the first
             "-"; the full product_id renders as one centered line. Font size is
             the largest that fits prodZoneW horizontally AND does not exceed
             zoneProdH vertically (zone height is the cap). New fitTextToBox helper
             added to BrotherPrinterPlugin.kt; fitTextToWidth retained for Zone C.
             Zone proportions 40/40/20, Zone B (composite barcode) and Zone C
             (Parent ID) unchanged. createLabelBitmap signature unchanged.
2026-05-06 — Phase E: Stock Take mobile screen + parent-only label format
             (v1.0.41+42). New screen lib/screens/stocktake_screen.dart with
             three modes (Initial Stock Entry, Annual Stock Take, Print Labels)
             each having Parent / Child sub-modes. Initial Stock Entry writes
             to the rolls collection (source='stocktake'); Annual Stock Take
             writes to a separate stock_take collection (no inventory change)
             via a new POST /stocktake/scan; missing rolls open inline forms
             that create the doc + record the scan. Print Labels mode prints
             without any inventory action. Home screen gets a Stock Take card
             gated by role admin/warehouse or modules.contains('stocktake').
             A new parent-only label format (single Parent ID barcode + text,
             50/50 vertical split, no composite) added to BrotherPrinterPlugin
             via createParentOnlyLabelBitmap + printParentOnlyLabelRawTcp + the
             "printParentOnlyLabel" method channel; PrinterService gains a new
             printParentOnlyLabel() Dart accessor. Composite label format and
             existing print loop UNCHANGED — both formats coexist. Backend
             gains 5 endpoints under /stocktake (parent, child, scan, list,
             lookup_child). Production / Sales / Conversion / Receive / Login /
             Printer Settings / History screens NOT modified.

## 9. Direct Cloud Shell Changes Log
Changes made directly in Cloud Shell (bypassing Claude Code) must be
documented here so the spec stays accurate.

### 2026-04-02 — Bitmap dimension fix
File: BrotherPrinterPlugin.kt
Change: val width = 1181, val height = 696 (was width=696, height=1181)
Reason: After postRotate(90°), returned bitmap is 696×1181 — matching
PRINT_WIDTH_PX=696 exactly so bitmapToRasterRows does zero scaling and
printer receives exactly 1181 raster lines matching 100mm label length.
Commit: 3387328

### 2026-04-02 — Version bump to 1.0.2+3
File: pubspec.yaml
Change: version: 1.0.2+3
Reason: Version tracking so installed APK can be verified on device.
Commit: f2bf193

### 2026-04-02 — APK artifact path fix
File: .github/workflows/build.yml
Change: app-release.apk → app-debug.apk
Reason: Debug build produces app-debug.apk not app-release.apk.
Commit: 17d17d2

### 2026-04-07 — Label zone proportions and barcode padding
File: BrotherPrinterPlugin.kt
Change: zoneProductH 20%→25%, zoneBarcodeH 55%→45%, barcodePad 8→40
Reason: More height for product ID zone; tighter barcode with more surrounding whitespace.
Commit: a4c337e

### 2026-04-07 — Version bump to 1.0.3+4
File: pubspec.yaml
Change: version: 1.0.3+4
Reason: Version tracking for APK verification on device.
Commit: 4193704
