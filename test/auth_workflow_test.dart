import 'package:flutter_test/flutter_test.dart';
import 'package:branch_flow/services/auth_service.dart';

void main() {
  group('Auth, Forgot Password & Email Verification Tests', () {
    late AuthService auth;

    setUp(() {
      auth = AuthService();
    });

    test('Sign Up creates user with unverified email requiring OTP verification', () async {
      final res = await auth.signUp(
        email: 'new.member@library.org',
        password: 'securePassword123',
        fullName: 'New Reader',
        role: 'member',
      );

      expect(res.success, isTrue);
      expect(res.requiresVerification, isTrue);
      expect(res.otpCode, isNotNull);
      expect(res.otpCode!.length, 6);
      expect(auth.currentUser, isNotNull);
      expect(auth.currentUser!.email, 'new.member@library.org');
      expect(auth.currentUser!.isEmailVerified, isFalse);

      // Verify with the generated OTP
      final verifyRes = await auth.verifyEmailWithOtp(
        email: 'new.member@library.org',
        otp: res.otpCode!,
      );
      expect(verifyRes.success, isTrue);
      expect(auth.currentUser!.isEmailVerified, isTrue);
    });

    test('Forgot Password OTP generation and password reset', () async {
      final otpRes = await auth.sendPasswordResetOtp('new.member@library.org');
      expect(otpRes.success, isTrue);
      expect(otpRes.otpCode, isNotNull);
      expect(otpRes.otpCode!.length, 6);

      // Reset password with valid OTP
      final resetRes = await auth.resetPasswordWithOtp(
        email: 'new.member@library.org',
        otp: otpRes.otpCode!,
        newPassword: 'myNewStrongPassword2026',
      );
      expect(resetRes.success, isTrue);
      expect(resetRes.message, contains('Password successfully reset'));

      // Invalid OTP rejection test
      final invalidOtpRes = await auth.resetPasswordWithOtp(
        email: 'new.member@library.org',
        otp: '999999',
        newPassword: 'anotherPassword',
      );
      expect(invalidOtpRes.success, isFalse);
      expect(invalidOtpRes.message, contains('Invalid OTP'));
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
