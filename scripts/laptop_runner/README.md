# IMS Patrol Test Runner — Tera P60

Double-click `test.bat`. The script does **everything** end to end:

1. Dispatches the GitHub Actions Patrol build for `main`.
2. Waits for it to finish (~5–7 min).
3. Downloads the Patrol APK pair.
4. Installs both APKs on the connected Tera P60.
5. Runs the bundled E2E scenarios via `adb shell am instrument`.
6. Prints a pass/fail summary.

Total wall time: about **7–9 minutes** per run. Type `test`, walk away,
come back to a green or red banner.

Joe's laptop does **not** need Flutter, Patrol CLI, the repo checkout, or
anything else beyond `adb`. The test logic ships compiled inside the
androidTest APK; this script just orchestrates GitHub + the device.

---

## Updates — you never redownload this zip

The script self-updates on every run. It fetches the canonical copy of
`run_tests.ps1` from
[`compleat-mobile/scripts/laptop_runner/`](https://github.com/servairmarketing/compleat-mobile/tree/main/scripts/laptop_runner)
and, if the remote `$SCRIPT_VERSION` is newer than the local one, swaps
itself on disk and relaunches with `-NoSelfUpdate`.

- `config.txt` is **never** touched — your PAT survives every update.
- A backup is written to `run_tests.ps1.bak` before the swap, so a bad
  update can be rolled back manually.
- If GitHub is unreachable, the update check logs a warning and the run
  continues with the local version. Failed update checks never block tests.

After this one-time install you should never need to redownload the zip
again.

---

## One-time setup (~3 minutes)

1. **Put this folder on the Desktop:**
   `C:\Users\joseph\Desktop\Mobile Screen Control\ims_test_runner\`

2. **Create a GitHub Personal Access Token (PAT):**
   - Go to <https://github.com/settings/tokens>
   - Click **Generate new token → classic**
   - Note: `IMS test runner — Joe laptop`
   - Expiration: 90 days
   - Scopes: check **`repo`** AND **`workflow`** (both are required —
     `workflow` is what lets the script trigger CI builds via the API)
   - Click **Generate token**, then **copy** the token immediately
     (GitHub only shows it once)

3. **Fill in `config.txt`:**
   - Copy `config.example.txt` → `config.txt` (same folder)
   - Open `config.txt` in Notepad
   - Replace `YOUR_GITHUB_PAT_HERE` with the token you just copied
   - Save and close

4. **Confirm the device is ready:**
   - Tera P60 plugged in via USB
   - USB debugging enabled (Settings → Developer options)
   - The "Allow USB debugging from this computer?" prompt has been accepted
     on the device. Verify with: open a terminal and run `adb devices` —
     you should see the serial with `device` next to it (not `unauthorized`).

That's it — no manual GitHub steps anymore.

---

## Running a test

1. Make sure the Tera P60 is plugged in and unlocked.
2. **Double-click `test.bat`**.
3. A black window opens. The first phase prints a build progress timer like:
   ```
   ==> Building APKs (typical: about 5-7 min on a clean cache)
       [00:00] status=queued
       [00:30] status=in_progress
       [01:00] status=in_progress
       ...
   ```
   You can walk away here — the script will keep polling and pick the build
   up the moment it finishes.
4. Once the build is done it downloads, installs, and runs the tests.
5. The window pauses with `Press Enter to close`. Read the result, then
   press Enter.

`run_tests.bat` from older copies of this folder still works — it calls
the same script — but `test.bat` is the documented entry point.

---

## What you'll see

### Success
```
============================================================
  RESULT: PASS
  All 5 test(s) passed.
  Run #87 | commit a1b2c3d
  Log: ...\logs\run_20260511_103045.log
============================================================
```

### Failure
```
============================================================
  RESULT: FAIL
  Tests run: 5, Failures: 1
============================================================
```
Scroll up in the window to see the failure stack trace. The full output is
also saved to the matching `logs\run_*.log` file — send that to dev when
asking for help.

### Hard failure (something broke before tests ran)
You'll see a red `==================== FAILURE ====================` block
with an explanation. Common ones below.

---

## Troubleshooting

### `config.txt not found`
You skipped step 3 of setup. Copy `config.example.txt` → `config.txt` and
fill in your PAT.

### `GitHub workflow_dispatch failed: ... 404`
Almost always: PAT is missing the **`workflow`** scope. The classic-PAT
`repo` scope alone is not enough to dispatch a workflow. Regenerate the
token with both `repo` and `workflow` checked, then update `config.txt`.

Also possible: `REPO=` in `config.txt` is wrong (must be `owner/name`,
e.g. `servairmarketing/compleat-mobile`).

### `GitHub API call failed: ... 401`
PAT is wrong, expired, or revoked. Generate a new token and update
`config.txt`.

### `Dispatched run never appeared in the API after 90s`
GitHub accepted the dispatch but didn't surface the run. Open
<https://github.com/servairmarketing/compleat-mobile/actions> and see if a
new run is queued — usually it just needs another minute. Re-run the script
once the run is visible.

### `Build did not complete within 15 minutes`
CI is queued behind other jobs, or one step is genuinely stuck. Open the
run URL printed in the error message. Once it finishes, re-run `test.bat`
to dispatch a fresh build.

### `Build finished with conclusion='failure'`
The CI build failed before producing artifacts. Open the run URL printed
in the error. Most common causes:
- A Flutter compile error in newly-added test code (check the
  `build-patrol-test-apk` job logs).
- `patrol_cli pub global activate` failed (transient — re-run `test.bat`).
- A signing keystore secret was rotated and not updated in repo settings.

### `Run #N completed successfully but did not produce both Patrol APK artifacts`
The build succeeded but the upload-artifact step in `build-patrol-test-apk`
didn't write the expected file paths. Open the run URL and check the
"Build Patrol APKs" step output — the apk paths under
`build/app/outputs/apk/...` may have moved.

### `Downloaded ... is not a zip (bad magic bytes ...)`
GitHub returned an error page instead of the artifact. Usually the PAT
expired between dispatch and download. Generate a new token and update
`config.txt`.

### `No device in 'device' state`
- Unplug and replug the Tera P60.
- Check the USB cable is a data cable (some are charge-only — try another).
- On the device, swipe down the notification shade → USB → File Transfer
  (or PTP), not Charge Only.
- Re-accept the USB debugging prompt on the device.
- Verify in a separate terminal: `adb devices` should list the serial with
  `device`, not `unauthorized` or `offline`.

### `Multiple devices connected`
Unplug any other Android devices / emulators. The script refuses to guess
which one to install to.

### `adb install failed ... INSTALL_FAILED_UPDATE_INCOMPATIBLE`
A prod build with the same package is interfering. The script uninstalls
`.test` packages, but the base prod APK (`com.compleat.compleat_mobile`)
is a different package and shouldn't conflict — if it does, manually:
```
adb uninstall com.compleat.compleat_mobile.test
adb uninstall com.compleat.compleat_mobile.test.test
```
then re-run.

### `Process crashed` in the test output
The instrumentation started but the app died. Most likely causes:
- The test backend (`compleat-inventory-api-...run.app`) is down or
  unreachable from the device's network. Check the device has internet.
- The test user `joseph` / `Test@1234` is missing in the **test** Firestore
  / Auth project. (This is separate from prod.)
- A seeded record the test depends on is missing (e.g. `TESTVEND1`,
  `TEST-PARENT-001`).

Send the matching `logs\run_*.log` file to dev.

---

## What gets created locally

- `logs\run_YYYYMMDD_HHMMSS.log` — full transcript of every run. Keep these;
  they're how you'll debug intermittent failures.
- `downloads\` — extracted APKs from the last run. Safe to delete anytime.
- `config.txt` — your PAT. **Do not share, do not commit.**

`logs\` and `downloads\` are listed in `.gitignore` already.

---

## How it works (for the curious)

1. **Dispatch.** POSTs to
   `/repos/servairmarketing/compleat-mobile/actions/workflows/build.yml/dispatches`
   with `{"ref":"main"}`. GitHub returns 204 No Content if the PAT has
   `workflow` scope.
2. **Identify the run.** Records the local UTC time before dispatch, then
   polls `/actions/runs?event=workflow_dispatch` and grabs the first run
   created at-or-after that timestamp (with a 5s clock-skew grace).
3. **Wait.** Polls `/actions/runs/{id}` every 30s for up to 15 minutes,
   printing `[mm:ss] status=...` so you can see progress. Bails if the
   run doesn't reach `status=completed && conclusion=success`.
4. **Locate artifacts.** Hits `/actions/runs/{id}/artifacts` for that
   specific run — no scanning of "latest 20 runs" — and picks the
   `app-patrol-debug.apk` and `app-patrol-androidTest.apk` entries.
5. **Download + validate.** GETs both archive_download_urls, validates the
   first 4 bytes are the ZIP magic `PK\x03\x04` (catches HTML/JSON error
   pages from GitHub auth failures), unzips into `downloads/`.
6. **Device gate.** `adb devices` — must find exactly one device in
   `device` state.
7. **Reinstall.** Uninstalls any previous `com.compleat.compleat_mobile.test`
   and `.test.test` packages (failures ignored), then `adb install -t -r -d`
   both APKs. `-t` is required because the test APK has the test-only flag.
8. **Verify install.** `adb shell pm list packages` confirms both packages
   are visible.
9. **Run.** `adb shell am instrument -w -e clearPackageData true
   com.compleat.compleat_mobile.test.test/pl.leancode.patrol.PatrolJUnitRunner`
   — the same call Patrol CLI makes internally, minus port-forwarding we
   don't need for non-`$.native.*` tests.
10. **Report.** Parses output for `OK (N tests)` (pass) or `FAILURES!!!`
    (fail) and prints the result banner.

Note: dispatching `build.yml` triggers the whole workflow, including the
`build` job that re-creates the GitHub release for the prod APK. That's
benign (the release is overwritten in place with the same version), but
it does mean every test run produces a release-updated event.
