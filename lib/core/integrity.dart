import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Blocks tampered copies: wrong signing key (re-signed / modded APK), debugger, Frida/Xposed.
/// EXPECTED_SIG is injected by the release build when a real keystore is configured.
class Integrity {
  static const _expected = String.fromEnvironment('EXPECTED_SIG');
  static const _ch = MethodChannel('roxyfy/newpipe');

  static Future<bool> ok() async {
    try {
      final m = await _ch.invokeMapMethod<String, dynamic>('integrity');
      if (m == null) return true;
      if (m['tampered'] == true) return false;
      if (_expected.isNotEmpty && m['sig'] != _expected) return false;
      return true;
    } catch (_) {
      return true;
    }
  }
}

class BlockedApp extends StatelessWidget {
  const BlockedApp({super.key});

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
                const SizedBox(height: 24),
                FilledButton(onPressed: () => SystemNavigator.pop(), child: const Text('Close')),
              ]),
            ),
          ),
        ),
      );
}
