import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Handles biometric (Face ID / Touch ID) authentication.
/// After successful email/password sign-in, call [saveBiometricEnabled].
/// On subsequent app opens, call [authenticateWithBiometrics].
class BiometricService {
  static final BiometricService _instance = BiometricService._();
  factory BiometricService() => _instance;
  BiometricService._();

  final _auth = LocalAuthentication();
  final _storage = const FlutterSecureStorage();

  static const _keyEnabled = 'biometric_enabled';
  static const _keyEmail = 'biometric_email';
  static const _keyPassword = 'biometric_password';

  /// Returns true if the device supports biometrics (Face ID or Touch ID).
  Future<bool> isAvailable() async {
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final isSupported = await _auth.isDeviceSupported();
      return canCheck && isSupported;
    } catch (_) {
      return false;
    }
  }

  /// Returns true if the user previously enabled biometric login.
  Future<bool> isEnabled() async {
    final val = await _storage.read(key: _keyEnabled);
    return val == 'true';
  }

  /// Save credentials for biometric re-login.
  Future<void> saveBiometricEnabled(String email, String password) async {
    await _storage.write(key: _keyEnabled, value: 'true');
    await _storage.write(key: _keyEmail, value: email);
    await _storage.write(key: _keyPassword, value: password);
  }

  /// Disable biometric login and clear stored credentials.
  Future<void> disable() async {
    await _storage.delete(key: _keyEnabled);
    await _storage.delete(key: _keyEmail);
    await _storage.delete(key: _keyPassword);
  }

  /// Prompt Face ID / Touch ID. Returns (email, password) if successful, null if failed.
  Future<({String email, String password})?> authenticateWithBiometrics() async {
    try {
      final ok = await _auth.authenticate(
        localizedReason: 'Sign in to PaintMatch',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
      if (!ok) return null;
      final email = await _storage.read(key: _keyEmail);
      final password = await _storage.read(key: _keyPassword);
      if (email == null || password == null) return null;
      return (email: email, password: password);
    } catch (_) {
      return null;
    }
  }
}
