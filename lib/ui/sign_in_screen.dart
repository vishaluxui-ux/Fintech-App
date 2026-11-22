import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth_service.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});
  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  bool _codeSent = false;
  bool _busy = false;
  String? _error;

  static final _emailOk = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  Future<void> _run(Future<void> Function() f) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await f();
    } on AuthException catch (e) {
      setState(() => _error = _friendly(e));
    } catch (_) {
      setState(() => _error = 'Something went wrong. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _friendly(AuthException e) {
    final m = e.message.toLowerCase();
    if (m.contains('expired') || m.contains('invalid')) return 'That code is wrong or has expired. Request a new one.';
    if (m.contains('rate') || e.statusCode == '429') return 'Too many attempts. Wait a minute and try again.';
    return 'Could not sign in: ${e.message}';
  }

  Future<void> _send() async {
    if (!_emailOk.hasMatch(_email.text.trim())) {
      setState(() => _error = 'Enter a valid email address');
      return;
    }
    await _run(() async {
      await context.read<AuthService>().sendCode(_email.text);
      setState(() => _codeSent = true);
    });
  }

  Future<void> _verify() async {
    if (_code.text.trim().length < 6) {
      setState(() => _error = 'Enter the code from the email');
      return;
    }
    await _run(() => context.read<AuthService>().verifyCode(_email.text, _code.text));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const SizedBox(height: 48),
            Align(alignment: Alignment.centerLeft, child: Icon(Icons.inbox_outlined, size: 48, color: cs.primary)),
            const SizedBox(height: 16),
            Text('Spend Inbox', style: t.headlineMedium),
            const SizedBox(height: 8),
            Text('Log spending from UPI alerts and bill photos. Check each item once, then see where your money goes.',
                style: t.bodyLarge),
            const SizedBox(height: 40),
            TextField(
              controller: _email,
              enabled: !_codeSent,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(labelText: 'Email'),
              onSubmitted: (_) => _send(),
            ),
            if (_codeSent) ...[
              const SizedBox(height: 8),
              Text('We emailed ${_email.text.trim()}. Open the email on this phone and tap the link, '
                  'or type the code if the email has one. Check spam too.', style: t.bodySmall),
              const SizedBox(height: 12),
              TextField(
                controller: _code,
                autofocus: true,
                keyboardType: TextInputType.number,
                maxLength: 8,
                autofillHints: const [AutofillHints.oneTimeCode],
                decoration: const InputDecoration(labelText: 'Code (if the email has one)', counterText: ''),
                onSubmitted: (_) => _verify(),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: cs.error)),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : (_codeSent ? _verify : _send),
              child: _busy
                  ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(_codeSent ? 'Sign in' : 'Send code'),
            ),
            if (_codeSent)
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                          _codeSent = false;
                          _code.clear();
                          _error = null;
                        }),
                child: const Text('Use a different email or resend'),
              ),
          ]),
        ),
      ),
    );
  }
}
