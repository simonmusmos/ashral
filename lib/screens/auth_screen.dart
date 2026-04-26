import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme/app_theme.dart';

enum _AuthMode { signIn, signUp }

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  _AuthMode _mode = _AuthMode.signIn;
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  late final AnimationController _enterCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  late final AnimationController _spinCtrl;

  @override
  void initState() {
    super.initState();
    _enterCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _fadeAnim =
        CurvedAnimation(parent: _enterCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
            begin: const Offset(0, 0.04), end: Offset.zero)
        .animate(CurvedAnimation(
            parent: _enterCtrl, curve: Curves.easeOutCubic));
    _enterCtrl.forward();

    _spinCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _enterCtrl.dispose();
    _spinCtrl.dispose();
    super.dispose();
  }

  static Widget _fadeSlide(Widget child, Animation<double> animation) {
    final slide = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut));
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(position: slide, child: child),
    );
  }

  void _toggleMode() => setState(() {
        _mode =
            _mode == _AuthMode.signIn ? _AuthMode.signUp : _AuthMode.signIn;
        _errorMessage = null;
      });

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    _spinCtrl.repeat();
    try {
      if (_mode == _AuthMode.signIn) {
        await AuthService.signIn(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      } else {
        await AuthService.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _errorMessage = _friendlyError(e.code));
    } catch (_) {
      if (mounted) setState(() => _errorMessage = 'Something went wrong.');
    } finally {
      _spinCtrl.stop();
      _spinCtrl.reset();
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _friendlyError(String code) => switch (code) {
        'user-not-found' || 'invalid-credential' =>
          'Invalid email or password.',
        'wrong-password' => 'Invalid email or password.',
        'email-already-in-use' =>
          'An account with this email already exists.',
        'weak-password' => 'Password must be at least 6 characters.',
        'invalid-email' => 'Enter a valid email address.',
        'too-many-requests' => 'Too many attempts. Try again later.',
        _ => 'Authentication failed.',
      };

  @override
  Widget build(BuildContext context) {
    final isSignIn = _mode == _AuthMode.signIn;
    final mq = MediaQuery.of(context);

    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: SlideTransition(
            position: _slideAnim,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: mq.size.height -
                      mq.padding.top -
                      mq.padding.bottom,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 64),

                    // ── Brand ─────────────────────────────────────────────
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        RotationTransition(
                          turns: _spinCtrl,
                          child: Image.asset(
                            'assets/images/app_logo/logo_transparent.png',
                            width: 64,
                            height: 64,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'Ashral',
                          style: AppText.display(
                            size: 34,
                            weight: FontWeight.w700,
                            letterSpacing: -1.2,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          transitionBuilder: _fadeSlide,
                          child: Text(
                            isSignIn
                                ? 'Sign in to your account'
                                : 'Create your account',
                            key: ValueKey(_mode),
                            style: AppText.ui(
                              size: 14,
                              color: AppColors.textMuted,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 48),

                    // ── Form ──────────────────────────────────────────────
                    Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            autocorrect: false,
                            style: AppText.ui(size: 15),
                            decoration: const InputDecoration(
                              hintText: 'Email address',
                              prefixIcon: Padding(
                                padding:
                                    EdgeInsets.only(left: 14, right: 10),
                                child: Icon(CupertinoIcons.mail,
                                    size: 17, color: AppColors.textMuted),
                              ),
                              prefixIconConstraints:
                                  BoxConstraints(minWidth: 0, minHeight: 0),
                            ),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return 'Email is required';
                              }
                              if (!v.contains('@')) return 'Invalid email';
                              return null;
                            },
                          ),

                          const SizedBox(height: 12),

                          TextFormField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _submit(),
                            style: AppText.ui(size: 15),
                            decoration: InputDecoration(
                              hintText: 'Password',
                              prefixIcon: const Padding(
                                padding:
                                    EdgeInsets.only(left: 14, right: 10),
                                child: Icon(CupertinoIcons.lock,
                                    size: 17, color: AppColors.textMuted),
                              ),
                              prefixIconConstraints: const BoxConstraints(
                                  minWidth: 0, minHeight: 0),
                              suffixIcon: GestureDetector(
                                onTap: () => setState(() =>
                                    _obscurePassword = !_obscurePassword),
                                child: Padding(
                                  padding:
                                      const EdgeInsets.only(right: 14),
                                  child: Icon(
                                    _obscurePassword
                                        ? CupertinoIcons.eye_slash
                                        : CupertinoIcons.eye,
                                    size: 17,
                                    color: AppColors.textMuted,
                                  ),
                                ),
                              ),
                              suffixIconConstraints: const BoxConstraints(
                                  minWidth: 44, minHeight: 44),
                            ),
                            validator: (v) {
                              if (v == null || v.isEmpty) {
                                return 'Password is required';
                              }
                              if (!isSignIn && v.length < 6) {
                                return 'Min 6 characters';
                              }
                              return null;
                            },
                          ),

                          const SizedBox(height: 20),

                          if (_errorMessage != null) ...[
                            _ErrorBanner(message: _errorMessage!),
                            const SizedBox(height: 16),
                          ],

                          SizedBox(
                            height: 52,
                            child: FilledButton(
                              onPressed: _isLoading ? null : _submit,
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.textPrimary,
                                foregroundColor: AppColors.bgDeep,
                                disabledBackgroundColor:
                                    AppColors.bgElevated,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: _isLoading
                                  ? const SizedBox(
                                      height: 18,
                                      width: 18,
                                      child: CupertinoActivityIndicator(
                                          color: AppColors.textMuted),
                                    )
                                  : AnimatedSwitcher(
                                      duration:
                                          const Duration(milliseconds: 220),
                                      transitionBuilder: _fadeSlide,
                                      child: Text(
                                        isSignIn
                                            ? 'Continue'
                                            : 'Create account',
                                        key: ValueKey(_mode),
                                        style: AppText.ui(
                                          size: 15,
                                          weight: FontWeight.w600,
                                          color: AppColors.bgDeep,
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),

                    // ── Toggle ────────────────────────────────────────────
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      transitionBuilder: _fadeSlide,
                      child: Row(
                        key: ValueKey(_mode),
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            isSignIn
                                ? "Don't have an account?"
                                : 'Already have an account?',
                            style: AppText.ui(
                                size: 13, color: AppColors.textMuted),
                          ),
                          const SizedBox(width: 5),
                          GestureDetector(
                            onTap: _toggleMode,
                            child: Text(
                              isSignIn ? 'Sign up' : 'Sign in',
                              style: AppText.ui(
                                size: 13,
                                weight: FontWeight.w600,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 64),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Error banner ──────────────────────────────────────────────────────────────

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.errorBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.errorBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(CupertinoIcons.exclamationmark_circle,
                size: 15, color: AppColors.error),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style:
                  AppText.ui(size: 13, color: AppColors.error, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}
