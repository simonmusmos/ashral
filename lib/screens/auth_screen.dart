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
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  _AuthMode _mode = _AuthMode.signIn;
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  late final AnimationController _animController;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnim =
        CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.04),
      end: Offset.zero,
    ).animate(
        CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic));
    _animController.forward();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _animController.dispose();
    super.dispose();
  }

  void _toggleMode() => setState(() {
        _mode = _mode == _AuthMode.signIn ? _AuthMode.signUp : _AuthMode.signIn;
        _errorMessage = null;
      });

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
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
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _friendlyError(String code) => switch (code) {
        'user-not-found' || 'invalid-credential' => 'Invalid email or password.',
        'wrong-password' => 'Invalid email or password.',
        'email-already-in-use' => 'An account with this email already exists.',
        'weak-password' => 'Password must be at least 6 characters.',
        'invalid-email' => 'Enter a valid email address.',
        'too-many-requests' => 'Too many attempts. Try again later.',
        _ => 'Authentication failed.',
      };

  @override
  Widget build(BuildContext context) {
    final isSignIn = _mode == _AuthMode.signIn;

    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: FadeTransition(
                opacity: _fadeAnim,
                child: SlideTransition(
                  position: _slideAnim,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 72),

                      _buildWordmark(),

                      const SizedBox(height: 52),

                      _ModeTabs(mode: _mode, onToggle: _toggleMode),

                      const SizedBox(height: 32),

                      Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _FieldLabel(label: 'Email'),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              autocorrect: false,
                              style: AppText.ui(size: 14),
                              decoration: const InputDecoration(
                                hintText: 'you@example.com',
                              ),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) {
                                  return 'Email is required';
                                }
                                if (!v.contains('@')) return 'Invalid email';
                                return null;
                              },
                            ),

                            const SizedBox(height: 18),

                            _FieldLabel(label: 'Password'),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _passwordController,
                              obscureText: _obscurePassword,
                              textInputAction: TextInputAction.done,
                              onFieldSubmitted: (_) => _submit(),
                              style: AppText.ui(size: 14),
                              decoration: InputDecoration(
                                hintText: '••••••••',
                                suffixIcon: GestureDetector(
                                  onTap: () => setState(
                                      () => _obscurePassword = !_obscurePassword),
                                  child: Padding(
                                    padding: const EdgeInsets.only(right: 14),
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
                                  minWidth: 44,
                                  minHeight: 44,
                                ),
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

                            const SizedBox(height: 28),

                            if (_errorMessage != null) ...[
                              _ErrorBanner(message: _errorMessage!),
                              const SizedBox(height: 16),
                            ],

                            _SubmitButton(
                              isLoading: _isLoading,
                              label: isSignIn ? 'Continue' : 'Create account',
                              onPressed: _submit,
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 28),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            isSignIn
                                ? "Don't have an account?"
                                : 'Already have an account?',
                            style:
                                AppText.ui(size: 13, color: AppColors.textMuted),
                          ),
                          const SizedBox(width: 5),
                          GestureDetector(
                            onTap: _toggleMode,
                            child: Text(
                              isSignIn ? 'Sign up' : 'Sign in',
                              style: AppText.ui(
                                size: 13,
                                weight: FontWeight.w600,
                                color: AppColors.ai,
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 64),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWordmark() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 50,
          height: 50,
          margin: const EdgeInsets.only(bottom: 20),
          decoration: BoxDecoration(
            color: AppColors.aiBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppColors.ai.withValues(alpha: 0.25),
              width: 1,
            ),
          ),
          child: Center(
            child: Text(
              'A',
              style: AppText.display(
                size: 24,
                weight: FontWeight.w800,
                color: AppColors.ai,
                letterSpacing: 0,
              ),
            ),
          ),
        ),
        Text(
          'Ashral',
          style: AppText.display(
            size: 38,
            weight: FontWeight.w700,
            letterSpacing: -1.5,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'agent console',
          style: AppText.mono(size: 12, color: AppColors.textMuted),
        ),
      ],
    );
  }
}

// ── Field label ────────────────────────────────────────────────────────────────

class _FieldLabel extends StatelessWidget {
  final String label;
  const _FieldLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(label.toUpperCase(), style: AppText.sectionLabel());
  }
}

// ── Mode tabs ─────────────────────────────────────────────────────────────────

class _ModeTabs extends StatelessWidget {
  final _AuthMode mode;
  final VoidCallback onToggle;

  const _ModeTabs({required this.mode, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _Tab(
          label: 'Sign in',
          selected: mode == _AuthMode.signIn,
          onTap: mode != _AuthMode.signIn ? onToggle : null,
        ),
        const SizedBox(width: 24),
        _Tab(
          label: 'Sign up',
          selected: mode == _AuthMode.signUp,
          onTap: mode != _AuthMode.signUp ? onToggle : null,
        ),
      ],
    );
  }
}

class _Tab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const _Tab({required this.label, required this.selected, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? AppColors.textPrimary : Colors.transparent,
              width: 1.5,
            ),
          ),
        ),
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 180),
          style: AppText.ui(
            size: 15,
            weight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? AppColors.textPrimary : AppColors.textMuted,
          ),
          child: Text(label),
        ),
      ),
    );
  }
}

// ── Submit button ─────────────────────────────────────────────────────────────

class _SubmitButton extends StatelessWidget {
  final bool isLoading;
  final String label;
  final VoidCallback onPressed;

  const _SubmitButton({
    required this.isLoading,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: FilledButton(
        onPressed: isLoading ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.textPrimary,
          foregroundColor: AppColors.bgDeep,
          disabledBackgroundColor: AppColors.bgElevated,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: isLoading
            ? const SizedBox(
                height: 18,
                width: 18,
                child: CupertinoActivityIndicator(color: AppColors.textMuted),
              )
            : Text(
                label,
                style: AppText.ui(
                  size: 15,
                  weight: FontWeight.w600,
                  color: AppColors.bgDeep,
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
              style: AppText.ui(size: 13, color: AppColors.error, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}
