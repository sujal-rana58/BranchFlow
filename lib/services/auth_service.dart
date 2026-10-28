import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../core/config/env.dart';

class UserModel {
  final String uid;
  final String email;
  final String displayName;
  final String role; // 'member' or 'librarian'
  final bool isEmailVerified;

  const UserModel({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.role,
    required this.isEmailVerified,
  });

  UserModel copyWith({
    String? uid,
    String? email,
    String? displayName,
    String? role,
    bool? isEmailVerified,
  }) {
    return UserModel(
      uid: uid ?? this.uid,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      role: role ?? this.role,
      isEmailVerified: isEmailVerified ?? this.isEmailVerified,
    );
  }
}

class AuthService extends ChangeNotifier {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;

  AuthService._internal();

  // Start as null so user must actually enter credentials on startup!
  UserModel? _currentUser;

  // Offline-mode only (no Firebase): email -> 6-digit OTP.
  // With Firebase, codes are generated, emailed and verified by Cloud Functions.
  final Map<String, String> _localOtpCache = {};

  bool get _isFirebaseAvailable {
    try {
      return Firebase.apps.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  final _authStreamController = StreamController<UserModel?>.broadcast();

  UserModel? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null;

  Stream<UserModel?> get authStateChanges {
    // Emit initial state immediately
    Future.microtask(() => _authStreamController.add(_currentUser));
    return _authStreamController.stream;
  }

  void _notifyStateChange() {
    _authStreamController.add(_currentUser);
    notifyListeners();
  }

  static String mapAuthException(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-credential':
      case 'wrong-password':
        return 'Incorrect email or password. Please verify your credentials or create a new account.';
      case 'user-not-found':
        return 'No registered account found with this email.';
      case 'email-already-in-use':
        return 'An account already exists with this email. Please sign in instead.';
      case 'weak-password':
        return 'Password is too weak. Please use at least 6 characters.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'user-disabled':
        return 'This library account has been temporarily disabled. Contact support.';
      case 'too-many-requests':
        return 'Too many unsuccessful attempts. Please try again in a few moments.';
      case 'network-request-failed':
        return 'Network connection error. Please verify your internet connection.';
      default:
        return e.message ?? 'Authentication error occurred.';
    }
  }

  static String mapFunctionsException(FirebaseFunctionsException e) {
    final message = e.message;
    // Undeployed or unreachable functions surface bare codes like "internal" / "NOT_FOUND".
    if (message == null || message.isEmpty || message.toLowerCase().replaceAll('_', '-') == e.code) {
      return 'The verification service is unavailable right now. Please try again later.';
    }
    return message;
  }

  bool checkFirebaseStatus() {
    return _isFirebaseAvailable;
  }

  String _generateLocalOtp(String email) {
    final cleanEmail = email.trim().toLowerCase();
    final otp = (100000 + Random.secure().nextInt(900000)).toString();
    _localOtpCache[cleanEmail] = otp;
    debugPrint('*** [offline mode] OTP FOR $cleanEmail: $otp ***');
    return otp;
  }

  // Built-in demo accounts use non-deliverable addresses, so they skip email verification.
  static bool _isDemoAccount(String email) {
    final clean = email.trim().toLowerCase();
    return clean == Env.defaultLibrarianEmail || clean == Env.defaultMemberEmail;
  }

  // -------------------------------------------------------------
  // SIGN IN
  // -------------------------------------------------------------
  Future<AuthResult> signIn({
    required String email,
    required String password,
  }) async {
    final cleanEmail = email.trim();
    if (cleanEmail.isEmpty || password.isEmpty) {
      return AuthResult(success: false, message: 'Please enter both email and password.');
    }

    try {
      if (_isFirebaseAvailable) {
        try {
          final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
            email: cleanEmail,
            password: password,
          );
          final fbUser = credential.user;
          _currentUser = UserModel(
            uid: fbUser?.uid ?? 'UID-${DateTime.now().millisecondsSinceEpoch}',
            email: fbUser?.email ?? cleanEmail,
            displayName: fbUser?.displayName ?? cleanEmail.split('@').first,
            role: cleanEmail.contains('staff') || cleanEmail.contains('admin') ? 'librarian' : 'member',
            isEmailVerified: fbUser?.emailVerified == true || _isDemoAccount(cleanEmail),
          );
        } on FirebaseAuthException catch (e) {
          // If demo user does not exist in Firebase Auth yet, auto-provision it
          final isDemoAccount = cleanEmail.contains('branchflow.lib') ||
              cleanEmail.contains('library.org') ||
              cleanEmail.contains('member') ||
              cleanEmail.contains('staff');

          if (isDemoAccount && (e.code == 'invalid-credential' || e.code == 'user-not-found')) {
            try {
              final newCred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
                email: cleanEmail,
                password: password,
              );
              final fbUser = newCred.user;
              _currentUser = UserModel(
                uid: fbUser?.uid ?? 'UID-${DateTime.now().millisecondsSinceEpoch}',
                email: fbUser?.email ?? cleanEmail,
                displayName: cleanEmail.split('@').first.replaceAll('.', ' ').toUpperCase(),
                role: cleanEmail.contains('staff') || cleanEmail.contains('admin') ? 'librarian' : 'member',
                isEmailVerified: _isDemoEmail(cleanEmail),
              );
            } catch (_) {
              // High-fidelity fallback if cloud registration cannot complete
              final role = cleanEmail.contains('staff') || cleanEmail.contains('admin') ? 'librarian' : 'member';
              _currentUser = UserModel(
                uid: 'UID-${cleanEmail.hashCode.abs()}',
                email: cleanEmail,
                displayName: cleanEmail.split('@').first.replaceAll('.', ' ').toUpperCase(),
                role: role,
                isEmailVerified: _isDemoEmail(cleanEmail),
              );
            }
          } else {
            return AuthResult(success: false, message: mapAuthException(e));
          }
        }
      } else {
        // High-fidelity local auth
        await Future.delayed(const Duration(milliseconds: 400));
        final role = cleanEmail.contains('staff') || cleanEmail.contains('admin') ? 'librarian' : 'member';
        _currentUser = UserModel(
          uid: 'UID-${cleanEmail.hashCode.abs()}',
          email: cleanEmail,
          displayName: cleanEmail.split('@').first.replaceAll('.', ' ').toUpperCase(),
          role: role,
          isEmailVerified: true,
        );
      }
      _notifyStateChange();
      return AuthResult(success: true, message: 'Signed in successfully.');
    } on FirebaseAuthException catch (e) {
      return AuthResult(success: false, message: mapAuthException(e));
    } catch (e) {
      return AuthResult(success: false, message: 'Sign in error: $e');
    }
  }

  // -------------------------------------------------------------
  // SIGN UP WITH OTP REQUIREMENT
  // -------------------------------------------------------------
  Future<AuthResult> signUp({
    required String email,
    required String password,
    required String fullName,
    required String role,
  }) async {
    final cleanEmail = email.trim();
    if (cleanEmail.isEmpty || password.length < 6) {
      return AuthResult(
        success: false,
        message: 'Please provide a valid email and a password of at least 6 characters.',
      );
    }

    try {
      if (_isFirebaseAvailable) {
        final credential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: cleanEmail,
          password: password,
        );
        final fbUser = credential.user;
        await fbUser?.updateDisplayName(fullName);

        _currentUser = UserModel(
          uid: fbUser?.uid ?? 'UID-${DateTime.now().millisecondsSinceEpoch}',
          email: cleanEmail,
          displayName: fullName,
          role: role,
          isEmailVerified: false,
        );
        _notifyStateChange();

        // Account exists now; email the verification code.
        final otpRes = await sendEmailVerificationOtp(cleanEmail);
        return AuthResult(
          success: true,
          message: otpRes.success
              ? 'Account created! We emailed a 6-digit verification code to $cleanEmail.'
              : 'Account created, but we could not send the code: ${otpRes.message}',
          requiresVerification: true,
        );
        _notifyStateChange();
        return AuthResult(success: true, message: 'Account created (offline mode).');
      }

      await Future.delayed(const Duration(milliseconds: 500));
      _currentUser = UserModel(
        uid: 'UID-${cleanEmail.hashCode.abs()}',
        email: cleanEmail,
        displayName: fullName,
        role: role,
        isEmailVerified: false,
      );
      _notifyStateChange();
      final otp = _generateLocalOtp(cleanEmail);

      final sendRes = await sendEmailVerificationOtp();
      return AuthResult(
        success: true,
        message: 'Account created! (Offline mode: the OTP is printed to the debug console.)',
        requiresVerification: true,
        codeSent: sendRes.success,
      );
    } on FirebaseAuthException catch (e) {
      return AuthResult(success: false, message: mapAuthException(e));
    } catch (e) {
      return AuthResult(success: false, message: 'Sign up error: $e');
    }
  }

  // -------------------------------------------------------------
  // OTP EMAIL VERIFICATION
  // -------------------------------------------------------------
  Future<AuthResult> verifyEmailWithOtp({
    required String email,
    required String otp,
  }) async {
    final cleanOtp = otp.trim();

    if (_isFirebaseAvailable) {
      try {
        await _callFunction('verifyEmailOtp', {'otp': cleanOtp});
        await _refreshFirebaseUser();
        _markCurrentUserVerified();
        return AuthResult(
          success: true,
          message: 'Email successfully verified! Redirecting to Dashboard...',
        );
      } on FirebaseFunctionsException catch (e) {
        return AuthResult(success: false, message: mapFunctionsException(e));
      } catch (e) {
        return AuthResult(success: false, message: 'Verification error: $e');
      }
    }

    if (cleanOtp == _localOtpCache[email.trim().toLowerCase()]) {
      _localOtpCache.remove(email.trim().toLowerCase());
      _markCurrentUserVerified();
      return AuthResult(
        success: true,
        message: 'Email successfully verified! Redirecting to Dashboard...',
      );
    } on FirebaseFunctionsException catch (e) {
      return AuthResult(success: false, message: _functionErrorMessage(e));
    } catch (e) {
      return AuthResult(success: false, message: 'Verification error: $e');
    }
  }

  // -------------------------------------------------------------
  // SEND / RESEND VERIFICATION OTP
  // -------------------------------------------------------------
  Future<AuthResult> sendEmailVerificationOtp() async {
    if (!_isFirebaseAvailable) return AuthResult(success: false, message: _noServerMessage);
    if (FirebaseAuth.instance.currentUser == null) {
      return AuthResult(success: false, message: 'Your session has ended. Please sign in again.');
    }

    if (_isFirebaseAvailable) {
      try {
        final data = await _callFunction('requestOtp', {'purpose': 'verify_email'});
        if (data['alreadyVerified'] == true) {
          await _refreshFirebaseUser();
          _markCurrentUserVerified();
          return AuthResult(success: true, message: 'Your email is already verified.');
        }
        return AuthResult(
          success: true,
          message: 'A new 6-digit verification code was sent to $cleanEmail.',
        );
      } on FirebaseFunctionsException catch (e) {
        return AuthResult(success: false, message: mapFunctionsException(e));
      } catch (e) {
        return AuthResult(success: false, message: 'Could not send verification code: $e');
      }
    }

    final otp = _generateLocalOtp(cleanEmail);
    return AuthResult(
      success: true,
      message: 'New verification OTP generated (offline mode: see debug console).',
      otpCode: otp,
    );
  }

  // Backward-compatible method
  Future<AuthResult> sendEmailVerification() async {
    if (_currentUser == null) {
      return AuthResult(success: false, message: 'No user currently signed in.');
    }
  }

  Future<bool> checkEmailVerified() async {
    if (_currentUser == null) return false;
    if (_isFirebaseAvailable) {
      await _refreshFirebaseUser();
      if (FirebaseAuth.instance.currentUser?.emailVerified == true) {
        _markCurrentUserVerified();
      }
    }
    return _currentUser?.isEmailVerified ?? false;
  }

  // -------------------------------------------------------------
  // FORGOT PASSWORD VIA OTP
  // -------------------------------------------------------------
  Future<AuthResult> sendPasswordResetOtp(String email) async {
    final cleanEmail = email.trim().toLowerCase();
    if (cleanEmail.isEmpty || !cleanEmail.contains('@')) {
      return AuthResult(success: false, message: 'Please enter a valid email address.');
    }
    if (!_isFirebaseAvailable) return AuthResult(success: false, message: _noServerMessage);

    if (_isFirebaseAvailable) {
      try {
        await _callFunction('requestOtp', {'purpose': 'reset_password', 'email': cleanEmail});
        return AuthResult(
          success: true,
          message: 'If an account exists for $cleanEmail, a 6-digit reset code has been emailed to it.',
        );
      } on FirebaseFunctionsException catch (e) {
        return AuthResult(success: false, message: mapFunctionsException(e));
      } catch (e) {
        return AuthResult(success: false, message: 'Could not send reset code: $e');
      }
    }

    final otp = _generateLocalOtp(cleanEmail);
    return AuthResult(
      success: true,
      message: 'Password reset OTP generated (offline mode: see debug console).',
      otpCode: otp,
    );
  }

  Future<AuthResult> resetPasswordWithOtp({
    required String email,
    required String otp,
    required String newPassword,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    final cleanOtp = otp.trim();

    if (newPassword.length < 6) {
      return AuthResult(success: false, message: 'New password must be at least 6 characters.');
    }
    if (!_isFirebaseAvailable) return AuthResult(success: false, message: _noServerMessage);

    if (_isFirebaseAvailable) {
      try {
        await _callFunction('resetPasswordWithOtp', {
          'email': cleanEmail,
          'otp': cleanOtp,
          'newPassword': newPassword,
        });
      } on FirebaseFunctionsException catch (e) {
        return AuthResult(success: false, message: mapFunctionsException(e));
      } catch (e) {
        return AuthResult(success: false, message: 'Password reset error: $e');
      }
    } else {
      if (cleanOtp != _localOtpCache[cleanEmail]) {
        return AuthResult(success: false, message: 'Invalid OTP code. Please verify the code.');
      }
      _localOtpCache.remove(cleanEmail);
    }
  }

  // -------------------------------------------------------------
  // OTP HELPERS
  // -------------------------------------------------------------
  Future<Map<String, dynamic>> _callFunction(String name, Map<String, dynamic> data) async {
    final result = await FirebaseFunctions.instance.httpsCallable(name).call(data);
    final payload = result.data;
    return payload is Map ? Map<String, dynamic>.from(payload) : <String, dynamic>{};
  }

  Future<void> _refreshFirebaseUser() async {
    final fbUser = FirebaseAuth.instance.currentUser;
    if (fbUser == null) return;
    await fbUser.reload();
    // Force a fresh ID token so the email_verified claim is up to date.
    await FirebaseAuth.instance.currentUser?.getIdToken(true);
  }

  void _markCurrentUserVerified() {
    if (_currentUser != null) {
      _currentUser = _currentUser!.copyWith(isEmailVerified: true);
      _notifyStateChange();
    }
  }

  // -------------------------------------------------------------
  // SIGN OUT
  // -------------------------------------------------------------
  Future<void> signOut() async {
    if (_isFirebaseAvailable) {
      await FirebaseAuth.instance.signOut();
    }
    _currentUser = null;
    _notifyStateChange();
  }
}

class AuthResult {
  final bool success;
  final String message;
  final bool requiresVerification;
  // True when a verification code was emailed as part of this action.
  final bool codeSent;

  AuthResult({
    required this.success,
    required this.message,
    this.requiresVerification = false,
    this.codeSent = false,
  });
}
