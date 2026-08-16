import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mycapstone_project/shared/user_access_scope.dart';
import 'package:mycapstone_project/web/shared/navigation/web_routes.dart';
import 'package:mycapstone_project/web/shared/services/user_access_scope_service.dart';
import 'package:mycapstone_project/web/shared/theme/app_theme.dart';

/// Keeps role-specific web routes consistent when a user enters a URL directly.
///
/// Firebase authentication protects the route from anonymous access, while
/// this gate applies the already-established Firestore access scope before the
/// role page is built. It is a client-side UX boundary; Firestore rules and
/// service-level checks remain the authorization boundary.
class WebRoleGate extends StatefulWidget {
  const WebRoleGate({
    super.key,
    required this.allowedRoles,
    required this.child,
    this.fallbackRoute = WebRoutes.landing,
  });

  final Set<String> allowedRoles;
  final Widget child;
  final String fallbackRoute;

  static String normalizeRole(Object? role) =>
      role?.toString().trim().toLowerCase() ?? '';

  static bool isAllowed(String role, Set<String> roles) =>
      roles.contains(normalizeRole(role));

  @override
  State<WebRoleGate> createState() => _WebRoleGateState();
}

class _WebRoleGateState extends State<WebRoleGate> {
  late Future<UserAccessScope?> _scopeFuture;

  @override
  void initState() {
    super.initState();
    _scopeFuture = _loadScope();
  }

  Future<UserAccessScope?> _loadScope() {
    return UserAccessScopeService.instance.loadCurrentScope().timeout(
      const Duration(seconds: 15),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<UserAccessScope?>(
      future: _scopeFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _WebRoleState(
            icon: Icons.verified_user_outlined,
            title: 'Checking portal access',
            message: 'Verifying your role before opening this workspace.',
          );
        }

        final scope = snapshot.data;
        final role = scope?.role ?? '';
        if (snapshot.hasError ||
            scope == null ||
            !WebRoleGate.isAllowed(role, widget.allowedRoles)) {
          return _WebRoleState(
            icon: Icons.lock_outline,
            title: 'Workspace unavailable',
            message: snapshot.hasError
                ? 'We could not verify your portal access. Please try again.'
                : 'Your account does not have permission to open this workspace.',
            actionLabel: snapshot.hasError ? 'Try again' : 'Return to portal',
            onAction: () {
              if (snapshot.hasError) {
                setState(() {
                  _scopeFuture = _loadScope();
                });
                return;
              }
              Get.offAllNamed(widget.fallbackRoute);
            },
          );
        }

        return widget.child;
      },
    );
  }
}

class _WebRoleState extends StatelessWidget {
  const _WebRoleState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: AppColors.primary, size: 44),
                const SizedBox(height: AppSpacing.md),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                if (actionLabel != null && onAction != null) ...[
                  const SizedBox(height: AppSpacing.lg),
                  FilledButton(
                    onPressed: onAction,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                    ),
                    child: Text(actionLabel!),
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
