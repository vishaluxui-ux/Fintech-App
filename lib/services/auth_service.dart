import 'package:supabase_flutter/supabase_flutter.dart';

/// ACC-01: email one-time code (decided 2026-11-22; Google sign-in moved to v1).
class AuthService {
  final SupabaseClient client;
  AuthService(this.client);

  /// Sends a sign-in code to [email]. Creates the account on first use.
  /// The email carries a link back into the app (and a code, once custom SMTP
  /// lets us edit the template). Either one signs the user in.
  static const redirect = 'com.spendinbox.expense_tracker://login-callback';
  Future<void> sendCode(String email) =>
      client.auth.signInWithOtp(email: email.trim(), shouldCreateUser: true, emailRedirectTo: redirect);

  Future<void> verifyCode(String email, String code) =>
      client.auth.verifyOTP(type: OtpType.email, email: email.trim(), token: code.trim());

  Future<void> signOut() => client.auth.signOut();

  /// ACC-03: the `delete-account` Edge Function deletes the user's rows and the
  /// auth user with the service role. Local data is wiped by the caller.
  Future<void> deleteAccount() async {
    final res = await client.functions.invoke('delete-account', method: HttpMethod.post);
    if (res.status != 200) throw Exception('Delete failed (${res.status})');
    await signOut();
  }
}
