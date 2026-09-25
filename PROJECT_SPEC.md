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

TEST VISUAL IDENTITY (2026-07-04): when `APP_ENV=test` the app additionally
renders (a) a light-red Material theme and (b) a red corner `TEST` ribbon on
EVERY screen (Flutter Banner widget via `MaterialApp.builder` in
`lib/main.dart`), and (c) the qa flavor carries a TEST-badged launcher icon
(`android/app/src/qa/res/mipmap-*`, generated red-band overlays of the prod
icon — flavor-scoped, prod builds cannot pick them up). All are driven ONLY
by the existing dart-define / flavor; committed defaults render prod blue.

BRAND COLOUR RULE (v1.0.68 fix): screens must NEVER hardcode the brand blue
`Color(0xFF1a73e8)` — use `kBrandColor` from `lib/brand.dart` (compile-time
const: prod -> #1a73e8 blue, APP_ENV=test -> #B91C1C red, AA-checked). The
original theme-seed-only approach didn't recolour screens because all
AppBars/buttons hardcoded the blue literal (55 sites, all migrated).
Semantic status tints (`Colors.blue.shadeX` chips in history/sales) are NOT
brand chrome and stay unchanged in both environments.

## Cloud Run
- Prod project: project-f05aa3b5-e37d-4c19-a03
- Test project: compleat-ims-test (separate, mirrored data; used by Patrol E2E)
- Region: northamerica-northeast2 (not northeast1)
- Service name: compleat-inventory-api (same in both projects)

## Test Build / Release channels (Joe's release model, 2026-07-04)
Test is the DEVELOPMENT instance and runs AHEAD of live. Live only gets a
release as a deliberate promotion act.

- Job `build-test-apk` (qa flavor) runs on EVERY push to `main` (and on
  dispatch) → `app-test-release.apk` → published as a GitHub PRE-RELEASE
  tagged `test-vX.Y.Z`. Built with `--dart-define=API_BASE=<test_url>` and
  `--dart-define=APP_ENV=test`.
- Job `build` (prod flavor) is `workflow_dispatch` ONLY → normal release
  tagged `vX.Y.Z` with `--latest`. A push to main can NEVER publish to
  live users; Joe triggers this manually when promoting.

Auto-update channels (`lib/services/update_service.dart`):
- prod app → `/releases/latest` (GitHub never returns pre-releases there)
  + rejects `test-v*` tags belt-and-braces.
- test app (`APP_ENV=test`) → release list, newest `test-v*` tag only.
  "Newest" = HIGHEST version among `test-v*` pre-releases, NOT list order
  (GitHub list order isn't guaranteed newest-first across re-publishes).
So each app self-updates from its own channel only; after the first manual
install of the test APK, it updates itself like the live app does.

_isNewer SUFFIX FIX (v1.0.69+70, commit 3168bc4): the qa flavor's
`versionNameSuffix "-test"` made the installed version read `X.Y.Z-test`,
which crashed `_isNewer`'s int parse → the test app never saw updates
(silent false negative). `update_service.dart` now strips a `-suffix`
before comparing and guards every part with `int.tryParse` (malformed → 0).
Keep both behaviours if you ever touch the version-compare logic.

VERIFIED end-to-end 2026-07-05: Joe's TC22 self-updated 1.0.69 → 1.0.70
from the test channel (prompt → download → install).

DEFERRED (Joe, 2026-07-05): separate version numbering for test vs live
channels — both build from the same pubspec `version:` line today; test
simply runs ahead. Revisit if promotion versioning gets confusing.

How to identify the test APK on a device: TEST-badged launcher icon,
light-red theme, red corner `TEST` ribbon on every screen, plus the amber
`TEST ENVIRONMENT` strip on Home.

Side-by-side install IS supported (May 2026): the qa flavor uses
`applicationIdSuffix ".test"` so test installs alongside prod with its own
data and icon.

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

### Receive Parent Roll Screen — shipment batch flow (Joe's rulings 2026-09-25, v1.0.73; no-read skip v1.0.74)
A shipment is many rolls of one variety: fill the shared info once, scan roll after roll into
an on-screen LIST, then press ONE Submit — the same pattern as Roll Production. Rolls are NOT
saved as they are scanned; nothing reaches the server until Submit.

1. SHIPMENT DETAILS (top section; set once):
   - Vendor — dropdown from /masters/vendors, required. LOCKS once the first roll is in the list.
   - PO Number — free text, OPTIONAL. Locks with Vendor.
   - Material Type / Basis Weight / Width (in) — dropdowns from the dedicated masters
     endpoints, required. EDITABLE mid-shipment: rolls ADDED after a change carry the new
     values (each roll in the list stores its own copy).
   - "New shipment" (app bar) discards the unsubmitted list (confirm when rolls are in it)
     and unlocks Vendor + PO.
2. ROLLS section:
   - Counter tile ABOVE the Roll ID field: "N rolls in this shipment — not yet submitted".
     Tapping it expands INLINE (no popup) to the list of roll IDs with a visible Collapse
     control. Tapping a roll expands its details — Length, Weight, Notes and the header
     values it carries — all EDITABLE, plus "Remove from shipment". Purely local.
   - Entry fields (no per-roll button): Roll ID → Length (ft) → Weight (lbs) → Notes.
     Roll ID REQUIRED (scan or type; uppercase; duplicate check against the list first, then
     the server, on Enter/blur; a duplicate keeps focus on the field).
     Focus flow: Roll ID Enter → duplicate check → Length → Enter → Weight → Enter → the roll
     is ADDED TO THE LIST (haptic pulse + green flash + counter ticks) → cursor back to
     Roll ID. Enter on an EMPTY field skips it (scan → Enter → Enter adds a roll with no
     length/weight). Notes: tap in, type, Enter completes the roll.
   - NO-READ = SKIP (Joe's ruling 2026-09-25, option 1, v1.0.74): pulling the scan TRIGGER with
     nothing to decode behaves exactly like Enter on the focused entry field (Roll ID with a
     value → duplicate check → Length; Length → Weight; Weight / Notes → the roll is ADDED). An
     EMPTY Roll ID is the one exception (nothing to skip to — ignored). Mechanism: DataWedge
     keystroke output sends NOTHING on a no-read, so the app registers for DataWedge's
     SCANNER_STATUS notifications (Notification API, DataWedge ≥ 6.4; native
     `ScannerStatusPlugin.kt` → EventChannel `com.compleat/scanner_status` →
     `services/scanner_status_service.dart`). `NoReadDetector`: SCANNING (beam on) followed by
     WAITING/IDLE (beam off) with no text arriving in any entry field during the beam or within
     a 400 ms grace window = one no-read; a real decode (keystrokes) never counts. GRACEFUL
     DEGRADATION: on a device without DataWedge nothing fires and the keyboard Enter stays the
     skip — no crash, no delay. TEST builds only: a small grey "Scanner diag" line under the
     Rolls card shows listening state, no-read count, last status and last hardware KEY event
     (MainActivity forwards every KeyEvent — diagnostics only, the skip is never driven by key
     events); it tells the TC22 walkthrough whether the trigger key is visible to the app.
     Unit tests: `test/no_read_detector_test.dart`. Other screens can opt in the same way.
   - No "scan → Enter → Enter → Enter" hint text; no "Receive Roll" / "Clear roll" buttons.
3. SUBMIT (one plain button at the bottom, no icon; disabled until the list has a roll):
   POST /rolls/receive/batch {vendor_id, po_number, submit_id, rolls:[{roll_id, material_type,
   basis_weight, width, length, weight, notes}]} — ALL-OR-NOTHING on the server (validate every
   roll first; one Firestore WriteBatch; 409/400 with per-roll `results` when anything is
   wrong, nothing saved). Success → banner "✔ N rolls received", the screen clears, and a
   "Submitted — N rolls received" result lists the rolls with a per-roll Undo
   (DELETE /rolls/{id}/receive; the SERVER enforces own receive / in stock / no children /
   within 4 h). Failure → banner "Nothing saved: …", the refused rolls are marked in the list
   (which opens), the list is kept for correction. `submit_id` makes a retry after a lost
   response idempotent (server answers `replayed: true`).
4. DRAFT PERSISTENCE: the whole unsubmitted shipment (header, lock, list, half-typed roll,
   submit_id) is written to SharedPreferences (`receive_shipment_draft_v1`, debounced) on
   every change and restored when the screen or the app comes back, with an amber
   "Unsubmitted shipment restored — N rolls" banner. Cleared ONLY by Submit or New shipment.
   This screen no longer uses the in-memory FormStateCache.

Rules:
- All dropdowns fetch fresh from API on every screen load; no hardcoded lists anywhere
- The old per-roll POST /rolls/receive stays on the server for older installed apps; this
  screen never calls it
- Errors render via ApiService.readableDetail (a 422 list prints as sentences, never raw)

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

Dropdowns must always open BELOW their field, never above. Before opening,
scroll the field to the upper portion of viewport so room exists below.
Combine with 40% maxHeight cap.

Implementation: every DropdownSearch wires `onBeforePopupOpening` to
`FieldFocus.ensureRoomForDropdown(...)`, which scrolls the field to ~20% from
the top before the popup is positioned. `FieldFocus.advance` applies the same
0.2 alignment for auto-advanced fields.

## BUILD & COMMIT RULES
Mobile builds happen via GitHub Actions, NEVER locally.
- Claude Code's workflow: edit code → commit to git → push to main
- GitHub Actions auto-triggers the build on push
- NEVER run `flutter build` locally — disk space is constrained on this Cloud Shell environment
- compleat-mobile IS a git repo — always commit and push there
- compleat-inventory (backend + web) is now ALSO a git repo. Same commit-and-push discipline as compleat-mobile. After any backend or web change, commit and push to the compleat-inventory repo before reporting work complete.
- compleat-inventory still deploys from disk via gcloud / firebase commands — git tracking is separate from deployment
- After every code change in compleat-mobile, the commit MUST be made and pushed in the same session — never leave uncommitted changes

## Change Log
2026-05-21 — BUILD & COMMIT RULES: compleat-inventory is now a git repo; same commit-and-push discipline applies
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
2026-09-21 — Initial Stock Entry — Child: Length and Weight REMOVED (Joe's ruling;
             v1.0.71+72). Form is now Parent Roll ID(s) [Two-Parent toggle],
             Product, Quantity, Status, Notes. Same removal in the Annual Count
             inline unknown-child form (it reuses /stocktake/child). Why: a
             child's length always equals its product master's length (a
             different length gets its own product ID, by policy), weight has no
             source, and nothing in the system reads either field. The backend
             silently ignores length/weight still sent by an older app. History
             stock-entry child detail: Length falls back to the product master;
             Weight shows only on older records that carry one. Parent initial
             entry UNCHANGED (still Length + Weight). Nothing else on the Stock
             Take screen touched.

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
