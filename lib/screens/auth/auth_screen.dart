import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../../core/constants/app_colors.dart';
import '../../services/auth_service.dart';
import '../../services/library_repository.dart';
import '../../widgets/primary_button.dart';
import '../home_screen.dart';
import 'email_verification_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final AuthService _auth = AuthService();
  final LibraryRepository _libraryRepo = LibraryRepository();

  bool _isSignUp = false;
  bool _isLoading = false;
  bool _obscurePassword = true;

  final _formKey = GlobalKey<FormState>();

  // Controllers
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  String _selectedRole = 'member'; // 'member' or 'librarian'

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _navigateToHome() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  void _navigateToVerification({bool sendOtpOnOpen = false}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EmailVerificationScreen(
          onVerified: _navigateToHome,
          sendOtpOnOpen: sendOtpOnOpen,
        ),
      ),
    );
  }

  // -------------------------------------------------------------
  // SIGN IN
  // -------------------------------------------------------------
  Future<void> _handleSignIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    final res = await _auth.signIn(
      email: _emailController.text,
      password: _passwordController.text,
    );
    setState(() => _isLoading = false);

    if (res.success) {
      _syncUserRole();
      if (_auth.currentUser?.isEmailVerified == false) {
        _navigateToVerification(sendOtpOnOpen: true);
      } else {
        _navigateToHome();
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res.message),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // -------------------------------------------------------------
  // SIGN UP
  // -------------------------------------------------------------
  Future<void> _handleSignUp() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    final res = await _auth.signUp(
      email: _emailController.text,
      password: _passwordController.text,
      fullName: _nameController.text.trim().isEmpty ? 'Library User' : _nameController.text.trim(),
      role: _selectedRole,
    );
    setState(() => _isLoading = false);

    if (res.success) {
      _syncUserRole();
      if (res.requiresVerification) {
        _navigateToVerification();
      } else {
        _navigateToHome();
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res.message),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _syncUserRole() {
    final role = _auth.currentUser?.role;
    if (role == 'librarian') {
      _libraryRepo.setRole(UserRole.librarian);
    } else {
      _libraryRepo.setRole(UserRole.member);
    }
  }

  // -------------------------------------------------------------
  // FORGOT PASSWORD MODAL (WITH 6-DIGIT OTP VERIFICATION)
  // -------------------------------------------------------------
  void _showForgotPasswordDialog() {
    final TextEditingController resetEmailController = TextEditingController(
      text: _emailController.text,
    );
    final TextEditingController otpController = TextEditingController();
    final TextEditingController newPasswordController = TextEditingController();

    bool isSubmitting = false;
    bool otpSent = false;
    String sentMessage = '';

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  const Icon(Icons.lock_reset, color: AppColors.primary),
                  const SizedBox(width: 10),
                  Text(
                    otpSent ? 'Enter OTP & New Password' : 'Reset Password',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!otpSent) ...[
                      const Text(
                        'Enter your registered email address to receive a 6-digit OTP code.',
                        style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: resetEmailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Registered Email',
                          hintText: 'member@library.org',
                          prefixIcon: Icon(Icons.email_outlined),
                        ),
                      ),
                    ] else ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.accentSoft,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFD4E8DA)),
                        ),
                        child: Text(
                          sentMessage,
                          style: const TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w600),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: isSubmitting
                              ? null
                              : () async {
                                  final messenger = ScaffoldMessenger.of(context);
                                  setDialogState(() => isSubmitting = true);
                                  final res = await _auth.sendPasswordResetOtp(resetEmailController.text);
                                  setDialogState(() {
                                    isSubmitting = false;
                                    if (res.success) sentMessage = res.message;
                                  });
                                  if (!res.success) {
                                    messenger.showSnackBar(
                                      SnackBar(content: Text(res.message), backgroundColor: AppColors.danger),
                                    );
                                  }
                                },
                          child: const Text('Resend code', style: TextStyle(fontSize: 12)),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: otpController,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 6),
                        decoration: const InputDecoration(
                          labelText: '6-Digit OTP',
                          counterText: '',
                          prefixIcon: Icon(Icons.pin_outlined),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: newPasswordController,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'New Password',
                          hintText: 'At least 6 characters',
                          prefixIcon: Icon(Icons.lock_outline),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                if (!otpSent)
                  ElevatedButton(
                    onPressed: isSubmitting
                        ? null
                        : () async {
                            final messenger = ScaffoldMessenger.of(context);
                            setDialogState(() => isSubmitting = true);
                            final res = await _auth.sendPasswordResetOtp(resetEmailController.text);
                            setDialogState(() {
                              isSubmitting = false;
                              if (res.success) {
                                otpSent = true;
                                sentMessage = res.message;
                              }
                            });

                            if (!res.success) {
                              messenger.showSnackBar(
                                SnackBar(content: Text(res.message), backgroundColor: AppColors.danger),
                              );
                            }
                          },
                    child: isSubmitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Send OTP'),
                  )
                else
                  ElevatedButton(
                    onPressed: isSubmitting
                        ? null
                        : () async {
                            setDialogState(() => isSubmitting = true);
                            final res = await _auth.resetPasswordWithOtp(
                              email: resetEmailController.text,
                              otp: otpController.text,
                              newPassword: newPasswordController.text,
                            );
                            setDialogState(() => isSubmitting = false);

                            // Keep the dialog open on failure so the user can retry the code.
                            if (res.success && ctx.mounted) {
                              Navigator.of(ctx).pop();
                            }
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(res.message),
                                  backgroundColor: res.success ? AppColors.success : AppColors.danger,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          },
                    child: isSubmitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Confirm Password Reset'),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  // -------------------------------------------------------------
  // FILL CREDENTIALS HINT (MEMBER DEMO AUTO-FILL)
  // -------------------------------------------------------------
  void _quickFillMemberDemo() {
    setState(() {
      _emailController.text = 'member@branchflow.lib';
      _passwordController.text = 'password123';
      _isSignUp = false;
      _selectedRole = 'member';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Member demo credentials filled. Tap "Sign In" to authenticate.'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _selectStaffManualMode() {
    setState(() {
      _emailController.clear();
      _passwordController.clear();
      _isSignUp = false;
      _selectedRole = 'librarian';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Staff portal: Please manually enter your authorized staff credentials.'),
        duration: Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 440),
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // App Logo & Header
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.auto_stories, color: Colors.white, size: 32),
                  ),
                ),
                const SizedBox(height: 16),
                const Center(
                  child: Text(
                    'BranchFlow',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Center(
                  child: Text(
                    _isSignUp
                        ? 'Join your community cross-branch network'
                        : 'Sign in to access unified library catalog',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                  ),
                ),
                const SizedBox(height: 24),

                // Sign In / Sign Up Mode Switcher
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _isSignUp = false),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: !_isSignUp ? AppColors.surface : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: !_isSignUp
                                  ? [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.05),
                                        blurRadius: 4,
                                        offset: const Offset(0, 1),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Center(
                              child: Text(
                                'Sign In',
                                style: TextStyle(
                                  fontWeight: !_isSignUp ? FontWeight.bold : FontWeight.w500,
                                  color: !_isSignUp ? AppColors.primary : AppColors.textSecondary,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _isSignUp = true),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: _isSignUp ? AppColors.surface : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: _isSignUp
                                  ? [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.05),
                                        blurRadius: 4,
                                        offset: const Offset(0, 1),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Center(
                              child: Text(
                                'Sign Up',
                                style: TextStyle(
                                  fontWeight: _isSignUp ? FontWeight.bold : FontWeight.w500,
                                  color: _isSignUp ? AppColors.primary : AppColors.textSecondary,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Form Container
                Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Sign Up: Name Field
                      if (_isSignUp) ...[
                        TextFormField(
                          controller: _nameController,
                          decoration: const InputDecoration(
                            labelText: 'Full Name',
                            hintText: 'e.g. Alex Morgan',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                          validator: (val) {
                            if (_isSignUp && (val == null || val.trim().isEmpty)) {
                              return 'Please enter your full name';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                      ],

                      // Email Field
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Email Address',
                          hintText: 'name@example.com',
                          prefixIcon: Icon(Icons.email_outlined),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Please enter your email';
                          }
                          if (!val.contains('@') || !val.contains('.')) {
                            return 'Please enter a valid email address';
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 14),

                      // Password Field
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          hintText: '••••••••',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                              size: 18,
                            ),
                            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                          ),
                        ),
                        validator: (val) {
                          if (val == null || val.isEmpty) {
                            return 'Please enter your password';
                          }
                          if (val.length < 6) {
                            return 'Password must be at least 6 characters';
                          }
                          return null;
                        },
                      ),

                      // Forgot Password Button (Only on Sign In)
                      if (!_isSignUp) ...[
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _showForgotPasswordDialog,
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                            ),
                            child: const Text(
                              'Forgot Password?',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primaryLight),
                            ),
                          ),
                        ),
                      ] else ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.accentSoft,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFD4E8DA)),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.badge_outlined, size: 16, color: AppColors.primary),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Registering as a Community Library Member.',
                                  style: TextStyle(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],

                      const SizedBox(height: 10),

                      // Reusable Primary Button
                      PrimaryButton(
                        label: _isSignUp ? 'Create Account & Verify' : 'Sign In',
                        isLoading: _isLoading,
                        onPressed: _isLoading ? null : (_isSignUp ? _handleSignUp : _handleSignIn),
                      ),
                    ],
                  ),
                ),

                if (kDebugMode) ...[
                  const SizedBox(height: 20),
                  const Divider(color: AppColors.border),
                  const SizedBox(height: 12),

                  // Quick Demo Accounts for Evaluation
                  const Center(
                    child: Text(
                      'Dev Evaluation Mode:',
                      style: TextStyle(fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            textStyle: const TextStyle(fontSize: 11),
                          ),
                          onPressed: _quickFillMemberDemo,
                          child: const Text('👤 Member (Demo Auto-Fill)'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            textStyle: const TextStyle(fontSize: 11),
                          ),
                          onPressed: _selectStaffManualMode,
                          child: const Text('🏢 Staff (Manual Login)'),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
