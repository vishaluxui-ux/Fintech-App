/// Build-time config. Pass with --dart-define, for example:
/// flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_PUBLISHABLE_KEY=... --dart-define=GOOGLE_WEB_CLIENT_ID=...
class Config {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabasePublishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  static const googleWebClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');
}
