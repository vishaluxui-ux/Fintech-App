# Spend Inbox: closed beta

Android expense tracker: UPI alerts and bill photos become pending items, you approve them in one inbox, and approved spend shows by category. This build covers the **Beta column** of the build spec only.

## Decisions taken (2026-11-21)

| Open item | Decision |
|---|---|
| Sign-in (ACC-01) | Email one-time code (Google sign-in moved to v1) |
| AI model | Claude Haiku (`claude-haiku-5-5`), called from a Supabase Edge Function |
| Delete vs reject | Both. Rejected items are kept but never counted; deleted items leave all totals |
| Duplicates | User setting: **flag** (default) or **auto-reject** |
| Bill photos | User setting: keep after approval (default on), or delete once the bill is approved. Photos never leave the phone except for parsing |

Still open (not built): paywall trigger, good/bad category tags (CAT-02).

## Layout

```
lib/domain/      models, UPI notification parser, ledger rules (totals, checks, cash, duplicates)
lib/data/        SQLite store with sync outbox, repository, settings
lib/services/    Supabase sync, Google sign-in, bill parser, notification bridge, daily cash reminder
lib/ui/          Spending, Inbox, Bill review, Cash, Settings screens
android/.../UpiNotificationListener.kt   reads notifications from supported UPI/bank apps only
supabase/        schema with RLS, Edge Functions parse-bill and delete-account
test/acceptance_test.dart                one test per Beta acceptance check (25 tests)
```

## Setup

1. Create a Supabase project, then link it and push the schema and functions:
   ```bash
   supabase link --project-ref <ref>
   supabase db push
   supabase secrets set ANTHROPIC_API_KEY=<key>
   supabase functions deploy parse-bill
   supabase functions deploy delete-account
   ```
2. In Supabase → Authentication → Email Templates → **Magic Link**, put `{{ .Token }}` in the body so the email shows the code.
3. Run:
   ```bash
   flutter run --dart-define=SUPABASE_URL=https://<ref>.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=<key>
   ```
4. Tests: `flutter test`

## Before the Play release

- Policy check (release plan step 1): notification-listener use needs a written go/no-go.
- Privacy policy must say bill images go to Anthropic for parsing.
- Replace the debug signing config in `android/app/build.gradle.kts`.
- Test UPI notification wording on real phones for each app testers use; adjust `lib/domain/upi_parser.dart`.
