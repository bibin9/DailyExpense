# QA report — Daily Expense Tracker 1.0.0

Date: 2026-10-02 · Build under test: commit after "QA fixes" (see git log) · Tester: automated QA suite run on a Windows host (Flutter 3.47.6), plus the owner's manual check on their Android phone (install, activation, basic use: OK)

## Verdict

**Host-side QA: PASS after fixes.** 7 defects found and fixed, each now covered by a regression test. **On-device phase (Monkey stress, logcat privacy, kill/restart, upgrade, network counters): NOT YET RUN.** It needs the phone connected over USB with USB debugging. Not production-ready until that phase and the manual checklist in `PHONE_TESTING.md` pass.

## Scope and method

| Area | How it was tested | Size |
|---|---|---|
| Amount entry | Fuzzing against an independent BigInt reference parser; boundary sweep; display↔input round-trip | 90,000+ inputs |
| Activation security | Every single-character tampering of a token; truncations; 5,000 random strings; request-code corruption | ~6,000 mutations |
| Report correctness | Model-based: 4,000 random add/edit/delete/rename/deactivate ops across 8 time zones (−12:00 to +14:00, incl. +5:30, +5:45) and a leap year; 300 random periods; month and week partitions must sum to the grand total | 300 periods |
| Data safety | Garbage file, truncated file, single flipped byte (HMAC), disk full mid-burst, failure inside a transaction, 100 open/close cycles | 6 scenarios |
| UI flows | Real screens driven end to end: 100+25+8, every validation message, input filtering, 250-char remarks, edit (capture time preserved) and discard prompt, delete confirm, categories (duplicate, turn off, old entries), report navigation and month picker, Lock now, 20 rapid Save taps | 10 flows |
| Accessibility / layout | Every screen at 320×568 (smallest common phone) at font scale 1.0, 1.5 and 2.0, with longest names, max amounts, full remarks, rendered with a real font | 3 scales |
| Volume / performance | 100,000 expenses (~10 years) in the real SQLCipher DB; query plans checked for full scans | 100k rows |
| Privacy (static) | No logging, no network code or SDKs, manifest/backup rules, iOS entitlements, key-store options, no destructive migrations, nothing secret committable | 9 checks |

Totals: **132 app tests + 15 activation + 3 admin = 150 automated tests, all passing**; `flutter analyze` clean; `dart format` clean.

## Defects found and fixed

| ID | Severity | Defect | Fix | Regression test |
|---|---|---|---|---|
| QA-01 | High (usability) | After saving, the "Expense saved" message sat on top of Home's **Add Expense** button for ~4 s and swallowed taps — painful when entering several expenses in a row. | Form messages are scoped to the form; edit/delete confirmations are shown by the screen you return to, which positions them above its button. | `ui_flows_test` (100+25+8 back-to-back adds) |
| QA-02 | High (crash) | **Add / Rename category** and **Start fresh** dialogs disposed their text controller while the closing animation still used it → framework error. | Each dialog is now its own widget that owns and disposes its controller. | `ui_flows_test` categories flow |
| QA-03 | Medium (usability) | A message from the Categories tab (e.g. "Category added") covered Home's **Add Expense** after switching tabs. | Messages are cleared on tab change. | `ui_flows_test` categories → Home → Add Expense |
| QA-04 | High (display) | Large amounts (e.g. AED 999,999.99) on small phones made list rows fail layout → broken rows on Home and Reports. | Shared `AmountLabel`: capped at 38% of width, shrinks to fit. | `ui_layout_stress_test` |
| QA-05 | Medium (accessibility) | At large font sizes the date/time card filled the whole screen (fields pushed below the fold); Add Expense button wider than the screen; "Categories" nav label wrapped mid-word. | Compact full-width date card; floating-button and nav labels capped at 1.3× font scaling. | `ui_layout_stress_test` |
| QA-06 | High (accessibility) | At 2× font on a small phone the **Save** button's label overflowed and was unreadable. | Button content scales down to fit. | `ui_layout_stress_test` |
| QA-07 | Medium (performance) | "Show older expenses" paging did a full table scan each page: 23 ms/page at 100k records (grows with data; slower on phones). | Row-value keyset query uses the index: **0.37 ms/page (62× faster)**, constant with size. | `query_plan_test` (fails on any full scan), `stress_100k_test` |

Earlier, before QA: a crash opening Add Expense (duplicate Hero tags) was found by the smoke test and fixed.

## Measurements (host PC, Intel i7-13700H — phones will be slower)

| | 10,000 expenses | 100,000 expenses |
|---|---|---|
| Database size (encrypted, with indexes) | 2.8 MB (297 B/expense) | 27.5 MB (289 B/expense) |
| Open + decrypt + migration check | <1 ms | 11 ms |
| Monthly report | 3.7 ms (732 entries) | 5.3 ms (690 entries) |
| Weekly / daily report | 0.8 / 0.2 ms | 1.5 / 0.3 ms |
| Home (today total + 40 newest) | 0.3 ms | 0.4 ms |
| "Show older" page | — | 0.37 ms |
| Integrity check after load | ok | ok |

The original planning allowance (2–5 KB per expense) is ~10× higher than measured.

## Not covered yet (needs the phone or a Mac)

| Test | Requires |
|---|---|
| Android **Monkey** random-input stress (thousands of taps/swipes) + crash/ANR check | Phone via USB debugging |
| **logcat** scan for any expense data in system logs | Phone via USB debugging |
| Process kill / restart, install-over upgrade keeps data | Phone via USB debugging |
| Per-app **network traffic counters** = 0 | Phone via USB debugging |
| Biometric/PIN prompts, lockout, FLAG_SECURE in recents, OEM backup/transfer | Owner, manually (`PHONE_TESTING.md`) |
| Everything on iPhone | Mac + Xcode |

## Note for the installed phone

The APK installed on the owner's phone was built **before** these fixes. Rebuild with `tool\android\build_release.ps1` and install with `adb install -r` (keeps data and activation).
