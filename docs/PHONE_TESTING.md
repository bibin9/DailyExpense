# Testing on a real Android phone

This PC can't run an Android emulator (CPU virtualization is off in the BIOS), so testing uses a real phone. Any Android 7.0+ phone works. Ideally test on one Samsung and one other brand.

## 1. Prepare the phone (once)

1. Set a screen lock: **Settings → Security → Screen lock** (PIN, pattern or password). The app refuses to open without one.
2. Optional: enrol a fingerprint or face.

## 2. Install the app

**Option A — copy the APK (simplest, no cable tools).**
1. Copy `dist\insideout-casa\DailyExpenseTracker-insideout-casa-<version>.apk` to the phone by USB file transfer, Google Drive or WhatsApp to yourself.
2. Open it from the **Files** app. Android asks to allow installs from that app; allow it, tap **Install**, then turn the permission off again.
3. If Play Protect warns about an unknown app, choose **More details → Install anyway**. This happens because the app isn't on Google Play or registered with developer verification yet.

**Option B — USB cable with adb (best for repeated testing).**
1. On the phone, open **Settings → About phone** and tap **Build number** 7 times. Then go to **Settings → Developer options** and turn on **USB debugging**.
2. Connect the cable and accept the "Allow USB debugging?" prompt on the phone.
3. On the PC:

```powershell
. C:\Bibin\_tools\env.ps1
adb devices
adb install -r dist\insideout-casa\DailyExpenseTracker-insideout-casa-1.0.0-build1.apk
```

`-r` installs over an existing copy and keeps its data. That is how real updates behave.

## 3. Activate the phone (per-phone mode only)

InsideOut Casa builds from 1.0.3 carry a **company licence**: after unlocking, the app opens straight to Home, so skip this section. It applies only to clients set to per-phone activation.


1. Open the app and unlock with fingerprint or PIN. It shows **Activate this phone for InsideOut Casa** and a request code starting `DETREQ1:`.
2. Tap **Copy request code** and send it to yourself, for example by WhatsApp Web or email.
3. On the PC, sign it:

```powershell
. C:\Bibin\_tools\env.ps1
cd C:\Bibin\daily-expense-tracker
dart run admin_cli/bin/det_admin.dart sign --client insideout-casa --label "Test phone 1" --request "DETREQ1:...paste..."
```

4. Send the long activation code it prints back to the phone, copy it, tap the paste icon in the app, then tap **Activate**.

## 4. Test script (tick each one)

**Turn on airplane mode before starting**: everything must work offline.

| # | Do this | Expect |
|---|---|---|
| 1 | Home screen | Today **AED 0.00**, "No expenses yet", big **Add Expense** button |
| 2 | Add Expense → tap Save without filling | Errors: choose a category; enter the amount |
| 3 | Amount `12.345`, then `0`, then `1000000` | Clear error each time |
| 4 | Petrol, **100**, Save | "Expense saved", form clears, no category preselected |
| 5 | Food **25**, Salik **8** | Home today shows **AED 133.00**, 3 entries |
| 6 | Other, amount 5, no remark | "Please describe the expense…" |
| 7 | Tap Save 3–4 times very fast | Only **one** new record |
| 8 | Open an expense, change amount and remark, save | Date/time unchanged, totals update |
| 9 | Delete an expense | Confirmation shown; total drops immediately |
| 10 | Reports → Daily / Weekly / Monthly | Count, total, per-category subtotals, newest first; Weekly shows Mon–Sun dates |
| 11 | Categories → add "Tolls", try adding "petrol" | Duplicate refused |
| 12 | Turn off "Carwash" | Not offered in Add Expense; old Carwash entries still show and still appear in reports |
| 13 | Swipe the app away, reopen | Asks to unlock; all data still there |
| 14 | Recent-apps screen | Preview is blank or blue, never your expenses |
| 15 | Try a screenshot inside the app | Blocked |
| 16 | Leave the app 1 minute, return | Not locked |
| 17 | Leave the app 2+ minutes, return | Locked; asks to unlock |
| 18 | On the unlock prompt tap Cancel | Stays locked with an Unlock button |
| 19 | Wrong fingerprint 5+ times | "Too many attempts" message, PIN fallback works |
| 20 | Settings | Data-loss warning, "Key protection: Android Keystore (TEE)" or "StrongBox", BCR signature |
| 21 | Install the same APK again with `adb install -r` | Data and activation kept |
| 22 | Uninstall, reinstall | Starts empty and asks for activation again (expected — no backup in v1) |
| 23 | Copy the activation code to a **second** phone | Rejected: "belongs to a different phone" |

| 24 | Settings → **Create backup**, password `short` | "Use at least 8 characters" |
| 25 | Create backup with an 8+ character password → save to Downloads or Drive | "Backup saved", Last backup = today |
| 26 | Second phone (or after uninstall/reinstall): activate, Home → **Restore a backup**, wrong password | "The password is wrong…" |
| 27 | Right password | Preview shows count, dates and total → **Restore** → all records back, same dates/times; still activated |
| 28 | Settings on a phone that has records | Restore is not offered (only for empty app) |

Note the phone model, Android version and any problems. Add them to `docs/TEST_REPORT.md`.

## Optional: confirm no network traffic

Install **PCAPdroid** from Google Play, start a capture filtered to Daily Expense Tracker, then use the app. You should see **zero** connections. The release APK has no INTERNET permission at all, so this is a second check.
