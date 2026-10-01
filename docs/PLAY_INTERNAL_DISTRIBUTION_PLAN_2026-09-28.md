# Google Play internal distribution for Com-Pleat IMS (compleat-mobile) — PLAN

Written 2026-09-28. **Proposal only — nothing is built.** Joe rules on the
decisions in §0 before any workflow, manifest or Dart change lands.

Why: every sideloaded APK install/update trips Google Play Protect
("harmful app blocked") — 05_SYNC_STATE backlog #25 / Bug #19 already says
this "needs Play Console enrollment or MDM (NOT a code fix)". Joe wants the
scanner app delivered through Google Play privately: no warnings, automatic
updates. Joe is creating the Play developer account (organization, company
Google account). The account will host TWO apps: this one now, and later the
Android side of `compleat-sales` (owned by the iOS/Android chat). §3 plans the
account-level pieces so both apps share them; this plan builds only the
scanner app's track.

Modelled on the compleat-sales TestFlight setup (`compleat-sales/docs/IOS_TESTFLIGHT_SETUP.md`,
`ios/fastlane/Fastfile`): CI signs and uploads, Joe does console clicks from a
numbered list.

Evidence grading (CLAUDE.md truth guardrails): **[V]** = verified in this
session from repo files, `gh` output or a fetched Google page (source
named); **[I]** = inference, reasoning shown; **[U]** = not checked.

---

## 0. Decisions for Joe (rule on each)

| # | Decision | Recommendation |
|---|----------|----------------|
| D1 | Play track | **Internal testing** (§1) |
| D2 | App signing key | **Upload our existing keystore as the Play app-signing key (PEPK)** so Play builds carry today's signature; existing keystore stays the upload key (§2.2) |
| D3 | GitHub-Releases APK path for LIVE | **Keep publishing the `vX.Y.Z` GitHub Release + APK for now as an emergency sideload fallback**; retire after two clean Play releases (§2.4) |
| D4 | In-app "Check for Update" (prod flavor) | **Must stop downloading APKs** (Play policy, §2.5). Replace with "Open Play Store" (one-line `url_launcher` call; already a dependency). Test flavor unchanged. |
| D5 | Device Google account | **One shared company Google account signed into all warehouse Zebras** + Joe's own account on his test device (§1.3) |
| D6 | Privacy policy page | **`public/privacy.html` on LIVE hosting**, needs a §2.18 lint exemption ruling (§4.2) |
| D7 | Service account home | **Create it in `project-f05aa3b5-e37d-4c19-a03`** (LIVE project, Joe is owner) and reuse it for both apps (§3) |

---

## 1. Which Play track

### 1.1 The three options

| | Internal testing | Closed testing | Managed Google Play private app |
|---|---|---|---|
| Who can install | up to **100 testers per app**, by email list **[V]** (support.google.com/googleplay/android-developer/answer/9845334) | email lists or Google Groups, up to 200 lists × 2,000 users **[V]** (same page) | any device enrolled in the company's Android Enterprise (EMM) **[I]** |
| Review wait | none — "available to testers within minutes", "might not be subject to standard Play policy or security reviews" **[V]** (same page) | subject to standard review **[V]** (same page, by contrast with internal) | Play review as for a normal app **[I]** |
| Store-listing / Data safety / privacy-policy prerequisites | Data safety form NOT required while the app is exclusively on internal testing **[V]** (search result summarising answer/10787469: "apps that are exclusively active on this track do not need to complete the Data safety form") | required **[V]** (same) | required **[I]** |
| Device requirement | Play Store present + a Google Account or Google Workspace account signed in; tester opens the opt-in link once **[V]** (answer/9845334) | same | device enrolled under an EMM (work profile or fully managed); no personal account needed **[I]** — Zebra devices would be enrolled via the EMM, a separate project |
| Automatic updates | Play Store auto-update, same as any store app **[I]** | same | same |

### 1.2 Recommendation: **Internal testing** (D1)

Reasoning for ~a handful of warehouse Zebras + Joe's test device:

- It removes the two pains (Play Protect prompt, manual sideload) with the
  least machinery: no review wait, so Joe's LIVE promotion stays a single
  deliberate click that lands on the devices within minutes — the same
  cadence the GitHub-Releases path gives today.
- 100 testers is 20× the fleet.
- No Data safety form or store listing is needed to start **[V]**, so nothing
  blocks the first release on paperwork; §4 prepares the paperwork anyway so a
  later move to closed testing (or production) is a form-fill, not a project.
- Closed testing buys nothing for this fleet and adds a review on every
  release. Managed Google Play is the "right" enterprise answer for a large
  corporate-owned fleet but requires standing up an EMM and enrolling each
  Zebra — out of proportion for five devices; revisit if the fleet grows or if
  Joe does not want Google accounts on the scanners.
- Internal-testing apps are reached only through the opt-in link; they do
  not appear in Play search **[I]**.

### 1.3 What the devices need (D5)

1. Play Store on the device. **[I]** The TC22s trip *Play Protect*, which is a
   Play-services feature, so the devices that show the warning have Google
   Mobile Services and therefore the Play Store. Joe confirms by finding the
   Play Store icon on one Zebra (step §3.J.1). **[U]** for any Zebra that has
   never shown the warning.
2. A Google account signed into the Play Store on each device. Recommendation:
   one shared company account (a Workspace account or a plain Google account,
   e.g. a warehouse mailbox) signed into every warehouse Zebra, added once to
   the tester list; Joe's own account on his test device. One account = one
   tester seat regardless of device count **[I]** (tester lists are email
   addresses, answer/9845334).
3. Each device opens the opt-in link once and taps "Become a tester", then
   installs from the Play Store like any app. Later releases arrive by Play
   auto-update (Wi-Fi by default) or by opening the store listing.

---

## 2. Pipeline changes (compleat-mobile only)

### 2.1 Current state [V] (`.github/workflows/build.yml`, `android/app/build.gradle.kts`, `pubspec.yaml`)

- Job `build` (LIVE): `workflow_dispatch` only → `flutter build apk --release --flavor prod`
  → signed with `compleat-release.jks` from the 4 repo secrets
  `KEYSTORE_BASE64` / `KEYSTORE_PASSWORD` / `KEY_ALIAS` / `KEY_PASSWORD`
  (`gh secret list`: all four dated 2026-04-08) → `gh release create vX.Y.Z`
  with `app-prod-release.apk` → the prod app self-updates from
  `/releases/latest` (`lib/services/update_service.dart`).
- Job `build-test-apk` (TEST): every push to main → `flutter test` → qa flavor
  (`.test` suffix, TEST backend) → GitHub pre-release `test-vX.Y.Z`. **Stays
  as-is** (brief).
- Version: `pubspec.yaml` `version: 1.0.78+79` → versionName 1.0.78,
  versionCode 79. Latest releases: `v1.0.78` (2026-09-28) + `test-v1.0.78`.
- `applicationId = "com.compleat.compleat_mobile"`; launcher name
  `Com-Pleat IMS` (`src/prod/res/values/strings.xml`).
- Manifest (`src/main/AndroidManifest.xml`) declares
  `REQUEST_INSTALL_PACKAGES` (needed only by the APK self-installer) and a
  FileProvider for the downloaded APK.
- Toolchain: Flutter 3.41.3, AGP 8.11.1, Kotlin 2.2.20; `compileSdk`/`targetSdk`
  come from the Flutter Gradle plugin = **36** (FlutterExtension.kt at tag
  3.41.3 via `gh api`: `compileSdkVersion = 36`, `targetSdkVersion = 36`,
  `minSdkVersion = 24`).

### 2.2 Signing: Play App Signing + our keystore (D2)

Facts **[V]** (answer/9842756): new apps are automatically enrolled in Play
App Signing with Google-generated keys; alternatively you may "provide a copy
of your app signing key" with the PEPK tool; the upload key must be an RSA
≥2048-bit key in a `.jks`/`.keystore`.

Android rule **[I, standard platform behaviour]**: an update installs over an
existing app only if it is signed with the same key; otherwise the device
refuses the install until the old app is uninstalled.

| Option | Play app-signing key | Effect on the Zebras (which today run the sideloaded, keystore-signed build) | Effect on the GitHub fallback APK |
|---|---|---|---|
| **A (recommended)** | our `compleat-release.jks` key, uploaded once via PEPK | Play install upgrades **in place**: no uninstall, local drafts/prefs kept | still signed with the same key → can be sideloaded over a Play install and vice versa in an emergency |
| B | Google-generated | every device must **uninstall** the sideloaded app once (loses SharedPreferences: token, saved shipment draft) before installing from Play | different signature → the fallback APK will NOT install over the Play build; fallback would mean uninstall/reinstall |

Either way the **upload key is the existing keystore**, so CI keeps signing
with the same four secrets; nothing changes in Gradle. Option A costs Joe one
PEPK step on his laptop (§3.C) and requires the `.jks` file + its passwords in
hand (they exist as repo secrets since 2026-04-08; the file itself is [U] —
Joe confirms he has it; if not, Option B).

### 2.3 New LIVE job `release-play` (replaces the body of job `build`)

`workflow_dispatch` only (Joe's release model unchanged: push to main never
publishes to LIVE). Steps, in order:

1. checkout / Java 17 / Flutter 3.41.3 / caches / decode keystore — as today.
2. `flutter test --reporter expanded` — parity with the TEST job (today the
   LIVE job does not run the tests; a red test must never reach Play).
3. `flutter build appbundle --release --flavor prod` (same env vars as today)
   → `build/app/outputs/bundle/prodRelease/app-prod-release.aab` **[I,
   Flutter naming convention; confirmed at first run]**.
4. Upload the AAB as a workflow artifact `compleat-mobile-aab` (always — this
   is what Joe downloads for the one-time manual first upload, §3.E).
5. **Upload to Play — gated on the secret existing**, same pattern as the
   compleat-sales `HAS_KEYSTORE` job-level env check:
   ```yaml
   env:
     HAS_PLAY_SA: ${{ secrets.PLAY_SERVICE_ACCOUNT_JSON != '' }}
   ...
   - name: Upload to Google Play (internal testing)
     if: env.HAS_PLAY_SA == 'true'
     uses: r0adkll/upload-google-play@v1   # pin to the newest v1.x tag when built
     with:
       serviceAccountJsonPlainText: ${{ secrets.PLAY_SERVICE_ACCOUNT_JSON }}
       packageName: com.compleat.compleat_mobile
       releaseFiles: build/app/outputs/bundle/prodRelease/app-prod-release.aab
       track: internal
       status: completed
       releaseName: ${{ env.VERSION }}   # X.Y.Z from pubspec, as today
   ```
   Inputs `serviceAccountJsonPlainText` / `packageName` / `releaseFiles` /
   `track` / `status` / `releaseName` are the action's documented inputs
   **[V]** (github.com/r0adkll/upload-google-play README). Until the secret
   exists the step is skipped and the run still produces the AAB artifact, so
   the workflow change can ship BEFORE Joe's console work is done.
   Alternative: fastlane `supply` (`upload_to_play_store`) for symmetry with
   the iOS Fastfile — rejected here because the Android job is Linux with no
   Ruby toolchain today; the action is one step with no new toolchain. Say
   the word and the plan switches.
6. (D3) `flutter build apk --release --flavor prod` + `gh release create
   vX.Y.Z` with the APK — **kept unchanged** for now as the emergency
   sideload path and the audit trail of what shipped. Retire = delete this
   step + the `/releases/latest` client code (D4 removes the client already).
7. Version numbering: Play requires a strictly increasing `versionCode` per
   upload. Proposal: keep `pubspec.yaml` `+N` as the versionCode (today's
   discipline already bumps it every release: 1.0.78+79). A forgotten bump
   fails the upload step with a clear "version code already used" error and
   nothing reaches devices. (The iOS job uses `run_number` instead; not
   proposed here because pubspec is the versioned record for this app.)
8. Secret name (shared convention for both apps, §3): `PLAY_SERVICE_ACCOUNT_JSON`.

### 2.4 The GitHub-Releases APK path (D3)

- LIVE app on Play: no longer reads GitHub (D4). GitHub Release `vX.Y.Z` +
  APK continues to be published by the same run as a fallback / record.
- Retirement path once Joe is satisfied (suggested after two Play releases):
  drop step 6, drop the APK artifact upload, README/PROJECT_SPEC updated.
- TEST channel (`build-test-apk`, `test-v*` pre-releases, qa-flavor
  self-update from GitHub): **unchanged**. The qa flavor keeps
  `REQUEST_INSTALL_PACKAGES` and the download/install code. Play Protect will
  keep prompting on Joe's test device for the test app; that is accepted
  for now. Later option (not proposed now): a second Play app record for
  `com.compleat.compleat_mobile.test` on its own internal track, reusing the
  same service account — then both flavors update via Play.

### 2.5 The in-app "Check for Update" (D4) — a Play policy requirement, not a preference

Play's Device and Network Abuse policy: "An app distributed via Google Play
may not modify, replace, or update itself using any method other than Google
Play's update mechanism" and may not download executable code from a source
other than Google Play **[V]** (WebSearch result quoting
support.google.com/googleplay/android-developer/answer/16559646). The prod
build's GitHub-APK download/`OpenFilex` install is exactly that.

Proposed code change (build phase, prod flavor only — the qa flavor keeps
today's code):

- `update_service.dart`: when `appEnvironment != 'test'`, `checkForUpdate`
  no longer calls GitHub; `home_screen.dart`'s button becomes **"Open Play
  Store"** → `url_launcher` opens
  `https://play.google.com/store/apps/details?id=com.compleat.compleat_mobile`
  (the store page shows "Update" when one is pending). `url_launcher ^6.2.5`
  is already in `pubspec.yaml` **[V]**.
- Manifest split: move `REQUEST_INSTALL_PACKAGES` and the APK FileProvider
  from `src/main/AndroidManifest.xml` into a new
  `src/qa/AndroidManifest.xml` (Gradle merges flavor manifests) so the Play
  build does not declare a self-install permission it no longer uses **[I]**.
- Nice-to-have, later: the `in_app_update` package (Play Core "immediate
  update" dialog inside the app). Not proposed now — the store link is
  policy-compliant with one line.

### 2.6 Delivery order (when Joe rules go)

1. Workflow + Dart + manifest changes in one commit, version bumped
   (e.g. 1.0.79+80). Push to main → TEST channel builds as usual.
2. Joe dispatches the LIVE job once with no Play secret → gets the AAB
   artifact (§3.E needs it). No LIVE release happens from this run unless
   Joe wants the GitHub Release too (it will publish `v1.0.79` — acceptable
   since it is the same build; say if not).
3. Joe finishes §3 (manual first upload, service account, secret).
4. Joe dispatches the LIVE job again → Play internal track updated
   automatically → devices update.

---

## 3. Account-level plan (shared by both apps) + Joe's numbered console steps

Design for two apps:

| Piece | Scanner app (this brief) | Sales app (later, other lane) |
|---|---|---|
| Play app record | "Com-Pleat IMS", package `com.compleat.compleat_mobile` [V] | "Compleat Sales", package `com.compleat.compleat_sales` [V] (`compleat-sales/android/app/build.gradle.kts`) |
| Play App Signing | Option A/B per D2 | its own decision (that repo has NO Android keystore secrets yet [V]: `gh secret list` shows only the four iOS ones) |
| CI identity | ONE Google Cloud service account `play-publisher@project-f05aa3b5-e37d-4c19-a03.iam.gserviceaccount.com`, invited into the Play Console once, granted per-app | same SA, granted on the second app when its record exists |
| GitHub secret | `PLAY_SERVICE_ACCOUNT_JSON` in `servairmarketing/compleat-mobile` | same NAME in `servairmarketing/compleat-sales` (per-repo copy; org-level secrets not relied on — availability to a private repo on the current plan is [U]) |
| Track | internal testing, tester list "Com-Pleat warehouse" | internal testing, its own tester list (salespeople) |

Why per-app permission on one SA: one key to rotate, one console user to
audit, but the SA can only touch the apps it is granted; granting "Release to
testing tracks" (not production) caps the blast radius of a leaked key.

### Joe's steps (do in this order; ★ = needs the developer account verified)

**A — Play developer account (in progress)**
1. Finish the organization account (D-U-N-S, identity verification, fee).
   Sign in at https://play.google.com/console with the company Google account.

**B ★ — Create the app record**
1. Play Console → **Create app**.
2. App name `Com-Pleat IMS`; default language English (Canada) or English
   (US); **App**; **Free**. Accept the declarations. **Create app**.
3. Ignore the "Set up your app" dashboard tasks for now (store listing, Data
   safety, content rating etc. are not needed for internal testing — §4 has
   the answers ready if the console insists on any of them).

**C ★ — Play App Signing (Option A; skip to C-B for Option B)**
1. Left menu → **Test and release → Setup → App signing** (menu wording
   varies by console version; it is under Setup).
2. Choose **Export and upload a key from Java keystore**. Download
   `pepk.jar` and copy the shown `--encryptionkey=…` value.
3. On your laptop (Java installed), with `compleat-release.jks` at hand
   (alias = the value of repo secret `KEY_ALIAS`), run the command the page
   shows, shaped like:
   ```
   java -jar pepk.jar --keystore=compleat-release.jks --alias=<KEY_ALIAS> \
        --output=compleat-mobile-signing.zip --include-cert --rsa-aes-encryption \
        --encryption-key-hex=<value from the page>
   ```
   (paste the console's exact flags; they change between console versions).
4. Upload the resulting zip on the same page → **Save**. The page should then
   show the app signing key certificate = the same SHA-1 as your keystore.
- **C-B (Option B):** choose **Use a Google-generated key**. Then, on every
  Zebra, uninstall Com-Pleat IMS before step J.

**D ★ — Internal testing track + tester list**
1. **Test and release → Testing → Internal testing → Testers** tab →
   **Create email list**: name `Com-Pleat warehouse`, add the shared
   warehouse Google account and your own account → **Save changes**.
2. Tick the list so it is active for the track. Note the **Copy link**
   (opt-in URL) — you will open it on every device (step J).

**E ★ — One-time manual first upload** (the Play API refuses to create the
first release; the action's README: "Make sure you upload an apk or aab
manually first by creating a release through the play console" **[V]**)
1. In GitHub → Actions → **Build APK** → **Run workflow** (main). When green,
   open the run and download artifact `compleat-mobile-aab`; unzip →
   `app-prod-release.aab`.
2. Play Console → **Internal testing → Releases** tab → **Create new release**.
3. Drop the `.aab` into **App bundles**. Release name auto-fills (e.g.
   `79 (1.0.79)`); Release notes: "First Play release". **Next / Save**.
4. **Review release → Start rollout to Internal testing**. Fix anything red
   the review page lists (it will name a missing declaration; see §4).

**F ★ — Link a Cloud project for API access**
1. Play Console → **Setup → API access**.
2. **Link an existing Google Cloud project** → choose
   `project-f05aa3b5-e37d-4c19-a03` (the LIVE IMS project; you are its
   owner) → **Link**. If the console cannot see it, the signed-in Play
   account is not a member of that project: tell me and we add it in Cloud
   Console IAM first.
3. Make sure **Google Play Android Developer API** is enabled on that
   project (the page offers a button; otherwise Cloud Console → APIs &
   Services → Enable APIs → "Google Play Android Developer API").

**G — Service account + JSON key (Cloud Console)**
1. https://console.cloud.google.com/iam-admin/serviceaccounts?project=project-f05aa3b5-e37d-4c19-a03
   → **Create service account**.
2. Name `play-publisher`, description `Google Play uploads from GitHub
   Actions (compleat-mobile, compleat-sales)`. **Create and continue**. Grant
   **no** project roles (it needs none; Play permissions come from step H).
   **Done**.
3. Open the new account → **Keys** tab → **Add key → Create new key → JSON
   → Create**. The browser downloads `project-f05aa3b5-…-<id>.json`. Keep it
   in your password manager; it is the CI credential for both apps.
4. Copy the account's email
   (`play-publisher@project-f05aa3b5-e37d-4c19-a03.iam.gserviceaccount.com`).

**H ★ — Invite the service account into the Play Console**
1. Play Console → **Users and permissions → Invite new users**.
2. Email = the service-account email from G.4. Under **App permissions →
   Add app** pick **Com-Pleat IMS** and tick **Release to testing tracks**
   (and the default view permissions). Do NOT tick production/pricing/etc.
3. **Invite user**. (Service accounts accept automatically; if the row shows
   "Pending", wait a few minutes.)
4. Later, when the sales app record exists: same user → **Add app** →
   Compleat Sales → the same permission. Nothing else to redo.

**I — GitHub secret (compleat-mobile)**
1. https://github.com/servairmarketing/compleat-mobile/settings/secrets/actions
   → **New repository secret**.
2. Name **exactly** `PLAY_SERVICE_ACCOUNT_JSON`; value = the **whole
   contents** of the JSON file from G.3 (open in Notepad/TextEdit, select
   all, copy, paste, including the braces). **Add secret**.
3. The other lane adds the same secret, same name, to
   `servairmarketing/compleat-sales` when its Android track is built.

**J ★ — Devices**
1. On one Zebra: confirm the **Play Store** app exists. If not, stop and tell
   me (that device needs the managed-Google-Play route instead).
2. Play Store → sign in with the shared warehouse Google account (your own
   account on your test device).
3. Option A: nothing to uninstall. Option B: uninstall Com-Pleat IMS first.
4. Open the opt-in link from D.2 in the device browser → **Become a tester**
   → **Download it on Google Play** → **Install** (or Update). Repeat 2–4 on
   each Zebra.
5. Play Store → profile → Settings → Network preferences → Auto-update apps:
   leave "Over Wi-Fi only" (default) so updates arrive on their own.

**K — First automated release**
1. GitHub → Actions → **Build APK** → **Run workflow**. With the secret in
   place the run now uploads to the internal track itself; a green
   `release-play` = on Play.
2. On a Zebra open the Play Store listing (or wait for auto-update) and
   confirm the version on the login screen matches `pubspec.yaml`.
3. If the upload step is red, send me the run link; the two usual causes
   are "APK/AAB version code already used" (bump `+N`) and "the caller does
   not have permission" (step H not applied to this app).

---

## 4. Play requirements and what to put in them

### 4.1 Target API level — satisfied
From 31 Aug 2026 new apps and updates must target Android 16 (API 36)
**[V]** (WebSearch result citing answer/11926878). Flutter 3.41.3 sets
`targetSdkVersion = 36` **[V]** (FlutterExtension.kt at tag 3.41.3) and
`build.gradle.kts` takes `flutter.targetSdkVersion` **[V]**. Nothing to do;
keep the Flutter pin at ≥3.41 when the deadline moves next year.

### 4.2 Privacy policy URL (D6)
Not required while the app is exclusively on internal testing **[V]** (§1.1),
but required the moment it goes to closed testing or production, and the
store-listing task asks for it. Proposal: create it now so the record is
complete.

- Host: a static page on LIVE hosting, `public/privacy.html`, served at
  `https://project-f05aa3b5-e37d-4c19-a03.web.app/privacy.html` **[I]**
  (site id from `.firebaserc`; `.web.app` is Firebase's default domain — Joe
  may prefer a custom domain if one exists [U]). It ships through the normal
  `deploy_live.sh` hosting step; no backend change.
- Standards §2.18: every `public/*.html` must carry the shared includes and
  `scripts/check_html_script_tags.py` fails otherwise. `privacy.html` is a
  public, pre-login page → it belongs in `AUTH_JS_EXEMPT` (like `index.html`
  and `forgot-password.html`) and `STYLE_CSS_EXEMPT`, with a stated reason;
  `firebase-config.js` + `env_badge.js` stay (so TEST hosting shows the
  ribbon on it too). **Needs Joe's ruling** — the script's own rule is
  "add a page only with a stated reason".
- Content (plain language, one screen): who we are (Com-Pleat Filters /
  Servair Filters, contact email [Joe supplies]); the app is for employees
  only; what it collects — the username, display name and role of the
  logged-in employee, and the inventory transactions they record (roll IDs,
  quantities, vendor/customer names); why — to run the company's inventory
  system; where — Google Cloud, Montréal region (`northamerica-northeast2`
  [V] CLAUDE.md); no advertising, no analytics SDKs, no location, no
  camera, no contacts [V]: `pubspec.yaml` has none of these packages and the
  manifest declares only INTERNET / WIFI_STATE / NETWORK_STATE /
  REQUEST_INSTALL_PACKAGES; not sold or shared with third parties; encrypted
  in transit (HTTPS); retention = for as long as the employee has an account;
  deletion = ask the administrator (contact email).

### 4.3 Data safety form — draft answers (needed only for closed testing / production)
- Collects data: **Yes**. Encrypted in transit: **Yes**. Deletion request
  mechanism: **Yes** — via the administrator (contact email on the privacy
  page).
- Personal info → **Name** and **User IDs** (username): collected, required,
  not shared, purpose "Account management / App functionality".
- App activity → **Other user-generated content** (inventory entries):
  collected, required, not shared, purpose "App functionality". (Roll IDs
  and quantities are business data, not personal; declaring them is the
  conservative reading.)
- Nothing else (no location, device IDs, financial, health, contacts,
  photos, crash logs, diagnostics — no crash/analytics SDK in the app [V]).
- Independent security review: No.

### 4.4 Other dashboard declarations (only if the console requires them)
- **App access**: "All or some functionality is restricted" → provide login
  instructions. For internal testing this is not reviewed; if ever needed
  for closed/production, a dedicated reviewer user must exist on LIVE —
  Joe's decision then, not now.
- **Ads**: No. **Content rating**: questionnaire, category Utility /
  Productivity, no flagged content → Everyone. **Target audience**: 18+.
  **News app**: No. **COVID-19 contact tracing**: No. **Government app**:
  No. **Financial features**: None. **Health**: None.
- **Store listing** (if required): short description "Com-Pleat / Servair
  warehouse inventory scanner (employees only)"; app icon 512×512 and a
  1024×500 feature graphic derived from the existing launcher icon; two
  screenshots from the TEST app are acceptable placeholders. Category:
  Business.

### 4.5 Cost
Play developer registration is a one-time fee (USD 25 historically **[I]**).
CI: Linux minutes only — no macOS multiplier; the AAB build replaces one APK
build, so run time is roughly unchanged **[I]**.

---

## 5. Out of scope / not proposed now
- Publishing the TEST (qa) app through Play (§2.4 later option).
- Managed Google Play / EMM enrollment of the Zebras (§1.1).
- The sales app's Android track (other lane; §3 leaves it a two-step job:
  create the record, add the SA and the secret).
- `in_app_update` in-app prompt (§2.5).

## 6. Sources
- Play testing tracks: https://support.google.com/googleplay/android-developer/answer/9845334
- Play App Signing: https://support.google.com/googleplay/android-developer/answer/9842756
- Device and Network Abuse (self-update rule): https://support.google.com/googleplay/android-developer/answer/16559646
- Target API level: https://support.google.com/googleplay/android-developer/answer/11926878
- Data safety: https://support.google.com/googleplay/android-developer/answer/10787469
- Upload action: https://github.com/r0adkll/upload-google-play
- Repo facts: `compleat-mobile/.github/workflows/build.yml`, `android/app/build.gradle.kts`,
  `android/app/src/main/AndroidManifest.xml`, `pubspec.yaml`,
  `lib/services/update_service.dart`, `lib/screens/home_screen.dart`;
  `compleat-sales/docs/IOS_TESTFLIGHT_SETUP.md`, `ios/fastlane/Fastfile`,
  `android/app/build.gradle.kts`; `compleat-inventory/CLAUDE.md`,
  `docs/IMS_CURRENT_TRUTH.md` §3.11, `docs/05_SYNC_STATE.md` #25,
  `scripts/check_html_script_tags.py`, `.firebaserc`; `gh secret list` /
  `gh release list` on both repos (2026-09-28).

---

## 7. BUILD 2026-10-01 — rulings D1–D7 APPROVED as recommended (Joe); pipeline built, NOTHING deployed

**Console state reported by Joe 2026-10-01 (not verifiable from this
session; recorded as reported):** organization developer account verified
("Com-pleat Filters Inc.", account ID 6954196794482709734, owner
servairmarketing@gmail.com); app record "Com-Pleat IMS", package
`com.compleat.compleat_mobile` **[V matches `android/app/build.gradle.kts`
line 24]**, free, Play App Signing terms accepted; internal-testing tester
list **"IMS Warehouse"** created and active (the plan's placeholder name
"Com-Pleat warehouse" in §3.D is superseded).

### 7.1 What is built (branch `feat/play-internal-distribution`, off `main` 79cc326)

| # | Piece | File(s) | Status |
|---|---|---|---|
| 1 | AAB build in the LIVE job `build` (workflow_dispatch only, unchanged trigger): `flutter test` → `flutter build appbundle --release --flavor prod` → artifact `compleat-mobile-aab` (always) → Play upload (gated) → APK + GitHub Release kept (D3) | `.github/workflows/build.yml` job `build` | built; YAML parsed locally; **proven only by the first dispatch** (AAB path `build/app/outputs/bundle/prodRelease/app-prod-release.aab` is the Flutter convention [I]) |
| 2 | Play upload step `r0adkll/upload-google-play@v1.1.5` (newest v1.x tag, 2026-04-21 [V `gh api`]) with inputs `serviceAccountJsonPlainText` / `packageName` / `releaseFiles` / `track: internal` / `status: completed` / `releaseName "<versionCode> (<version>)"` — all verified against the action's `action.yml` at that tag [V]. Gate: job-level `env.HAS_PLAY_SA = secrets.PLAY_SERVICE_ACCOUNT_JSON != ''`; step `if: env.HAS_PLAY_SA == 'true'`; a sibling notice step prints when skipped. **Secret name (D7): `PLAY_SERVICE_ACCOUNT_JSON`** — same name the compleat-sales lane will use. | same | built; skip path is what the first dispatch exercises (no secret yet) |
| 3 | D4 — prod flavor stops self-updating: `checkForUpdate()` returns null without any network call unless `APP_ENV=test`; the GitHub `/releases/latest` client branch is DELETED; prod home-screen button = "Check for Update (Play Store)" → `market://details?id=com.compleat.compleat_mobile`, https fallback (`url_launcher`, already a dependency). qa flavor flow unchanged. | `lib/services/update_service.dart`, `lib/screens/home_screen.dart`, `test/update_service_test.dart` (3 tests, run by CI `flutter test` in BOTH jobs) | built; **not run locally** (no Flutter in Cloud Shell — rule); proven by the next push's `build-test-apk` job |
| 4 | Manifest split: `REQUEST_INSTALL_PACKAGES` + the APK `FileProvider` + `res/xml/file_paths.xml` moved from `src/main` to **`src/qa`** (Gradle merges flavor manifests). The Play build declares no self-install permission. | `android/app/src/main/AndroidManifest.xml`, `android/app/src/qa/AndroidManifest.xml` (new), `android/app/src/qa/res/xml/file_paths.xml` (moved) | built; proven by the next push's qa build (uses the provider) + the first prod dispatch |
| 5 | Version `1.0.78+79` → **`1.0.79+80`** (Play versionCode 80; must increase on every Play upload) | `pubspec.yaml` | built |
| 6 | README build-environments table updated | `README.md` | built |
| 7 | D6 privacy page `public/privacy.html` + linter exemption (`AUTH_JS_EXEMPT`/`STYLE_CSS_EXEMPT`, reason stated) — **compleat-inventory branch `feat/play-privacy-page`**, NOT deployed | `compleat-inventory/public/privacy.html`, `scripts/check_html_script_tags.py`, `docs/UNPROMOTED_TO_LIVE.md` | built; linter + `tests/test_html_lint.py` run in that worktree (result in the commit message) |

Not built (by design): Data safety form answers (§4.3, only needed off the
internal track); `in_app_update`; the qa app on Play; the compleat-sales
Android track (other lane — it only needs the same SA invited on its app + the
same-named secret).

### 7.2 D2 — PEPK export of the EXISTING keystore (Joe's laptop; one command at a time)

Where this happens: Play Console → Com-Pleat IMS → **Test and release →
Internal testing → Create new release**. On a brand-new app the first
release page offers **"Choose signing key"** → **Use a different key** →
**Export and upload a key from Java keystore** (older console wording:
Setup → App signing → "Export and upload a key from Java keystore") [I —
console wording moves; the PEPK option is the one to pick either way]. That
page gives you two things: the **pepk.jar** download and an
**encryption key** (a long hex string). Needs: `compleat-release.jks` (the
same file whose base64 is repo secret `KEYSTORE_BASE64`, dated 2026-04-08),
its store password (`KEYSTORE_PASSWORD`), alias (`KEY_ALIAS`) and key
password (`KEY_PASSWORD`). GitHub cannot show secrets back; if the `.jks` is
not on your machine, STOP and tell me (then D2 falls back to Option B).

Run in a folder that contains `pepk.jar` and `compleat-release.jks`:

1. Java present (any 11+ works):
   ```
   java -version
   ```
2. Confirm the alias and note the SHA-1 (enter the store password when asked;
   expected: one entry, `Entry type: PrivateKeyEntry`, `Signature algorithm
   name: SHA256withRSA`, key size 2048 or larger):
   ```
   keytool -list -v -keystore compleat-release.jks -alias <KEY_ALIAS>
   ```
3. Export the private key encrypted for Google (replace the two
   placeholders; `<ENCRYPTION_KEY_HEX>` is the value the console page shows
   — paste it exactly; it is ~130 hex characters):
   ```
   java -jar pepk.jar --keystore=compleat-release.jks --alias=<KEY_ALIAS> --output=compleat-mobile-signing.zip --include-cert --rsa-aes-encryption --encryption-key-hex=<ENCRYPTION_KEY_HEX>
   ```
   It prompts for the keystore password, then the key password. If the
   console page shows a command with different flag names (e.g.
   `--encryptionkey=` without `--rsa-aes-encryption`), **use the console's
   exact flags** — the jar version and the page are matched to each other.
   Expected: the file `compleat-mobile-signing.zip` appears, no error text.
4. Back in the console page: **Upload** `compleat-mobile-signing.zip` →
   continue. After it is accepted, the app-signing section should show an
   **App signing key certificate** whose **SHA-1 equals the SHA-1 from
   step 2** — that equality is the proof that Play will sign with our key
   (in-place upgrades on the Zebras, fallback APK compatible). If the two
   SHA-1s differ, stop and tell me before rolling out.
5. Delete `compleat-mobile-signing.zip` from the laptop once uploaded (it
   is your private key, encrypted to Google's key — not needed again).

The upload key stays the same keystore, so CI's four signing secrets are
unchanged.

### 7.3 Joe's remaining console / GitHub steps (plan §3, renumbered)

1. Merge `feat/play-internal-distribution` → `main` (push to main builds
   `test-v1.0.79`; nothing reaches LIVE or Play).
2. Dispatch **Build APK** on `main` → download artifact
   **`compleat-mobile-aab`** → `app-prod-release.aab`. (This run ALSO
   publishes GitHub Release `v1.0.79` — D3 fallback path, same build; the
   `/releases/latest` client is gone from prod, so no device self-installs
   it.)
3. Create new release on Internal testing: §7.2 signing-key step, drop the
   `.aab`, release notes "First Play release", review, **Start rollout to
   Internal testing**.
4. Setup → API access → link Cloud project `project-f05aa3b5-e37d-4c19-a03`
   + enable Google Play Android Developer API (plan §3.F).
5. Cloud Console → service account `play-publisher` → JSON key (plan §3.G).
6. Play Console → Users and permissions → invite the SA with **Release to
   testing tracks** on Com-Pleat IMS only (plan §3.H).
7. GitHub → compleat-mobile → secret **`PLAY_SERVICE_ACCOUNT_JSON`** = whole
   JSON file (plan §3.I).
8. Devices: shared warehouse Google account in the "IMS Warehouse" list,
   opt-in link, install from Play (plan §3.J). Option A → no uninstall.
9. Next LIVE promotion: bump `+N`, merge, dispatch → the run uploads to Play
   itself (plan §3.K).

### 7.4 D6 privacy page — deploy command (NOT run; Joe runs, after merge)

URL once live: `https://project-f05aa3b5-e37d-4c19-a03.web.app/privacy.html`
(LIVE site id from `.firebaserc`; `/index.html` on that host answers 200 and
`/privacy.html` answers 404 today [V curl 2026-10-01]). ⚑ The page carries a
**placeholder contact email** — supply the address and I fill it in before
anything is deployed. TEST first, then LIVE, both from the `compleat-inventory`
repo root on `main` after `feat/play-privacy-page` is merged:

```
./scripts/build-test.sh && firebase deploy --only hosting:test --project test
```
Check: `https://compleat-ims-test.web.app/privacy.html` shows the page with
the TEST ribbon. Then LIVE — hosting only, no backend, no migration (the
full `deploy_live.sh` would also redeploy the unchanged backend; this is the
documented hosting step of that script run on its own; `hosting:prod`
serves `public/` = LIVE):
```
firebase deploy --only hosting:prod --project project-f05aa3b5-e37d-4c19-a03
```
Then paste `https://project-f05aa3b5-e37d-4c19-a03.web.app/privacy.html`
into Play Console → **Grow users → Store presence → Store listing (or App
content → Privacy policy)** → Save. Not required while the app is only on
internal testing; required before closed testing / production.

### 7.5 D2 revised (Joe, 2026-10-01): PEPK export runs INSIDE GitHub Actions — `.github/workflows/pepk-export.yml`

Why: the keystore passwords exist only as GitHub repo secrets (deliberate —
never stored anywhere else; the Cloud Shell copy of `compleat-release.jks`
exists but nothing on this machine can open it). So §7.2's laptop commands
are replaced by a manual-only workflow.

Facts established 2026-10-01 (all VERIFIED in this session):
- Secret names reused EXACTLY from `build.yml`: `KEYSTORE_BASE64`,
  `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD` (all four exist, set
  2026-04-08; `gh secret list`). The alias IS a secret → no guessing needed.
- LIVE signing certificate (read from the v1.0.78 APK's signing block, no
  password needed): SHA-1 `9B:FE:7E:9A:87:88:79:25:65:E2:BA:31:27:F7:5F:0F:08:89:07:01`,
  SHA-256 `B3FD33EB…C43382`, subject `CN=Compleat IMS, OU=IT, O=Servair
  Filters, L=Orangeville, ST=Ontario, C=CA`, RSA 2048, valid 2026-04-08 →
  2053-08-24. The Play Console must show this SHA-1 after the upload.
- Google's tool: `https://www.gstatic.com/play-apps-publisher-rapid/signing-tool/prod/pepk.jar`,
  9,136,653 bytes, SHA-256
  `aaccc0774b240aa5304bdad2a49865e92f229ca73209ecb6eaafe75dc858e24e`
  (downloaded + verified in Cloud Shell; the workflow pins this hash and
  stops on a mismatch). Its `--help`: hex-string mode is
  `--encryptionkey=<hex>` ("4-byte identity + 64-byte P256 point" = exactly
  136 hex chars; the workflow validates that); the `--rsa-aes-encryption`
  mode needs a PEM file instead and is not used.
- pepk reads passwords via `java.io.Console` — null on a CI runner, so a
  stdin pipe crashes (NullPointerException, proven). Password FLAGS would
  put the secrets in the runner's process argument list, so the workflow
  uses `scripts/pepk_export.py`: runs pepk in a pseudo-terminal, answers
  the prompts `Enter password for store '…':` then `Enter password for key
  '…':` from env vars, redacts the values from the captured output, refuses
  password flags. Proven against throwaway PKCS12 (same pw) and JKS
  (different pws) keystores: zip = `encryptedPrivateKey` + `certificate.pem`;
  wrong password → `Cannot recover key`, exit 1, no zip; wrong alias → `No
  key for alias`, exit 1; no password string in any log.
- PKCS12 rule: keytool ignores a separate `-keypass` on PKCS12 keystores, so
  if `KEY_PASSWORD` ≠ the real key password the workflow retries ONCE with
  the keystore password and says so in a `::notice::`.

Workflow safety: `on: workflow_dispatch` ONLY; one input `encryption_key`
(masked); `permissions: contents: read`; no Flutter, no build, no test, no
GitHub Release, no Play upload — dispatching it on `feat/play-internal-distribution`
cannot touch LIVE, TEST or Play. Output: artifact
`compleat-mobile-pepk-export` containing only `compleat-mobile-signing.zip`
(encrypted to Google's key), 1-day retention; keystore + jar deleted from
the runner in an `always()` step.

**Joe's dispatch steps (one at a time):**
1. Play Console → Com-Pleat IMS → Test and release → Internal testing →
   **Create new release** → in the app-signing choice pick **Use a different
   key → Export and upload a key from Java keystore** (older wording: Setup →
   App signing → same option). Leave this page open; copy the
   **encryption key** hex string it shows (do NOT download pepk.jar there —
   the workflow fetches and checksums it).
2. GitHub → compleat-mobile → **Actions** → left list **"PEPK export (Play
   App Signing key)"** → **Run workflow** → Branch
   `feat/play-internal-distribution` → paste the hex string into
   `encryption_key` → **Run workflow**.
3. Open the run. Expected: every step green; step "Show the keystore
   certificate fingerprints" prints `SHA1: 9B:FE:7E:9A:…:07:01`; the export
   step ends with `encryptedPrivateKey` + `certificate.pem` listed; artifact
   `compleat-mobile-pepk-export` at the bottom. If the fingerprint step is
   red → `KEYSTORE_PASSWORD`/`KEY_ALIAS` wrong; if the export step says
   `Cannot recover key` after the retry → `KEY_PASSWORD` wrong; if the
   checksum step is red → Google changed pepk.jar, send me the run link.
4. Download the artifact, unzip it once → `compleat-mobile-signing.zip`;
   upload THAT zip on the console page from step 1.
5. The console shows the **App signing key certificate** — its SHA-1 must be
   `9B:FE:7E:9A:87:88:79:25:65:E2:BA:31:27:F7:5F:0F:08:89:07:01`. Equal →
   continue the release (the AAB from the `compleat-mobile-aab` artifact,
   §7.3 step 2). Different → stop, send me a screenshot; do not roll out.
6. Delete the downloaded zip from your machine. The artifact expires after
   one day; the workflow can be re-run any time.
