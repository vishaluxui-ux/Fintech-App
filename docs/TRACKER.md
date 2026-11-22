# Spend Inbox — Project Tracker

Android expense tracker (Flutter + Supabase + Claude Haiku).
Last updated: 22 Nov 2026

**Type key:** ✅ Existing feature (F) · 🆕 New feature (N) · 🐞 Bug/issue (B) · 🔧 Improvement (I) · ❓ Open question (Q) · ✔️ Decision (D)

## Master tracker
| ID | Type | Area | Item | Status | Date |
|---|---|---|---|---|---|
| F-01 | ✅ Existing | Payment capture | UPI payment capture from notifications (Google Pay, PhonePe, Paytm, BHIM, Amazon Pay, CRED, iMobile, HDFC, YONO SBI, Axis). No SMS, no accessibility service | In beta | 22 Nov |
| F-02 | ✅ Existing | Payment capture | ATM withdrawal alerts logged as unallocated cash | In beta | 22 Nov |
| F-11 | ✅ Existing | Payment capture | Claude reads payment alerts the built-in rules can't; queued offline; logged in Supabase `alert_log` | In beta | 22 Nov |
| F-18 | ✅ Existing | Payment capture | "Check payment alerts" diagnostics screen | In beta | 22 Nov |
| F-03 | ✅ Existing | Bill scan | Bill scan (camera/gallery) read by Claude Haiku into item lines; payment screenshots read as one spend | In beta | 22 Nov |
| F-04 | ✅ Existing | Bill scan | Share a screenshot/bill from any app into Spend Inbox | In beta | 22 Nov |
| F-08 | ✅ Existing | Bill scan | Bill total mismatch sheet: Discount / Problem while printing / Line appears twice / Other; printed discounts applied automatically | In beta | 22 Nov |
| F-05 | ✅ Existing | Inbox | Inbox grouped by bill/payment; edit, approve, approve all per bill, reject, delete, add a missed line | In beta | 22 Nov |
| F-06 | ✅ Existing | Inbox | One-tap "Approve N" for all unflagged items | In beta | 22 Nov |
| F-07 | ✅ Existing | Inbox | Flags with reasons: low confidence, new merchant, unknown payee, possible duplicate | In beta | 22 Nov |
| F-09 | ✅ Existing | Inbox | Duplicate handling setting: flag or auto-reject; bill matching a UPI payment can replace it | In beta | 22 Nov |
| F-10 | ✅ Existing | Inbox | Auto-approve known merchants (approved twice, same category), marked "Auto"; setting on/off | In beta | 22 Nov |
| F-12 | ✅ Existing | Cash | Cash wallet: split withdrawals into spends, outstanding shown; month-end review prompt | In beta | 22 Nov |
| F-13 | ✅ Existing | Notifications | Daily 8 pm nudge only when items/cash are waiting; Sunday 7 pm weekly summary (setting) | In beta | 22 Nov |
| F-14 | ✅ Existing | Dashboard | Approved total, by category, recent list, inbox count. Pending never counts | In beta | 22 Nov |
| F-15 | ✅ Existing | Account & sync | Email sign-in (code or link); offline-first storage with sync to Supabase (RLS per user) | In beta | 22 Nov |
| F-16 | ✅ Existing | Account & sync | Delete account and all data in the app | In beta | 22 Nov |
| F-17 | ✅ Existing | Settings | Bill photo setting: keep after approval or delete | In beta | 22 Nov |
| F-19 | ✅ Existing | Quality | 51 automated tests passing | In beta | 22 Nov |
| N-01 | 🆕 New | Payment capture | SMS reading as opt-in — only if Play approves (depends on Q-01) | Planned v1 | 22 Nov |
| N-02 | 🆕 New | Money | Pro subscription via RevenueCat: ₹99/month or ₹799/year; free = 15 bill scans/month | Planned v1 | 22 Nov |
| N-03 | 🆕 New | Budgets | Category budgets with overspend alerts | Planned v1 | 22 Nov |
| N-04 | 🆕 New | Language | Hindi interface | Planned v1 | 22 Nov |
| N-05 | 🆕 New | Cash | Cash count reconciliation | Planned v1 | 22 Nov |
| N-06 | 🆕 New | Payment capture | Forwarded email receipts | Planned v1 | 22 Nov |
| N-07 | 🆕 New | Account & sync | Google sign-in (moved from beta) | Planned v1 | 22 Nov |
| N-08 | 🆕 New | Dashboard | Good/bad spending tag per category (needs Q-02) | Planned v1 | 22 Nov |
| N-09 | 🆕 New | Account & sync | Household mode | Later | 22 Nov |
| B-05 | 🐞 Bug | Payment capture | ₹1 payments via Google Pay and CRED not captured — these apps usually post no notification for outgoing payments | 🔴 Open — see Q-01 | 22 Nov |
| B-04 | 🐞 Bug | Bill scan | Payment screenshot shared → "No items found" | 🟡 Fixed (server) — user to retest | 22 Nov |
| B-06 | 🐞 Bug | Setup | Sideloaded APK: Android blocks notification access until "Allow restricted settings" | 🟡 Known; fine from Play. See I-01 | 22 Nov |
| B-07 | 🐞 Bug | Account & sync | Supabase default email sends a link, not a code; code needs custom SMTP | 🟡 Workaround: link opens app. See I-02 | 22 Nov |
| B-01 | 🐞 Bug | Bill scan | Same bill scanned twice counted twice | 🟢 Fixed | 22 Nov |
| B-02 | 🐞 Bug | Account & sync | Items not saving to server (new Supabase projects need table grants) | 🟢 Fixed | 22 Nov |
| B-03 | 🐞 Bug | Account & sync | Sync pushed items before their bill → rejected | 🟢 Fixed | 22 Nov |
| I-01 | 🔧 Improve | Setup | In-app steps for "Allow restricted settings" when access is blocked (B-06) | To do | 22 Nov |
| I-02 | 🔧 Improve | Account & sync | Custom SMTP (Gmail or Resend) — Supabase built-in email sends only a few per hour | To do — before 10 Dec | 22 Nov |
| I-03 | 🔧 Improve | Play release | Permanent release signing key (needed for Play) | To do | 22 Nov |
| I-04 | 🔧 Improve | AI cost | Spend limit on Anthropic console (e.g. US$10/month) | To do | 22 Nov |
| I-05 | 🔧 Improve | Branding | App icon and name (currently Flutter default icon) | To do | 22 Nov |
| Q-01 | ❓ Open | Payment capture | How to capture payments when UPI apps don't notify? A) bank app alerts, B) share screenshot, C) SMS opt-in. Suggested: beta with A+B, measure, apply for C in v1. Need: user's bank + diagnostics screenshot | Due 23 Nov | 22 Nov |
| Q-02 | ❓ Open | Dashboard | Good/bad spending definition per category (blocks N-08) | Open | 22 Nov |
| Q-03 | ❓ Open | Play release | Play Console registration (US$25) and identity verification | Not done — needed before 10 Dec | 22 Nov |
| D-01 | ✔️ Decided | Account & sync | Sign-in: email code/link for beta; Google moved to v1 | Decided | 22 Nov |
| D-02 | ✔️ Decided | AI cost | AI model: Claude Haiku (≈5 paise per bill) | Decided | 22 Nov |
| D-03 | ✔️ Decided | Inbox | Items can be deleted and rejected; rejected kept, never counted | Decided | 22 Nov |
| D-04 | ✔️ Decided | Inbox | Duplicates: user setting (flag / auto-reject) | Decided | 22 Nov |
| D-05 | ✔️ Decided | Settings | Bill photos: user setting (keep / delete after approval) | Decided | 22 Nov |
| D-06 | ✔️ Decided | Money | Pricing: Free + Pro ₹99/month or ₹799/year; free limit 15 scans/month | Decided | 22 Nov |
| D-07 | ✔️ Decided | Tools | User uses only Claude chat + phone + Supabase/Play websites; no VS Code/Android Studio | Decided | 22 Nov |

## Key dates
| Date | Milestone |
|---|---|
| 10 Dec 2026 | Closed beta: 12+ testers installed, running 14 days |
| ~24 Dec 2026 | Apply for production |
| Before 1 Jan 2027 | Play Store production launch |

## Accounts and services (no secrets here)
| Service | Details |
|---|---|
| Supabase | Project `thshyjmtrlqpyzdxevni`; Edge Functions: parse-bill, parse-alert, delete-account |
| Anthropic API | Key stored only in Supabase secrets |
| GitHub | vishaluxui-ux/Fintech-App |
| Play Console | Not yet registered (Q-03) |
