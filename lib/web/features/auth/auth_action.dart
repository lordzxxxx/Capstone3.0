import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mycapstone_project/shared/password_policy.dart';
import 'package:mycapstone_project/web/shared/navigation/web_routes.dart';
import 'package:mycapstone_project/web/shared/theme/app_theme.dart';

/// Branded Firebase email-action handler for account activation/password reset.
///
/// Firebase supplies the one-time `oobCode` in the link. The code is verified
/// and consumed by FirebaseAuth; this page never stores or displays a
/// password, reset token, or credential.
class AuthActionPage extends StatefulWidget {
  const AuthActionPage({super.key});

  @override
  State<AuthActionPage> createState() => _AuthActionPageState();
}

class _AuthActionPageState extends State<AuthActionPage> {
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();

  String? _mode;
  String? _oobCode;
  String? _email;
  String? _error;
  bool _checkingCode = true;
  bool _submitting = false;
  bool _completed = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  @override
  void initState() {
    super.initState();
    final query = Uri.base.queryParameters;
    _mode = query['mode'];
    _oobCode = query['oobCode'];
    _verifyActionCode();
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _verifyActionCode() async {
    if (_mode != 'resetPassword') {
      _setError('This email action is not supported here.');
      return;
    }
    final code = _oobCode;
    if (code == null || code.isEmpty) {
      _setError('This password setup link is incomplete. Request a new link.');
      return;
    }

    try {
      final email = await FirebaseAuth.instance.verifyPasswordResetCode(code);
      if (!mounted) return;
      setState(() {
        _email = email;
        _checkingCode = false;
      });
    } on FirebaseAuthException catch (error) {
      _setError(_friendlyAuthError(error));
    } catch (_) {
      _setError('The secure link could not be verified. Request a new link.');
    }
  }

  void _setError(String message) {
    if (!mounted) return;
    setState(() {
      _checkingCode = false;
      _error = message;
    });
  }

  String _friendlyAuthError(FirebaseAuthException error) {
    switch (error.code) {
      case 'expired-action-code':
        return 'This password setup link has expired. Request a new link.';
      case 'invalid-action-code':
        return 'This password setup link is invalid or has already been used.';
      case 'user-disabled':
        return 'This account is disabled. Contact the City Health Office.';
      case 'user-not-found':
        return 'This account is no longer available. Contact the City Health Office.';
      default:
        return 'The secure link could not be verified. Request a new link.';
    }
  }

  Future<void> _savePassword() async {
    if (_submitting || _oobCode == null) return;
    final password = _passwordController.text;
    final confirmation = _confirmController.text;
    if (!PasswordPolicy.isValid(password)) {
      _showInlineError(PasswordPolicy.validationMessage(password));
      return;
    }
    if (password != confirmation) {
      _showInlineError('The passwords do not match.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await FirebaseAuth.instance.confirmPasswordReset(
        code: _oobCode!,
        newPassword: password,
      );
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _completed = true;
      });
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = _friendlyAuthError(error);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = 'We could not save your password. Please try again.';
      });
    }
  }

  void _showInlineError(String message) {
    if (!mounted) return;
    setState(() => _error = message);
  }

  void _goToLogin() {
    Get.offAllNamed(WebRoutes.login);
  }

  Widget _brandMark() {
    return Container(
      width: 58,
      height: 58,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Image.asset(
        'assets/newlogo_white.png',
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => const Icon(
          Icons.health_and_safety_rounded,
          color: Colors.white,
          size: 32,
        ),
      ),
    );
  }

  Widget _header() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _brandMark(),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'AI-DSUHIS',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'City Health Office Portal',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        Icon(
          Icons.verified_user_outlined,
          color: AppColors.primary,
          size: 22,
          semanticLabel: 'Secure account setup',
        ),
      ],
    );
  }

  Widget _statusIcon(IconData icon, Color color) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: color, size: 32),
    );
  }

  Widget _buildPasswordField({required bool confirmation}) {
    final controller = confirmation ? _confirmController : _passwordController;
    final obscure = confirmation ? _obscureConfirm : _obscurePassword;
    return TextField(
      controller: controller,
      obscureText: obscure,
      textInputAction: confirmation
          ? TextInputAction.done
          : TextInputAction.next,
      onSubmitted: confirmation ? (_) => _savePassword() : null,
      decoration: InputDecoration(
        labelText: confirmation ? 'Confirm password' : 'New password',
        hintText: confirmation ? 'Re-enter your password' : 'Create a password',
        prefixIcon: const Icon(Icons.lock_outline_rounded),
        suffixIcon: IconButton(
          tooltip: obscure ? 'Show password' : 'Hide password',
          onPressed: () => setState(() {
            if (confirmation) {
              _obscureConfirm = !_obscureConfirm;
            } else {
              _obscurePassword = !_obscurePassword;
            }
          }),
          icon: Icon(
            obscure
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
          ),
        ),
      ),
      onChanged: (_) {
        if (_error != null && mounted) setState(() => _error = null);
      },
    );
  }

  Widget _requirements() {
    final unmet = PasswordPolicy.unmetRequirements(_passwordController.text);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Password requirements',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: PasswordPolicy.requirementLabels.map((label) {
              final met = !unmet.contains(label);
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: met ? AppColors.surfaceLight : AppColors.canvasLight,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: met ? AppColors.border : AppColors.borderStrong,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      met ? Icons.check_circle_outline : Icons.circle_outlined,
                      size: 15,
                      color: met ? AppColors.success : AppColors.textSecondary,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      label,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _errorBanner() {
    final message = _error;
    if (message == null || message.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.error),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_checkingCode) {
      return Column(
        children: [
          _statusIcon(Icons.lock_clock_outlined, AppColors.primary),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Verifying secure link',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          const Text(
            'Please wait while we verify your account setup link.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.lg),
          const CircularProgressIndicator(),
        ],
      );
    }

    if (_completed) {
      return Column(
        children: [
          _statusIcon(Icons.check_rounded, AppColors.success),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Your password is set',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Your AI-DSUHIS account is ready. Sign in with ${_email ?? 'your registered email'} to open the Doctor Portal.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _goToLogin,
              icon: const Icon(Icons.login_rounded),
              label: const Text('Go to sign in'),
            ),
          ),
        ],
      );
    }

    if (_error != null && _email == null) {
      return Column(
        children: [
          _statusIcon(Icons.link_off_rounded, AppColors.error),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Secure link unavailable',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Request a new account setup link or contact the City Health Office administrator.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _errorBanner(),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _goToLogin,
              icon: const Icon(Icons.arrow_back_rounded),
              label: const Text('Return to sign in'),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Set up your account',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Create a secure password to activate your AI-DSUHIS access.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: AppColors.textSecondary,
            height: 1.5,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surfaceSubtle,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              const Icon(Icons.mail_outline_rounded, color: AppColors.secondary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Registered email',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _email ?? '',
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _buildPasswordField(confirmation: false),
        const SizedBox(height: AppSpacing.md),
        _buildPasswordField(confirmation: true),
        const SizedBox(height: AppSpacing.md),
        _requirements(),
        const SizedBox(height: AppSpacing.md),
        _errorBanner(),
        const SizedBox(height: AppSpacing.lg),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _submitting ? null : _savePassword,
            icon: _submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.lock_open_rounded),
            label: Text(_submitting ? 'Saving password…' : 'Activate account'),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.light(isWeb: true),
      child: Scaffold(
        backgroundColor: AppColors.backgroundLight,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final horizontalPadding = constraints.maxWidth < 520 ? 16.0 : 24.0;
              return SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: horizontalPadding,
                  vertical: constraints.maxWidth < 520 ? 20 : 40,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 500),
                    child: Card(
                      margin: EdgeInsets.zero,
                      elevation: 0,
                      color: AppColors.surfaceLight,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                        side: const BorderSide(color: AppColors.border),
                      ),
                      child: Padding(
                        padding: EdgeInsets.all(
                          constraints.maxWidth < 520 ? 20 : 28,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _header(),
                            const SizedBox(height: AppSpacing.lg),
                            const Divider(height: 1, color: AppColors.border),
                            const SizedBox(height: AppSpacing.lg),
                            _buildContent(),
                            const SizedBox(height: AppSpacing.xl),
                            Center(
                              child: Text(
                                'AI-DSUHIS • City Health Office Portal',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: AppColors.textSecondary),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
