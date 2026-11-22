# Spend Inbox — Project Tracker

Android expense tracker (Flutter + Supabase + Claude Haiku).
Last updated: 22 Nov 2026

## Key dates
| Date | Milestone |
|---|---|
| 10 Dec 2026 | Closed beta: 12+ testers installed, running 14 days |
| ~24 Dec 2026 | Apply for production |
| Before 1 Jan 2027 | Play Store production launch |

## 1. Existing features (built and in the beta APK)
| ID | Date | Feature |
|---|---|---|
| F-01 | 22 Nov | UPI payment capture from notifications (Google Pay, PhonePe, Paytm, BHIM, Amazon Pay, CRED, iMobile, HDFC, YONO SBI, Axis). No SMS, no accessibility service |
| F-02 | 22 Nov | ATM withdrawal alerts logged as unallocated cash |
| F-03 | 22 Nov | Bill scan (camera/gallery) read by Claude Haiku into item lines; payment screenshots read as one spend (fixed 22 Nov) |
| F-04 | 22 Nov | Share a screenshot/bill from any app into Spend Inbox |
| F-05 | 22 Nov | Inbox grouped by bill/payment; edit, approve, approve all per bill, reject, delete, add a missed line |
| F-06 | 22 Nov | One-tap "Approve N" for all unflagged items |
| F-07 | 22 Nov | Flags with reasons: low confidence, new merchant, unknown payee, possible duplicate |
| F-08 | 22 Nov | Bill total mismatch sheet: Discount (spread over lines) / Problem while printing / Line appears twice / Other (reason + actual total); printed discounts applied automatically |
| F-09 | 22 Nov | Duplicate handling setting: flag or auto-reject (UPI payments and re-scanned bills); bill matching a UPI payment can replace it |
| F-10 | 22 Nov | Auto-approve known merchants (approved twice, same category), marked "Auto"; setting on/off |
| F-11 | 22 Nov | Claude reads payment alerts the built-in rules can't; queued offline; logged in Supabase `alert_log` |
| F-12 | 22 Nov | Cash wallet: split withdrawals into spends, outstanding shown; month-end review prompt |
| F-13 | 22 Nov | Notifications: daily 8 pm nudge only when items/cash are waiting; Sunday 7 pm weekly summary (setting) |
| F-14 | 22 Nov | Spending dashboard: approved total, by category, recent list, inbox count. Pending never counts |
| F-15 | 22 Nov | Email sign-in (code or link); offline-first local storage with sync to Supabase (RLS per user) |
| F-16 | 22 Nov | Delete account and all data in the app |
| F-17 | 22 Nov | Bill photo setting: keep after approval or delete |
| F-18 | 22 Nov | "Check payment alerts" diagnostics screen |
| F-19 | 22 Nov | 51 automated tests passing |

## 2. New features (planned, not built)
| ID | Date | Feature | Target | Notes |
|---|---|---|---|---|
| N-01 | 22 Nov | SMS reading as opt-in | v1 | Only if Play approves — depends on Q-01 |
| N-02 | 22 Nov | Pro subscription via RevenueCat: ₹99/month or ₹799/year; free = 15 bill scans/month | v1 | |
| N-03 | 22 Nov | Category budgets with overspend alerts | v1 | |
| N-04 | 22 Nov | Hindi interface | v1 | |
| N-05 | 22 Nov | Cash count reconciliation | v1 | |
| N-06 | 22 Nov | Forwarded email receipts | v1 | |
| N-07 | 22 Nov | Google sign-in | v1 | Moved from beta |
| N-08 | 22 Nov | Good/bad spending tag per category | v1 | Needs decision — Q-02 |
| N-09 | 22 Nov | Household mode | Later | |

## 3. Bugs & issues log
| ID | Date | Issue | Status |
|---|---|---|---|
| B-01 | 22 Nov | Same bill scanned twice counted twice | Fixed 22 Nov |
| B-02 | 22 Nov | Items not saving to server (new Supabase projects need table grants) | Fixed 22 Nov |
| B-03 | 22 Nov | Sync pushed items before their bill → rejected | Fixed 22 Nov |
| B-04 | 22 Nov | Payment screenshot shared → "No items found" | Fixed 22 Nov (server) — user to retest |
| B-05 | 22 Nov | ₹1 payments via Google Pay and CRED not captured: these apps usually post no notification for outgoing payments | Open — see Q-01 |
| B-06 | 22 Nov | Sideloaded APK: Android blocks notification access until "Allow restricted settings" | Known; fine once installed from Play. Idea: in-app help (I-01) |
| B-07 | 22 Nov | Supabase default email sends a link not a code; code needs custom SMTP (Gmail app password) | Workaround: link opens app (see I-02) |

## 4. Improvements
| ID | Date | Improvement | Status |
|---|---|---|---|
| I-01 | 22 Nov | In-app steps for "Allow restricted settings" when access is blocked (B-06) | To do |
| I-02 | 22 Nov | Custom SMTP (Gmail or Resend) before testers join — Supabase built-in email sends only a few emails/hour | To do — before 10 Dec |
| I-03 | 22 Nov | Permanent release signing key (needed for Play) | To do |
| I-04 | 22 Nov | Spend limit on Anthropic console (e.g. US$10/month) | To do |
| I-05 | 22 Nov | App icon and name branding (currently Flutter default icon) | To do |

## 5. Questions & decisions

### Open
| ID | Date | Question | Notes |
|---|---|---|---|
| Q-01 | 22 Nov | How to capture payments when UPI apps don't notify? A) bank app alerts, B) share screenshot, C) SMS opt-in | For 23 Nov. Suggested: beta with A+B, measure capture rate, apply for C in v1. Need: user's bank + "Check payment alerts" screenshot |
| Q-02 | 22 Nov | Good/bad spending definition per category | Blocks N-08 |
| Q-03 | 22 Nov | Play Console registration (US$25) and identity verification | Not yet done — needed before 10 Dec |

### Decided
| ID | Date | Decision |
|---|---|---|
| D-01 | 22 Nov | Sign-in: email code/link for beta (Google moved to v1) |
| D-02 | 22 Nov | AI model: Claude Haiku (≈5 paise per bill) |
| D-03 | 22 Nov | Items can be deleted and rejected; rejected kept, never counted |
| D-04 | 22 Nov | Duplicates: user setting (flag / auto-reject) |
| D-05 | 22 Nov | Bill photos: user setting (keep / delete after approval) |
| D-06 | 22 Nov | Pricing: Free + Pro ₹99/month or ₹799/year; free limit 15 scans/month |
| D-07 | 22 Nov | Tools: user uses only this Claude chat + phone + Supabase/Play websites; no VS Code/Android Studio |

## Accounts and services (no secrets here)
| Service | Details |
|---|---|
| Supabase | Project `thshyjmtrlqpyzdxevni`; Edge Functions: parse-bill, parse-alert, delete-account |
| Anthropic API | Key stored only in Supabase secrets |
| GitHub | vishaluxui-ux/Fintech-App |
| Play Console | Not yet registered (Q-03) |
