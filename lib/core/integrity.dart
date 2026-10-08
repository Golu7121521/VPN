import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Blocks tampered copies: wrong signing key (re-signed / modded APK), debugger, Frida/Xposed,
/// signature-killer tools. EXPECTED_SIG is injected by the release build when a real keystore is set.
class Integrity {
  static const _expected = String.fromEnvironment('EXPECTED_SIG');
  static const _ch = MethodChannel('roxyfy/newpipe');

  /// null = fine, otherwise a short code of the failed check.
  static Future<String?> failure() async {
    try {
      final m = await _ch.invokeMapMethod<String, dynamic>('integrity');
      if (m == null) return null;
      if (m['tampered'] == true) return 'T${m['why']}';
      if (_expected.isNotEmpty) {
        if (m['sig'] != _expected) return 'S';
        final apk = m['apkSig'] as String?; // read from the APK file itself
        if (apk != null && apk != _expected) return 'F';
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> ok() async => (await failure()) == null;
}

class BlockedApp extends StatelessWidget {
  const BlockedApp({super.key, this.code = ''});
  final String code;

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(useMaterial3: true),
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.gpp_bad_rounded, size: 64, color: Colors.redAccent),
                const SizedBox(height: 16),
                const Text('Unsafe copy detected', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                const Text('This app was modified or is being inspected. Please install the original Roxyfy.',
                    textAlign: TextAlign.center),
                if (code.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('Code: $code', style: const TextStyle(color: Colors.grey)),
                ],
                const SizedBox(height: 24),
                FilledButton(onPressed: () => SystemNavigator.pop(), child: const Text('Close')),
              ]),
            ),
          ),
        ),
      );
}
