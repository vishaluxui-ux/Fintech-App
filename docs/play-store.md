# Play Store: listing, notification-access and SMS declarations

## Listing

**App name:** Spend Inbox: UPI Expense Tracker

**Short description (80 chars max):**
Track UPI, bills and cash without typing. Private, on-device payment reading.

**Full description:**

Know where your money goes, without typing every expense.

Spend Inbox picks up your UPI payments from Google Pay, PhonePe, Paytm, BHIM and your bank app's alerts, and, if you turn it on, from your bank's debit SMS. Scan a bill and every item is listed for you. Check each one once in your inbox, and see your spending by category.

**Why Spend Inbox**
• Private by design. We read only payment alerts from UPI and bank apps. Bank SMS reading is optional, reads bank senders only, and happens on your phone; SMS are never uploaded.
• Cash tracking. ATM withdrawals are held as cash; split them into what you actually spent.
• Item-level bills. A grocery bill becomes milk, bread and face wash, each in the right category.
• Less checking over time. Merchants you've approved before are approved for you.
• Your data, your call. Delete your account and every entry from inside the app.

**Free:** unlimited UPI capture, manual and cash entries, 15 bill scans a month.
**Pro (coming soon):** unlimited bill scans, budgets and alerts, Hindi.

**Category:** Finance
**Tags:** expense tracker, UPI, budget, money manager

## Data safety form (answers)

| Data | Collected | Shared | Purpose |
|---|---|---|---|
| Email address | Yes | No | Account sign-in |
| Financial info: purchase history (amounts, payees, categories) | Yes | No | App functionality |
| Photos (bill images) | Yes, processed | Sent to our AI provider (Anthropic) to read the bill; not stored by them for training | App functionality |
| Notification content (payment alerts only) | Processed on device; unusual alerts sent to our AI provider | Same as above | App functionality |
| SMS (bank transaction SMS only, opt-in) | Processed on device only; not collected or sent | No | App functionality |

Encrypted in transit: yes. Users can request deletion: yes, in the app (Settings → Delete account).

## Notification access declaration

**Why the app needs notification access:**
Spend Inbox is an expense tracker. It reads notifications only from a fixed list of UPI and banking apps (Google Pay, PhonePe, Paytm, BHIM, Amazon Pay, CRED and major bank apps) to log the amount, payee and time of payments the user makes and ATM withdrawals. This is the app's core feature: automatic expense logging without SMS access. Notifications from every other app are discarded immediately on the device and never stored or sent anywhere.

**How the user is informed:** before the system setting opens, an in-app screen explains exactly what is read and that other notifications are ignored. The app works fully without this permission (bill scanning, shared screenshots, manual entry).

**Video to record for the declaration (30–60 s, screen recording on a phone):**
1. Open the app → Settings → "UPI payment alerts".
2. Show the explanation screen, tap Continue, enable Spend Inbox in the system list.
3. Make a ₹1 UPI payment; show it appearing in the inbox with amount, payee and time.
4. Show the app still working with access off (scan a bill).

## SMS permission declaration (READ_SMS)

Fill the **Permissions Declaration Form** in Play Console (App content → Sensitive permissions) before uploading any build that contains READ_SMS. Play reviews these case by case; a build with READ_SMS can't go live on any track until it is approved.

**Core functionality:** SMS-based money management (expense tracking).

**Why the app needs it:** Many UPI apps (Google Pay, CRED) post no notification for outgoing payments, so the bank's debit SMS is the only record on the phone. With the user's opt-in, Spend Inbox reads SMS from registered bank sender IDs (for example AD-HDFCBK) to log the amount, payee and time of spends and ATM withdrawals for the user to approve.

**Limits we apply:**
- Off by default. Turned on in Settings → Bank SMS after an in-app explanation, then Android's permission prompt.
- Only SMS from DLT bank sender headers are read; SMS from phone numbers (personal messages) are skipped before parsing. OTPs, credits, failed and upcoming debits are ignored.
- Parsing happens on the device. SMS text is never stored, uploaded or sent to the AI provider. Only the resulting expense (amount, payee, time) is saved.
- Only READ_SMS is requested (no RECEIVE_SMS, SEND_SMS or WRITE_SMS).
- The app works fully without it (notification alerts, bill scans, manual entry).

**Video to record (30–60 s):**
1. Settings → Bank SMS → show the explanation → Allow → Android prompt → Allow.
2. Show a bank debit SMS in the Messages app.
3. Back in Spend Inbox, tap ↻ "Check for new payments"; show the payment appear in the inbox with amount, payee and time.
4. Turn Bank SMS off in Settings.

**Privacy policy must add:** bank SMS are read on the device only when the user turns it on; SMS text is not collected, stored or shared.
