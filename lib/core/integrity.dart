import 'package:flutter/services.dart';

/// Registers this build's expected signing-certificate hash with the native side.
/// All tamper checks (wrong signature, debugger, Frida/Xposed, signature-killer tools,
/// wrong package name) then run natively and silently kill the process if anything is
/// wrong - no Dart code path, no on-screen message. Safe to call even without a real
/// keystore configured (EXPECTED_SIG empty): native then only checks for tamper tools.
const _expectedSig = String.fromEnvironment('EXPECTED_SIG');
const _ch = MethodChannel('roxyfy/newpipe');

Future<void> registerIntegrity() async {
  try {
    await _ch.invokeMethod('setExpected', {'sig': _expectedSig});
  } catch (_) {}
}
