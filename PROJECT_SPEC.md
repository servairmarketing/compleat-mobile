# Com-Pleat IMS — Master Project Specification
Last updated: 2026-04-02

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
- Printer: Brother QL-1110NWBc — raw TCP raster port 9100 — PRINT_WIDTH_PX = 1296 (hardware constant, never change)

## API Base URL
https://compleat-inventory-api-793462624071.northamerica-northeast2.run.app

## Known API Endpoints
- POST /auth/login
- GET /masters/vendors → response key: records[]
- GET /masters/products → response key: records[]
- POST /rolls/receive

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
- Bitmap returned by createLabelBitmap() must be exactly PRINT_WIDTH_PX (1296) wide
- Barcode encodes productId — never parentRollId
- Functions that must never be modified: bitmapToRasterRows(), buildRasterJob(), printLabelRawTcp(), byteListOf()

## Rules for Every Instruction
1. Read PROJECT_SPEC.md and LABEL_SPEC.md before touching any file
2. If the instruction contradicts either spec, report it — do not resolve it
3. State explicitly what changed and what was preserved
4. For any change to BrotherPrinterPlugin.kt, complete the LABEL_SPEC.md checklist before committing
5. Never rewrite entire functions — make only the specific lines requested
6. Build is via GitHub Actions — never suggest running flutter build locally

## Change Log
2026-04-02 — PROJECT_SPEC.md created
2026-04-02 — LABEL_SPEC.md created
2026-04-02 — Blank test button removed from printer settings
2026-04-01 — Label: 3-zone proportional layout, dynamic fonts, centered text
2026-04-01 — Brother SDK replaced with raw TCP raster implementation
