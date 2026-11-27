import 'package:flutter/services.dart';

/// Opens Android's speech screen and returns what the user said.
/// The phone's own speech recognition does the listening; the app gets only the text.
class VoiceService {
  static const _method = MethodChannel('spendinbox/voice');

  /// Null when the user cancelled or nothing was heard.
  /// Throws [VoiceUnavailable] when the phone has no speech recognition.
  Future<String?> listen() async {
    try {
      return await _method.invokeMethod<String>('listen', {
        'language': 'en-IN',
        'prompt': 'Say what you spent, e.g. "Lunch 250 and auto 80"',
      });
    } on PlatformException catch (e) {
      if (e.code == 'unavailable') throw VoiceUnavailable();
      rethrow;
    }
  }
}

class VoiceUnavailable implements Exception {}
