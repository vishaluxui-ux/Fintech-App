import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';

/// ACC-01: Google sign-in only (decided 2026-11-21), exchanged for a Supabase session.
class AuthService {
  final SupabaseClient client;
  AuthService(this.client);

  bool _initialized = false;

  Future<void> _init() async {
    if (_initialized) return;
    await GoogleSignIn.instance.initialize(serverClientId: Config.googleWebClientId);
    _initialized = true;
  }

  Future<void> signIn() async {
    await _init();
    final account = await GoogleSignIn.instance.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null) throw Exception('Google did not return an ID token');
    await client.auth.signInWithIdToken(provider: OAuthProvider.google, idToken: idToken);
  }

  Future<void> signOut() async {
    await _init();
    await GoogleSignIn.instance.signOut();
    await client.auth.signOut();
  }

  /// ACC-03: the `delete-account` Edge Function deletes the user's rows and the
  /// auth user with the service role. Local data is wiped by the caller.
  Future<void> deleteAccount() async {
    final res = await client.functions.invoke('delete-account', method: HttpMethod.post);
    if (res.status != 200) throw Exception('Delete failed (${res.status})');
    await signOut();
  }
}
