import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});
  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _go() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AuthService>().signIn();
    } catch (e) {
      setState(() => _error = 'Sign-in did not finish. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Spacer(),
            Icon(Icons.inbox_outlined, size: 48, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text('Spend Inbox', style: t.headlineMedium),
            const SizedBox(height: 8),
            Text('Log spending from UPI alerts and bill photos. Check each item once, then see where your money goes.',
                style: t.bodyLarge),
            const Spacer(),
            if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy ? null : _go,
                icon: _busy
                    ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.login),
                label: const Text('Continue with Google'),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
