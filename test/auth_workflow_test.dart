import 'package:flutter_test/flutter_test.dart';
import 'package:branch_flow/services/auth_service.dart';

void main() {
  group('Auth, Forgot Password & Email Verification Tests', () {
    late AuthService auth;

    setUp(() {
      auth = AuthService();
    });

    // These tests run without Firebase (offline local mode). Real OTP codes are
    // emailed and checked by Cloud Functions; see functions/otp.test.js.
    test('Sign Up in offline mode creates a verified user without OTP', () async {
      final res = await auth.signUp(
        email: 'new.member@library.org',
        password: 'securePassword123',
        fullName: 'New Reader',
        role: 'member',
      );

      expect(res.success, isTrue);
      expect(res.requiresVerification, isFalse);
      expect(res.codeSent, isFalse);
      expect(auth.currentUser, isNotNull);
      expect(auth.currentUser!.email, 'new.member@library.org');
      expect(auth.currentUser!.isEmailVerified, isTrue);
    });

    test('OTP actions fail cleanly without the server', () async {
      final sendRes = await auth.sendEmailVerificationOtp();
      expect(sendRes.success, isFalse);

      final verifyRes = await auth.verifyEmailWithOtp('123456');
      expect(verifyRes.success, isFalse);

      final resetOtpRes = await auth.sendPasswordResetOtp('new.member@library.org');
      expect(resetOtpRes.success, isFalse);

      final resetRes = await auth.resetPasswordWithOtp(
        email: 'new.member@library.org',
        otp: '123456',
        newPassword: 'myNewStrongPassword2026',
      );
      expect(resetRes.success, isFalse);
    });

    test('Password reset validates input before calling the server', () async {
      final badEmail = await auth.sendPasswordResetOtp('not-an-email');
      expect(badEmail.message, contains('valid email'));

      final shortCode = await auth.resetPasswordWithOtp(
        email: 'new.member@library.org',
        otp: '12',
        newPassword: 'myNewStrongPassword2026',
      );
      expect(shortCode.message, contains('6-digit'));

      final shortPassword = await auth.resetPasswordWithOtp(
        email: 'new.member@library.org',
        otp: '123456',
        newPassword: 'abc',
      );
      expect(shortPassword.message, contains('at least 6'));
    });

    test('Sign Out clears active user session', () async {
      expect(auth.isAuthenticated, isTrue);
      await auth.signOut();
      expect(auth.isAuthenticated, isFalse);
      expect(auth.currentUser, isNull);
    });

    test('Sign In authenticates registered user', () async {
      final signInRes = await auth.signIn(
        email: 'priya.sharma@library.org',
        password: 'password123',
      );

      expect(signInRes.success, isTrue);
      expect(auth.isAuthenticated, isTrue);
      expect(auth.currentUser!.email, 'priya.sharma@library.org');
      expect(auth.currentUser!.isEmailVerified, isTrue);
    });
  });
}
