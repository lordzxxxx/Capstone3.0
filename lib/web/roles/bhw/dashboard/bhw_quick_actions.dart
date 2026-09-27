import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:mycapstone_project/firebase_helper.dart';
import 'package:mycapstone_project/web/shared/theme/app_theme.dart';

const int bhwQuickActionLimit = 6;

class BhwQuickActionDefinition {
  const BhwQuickActionDefinition({
    required this.id,
    required this.label,
    required this.description,
    required this.icon,
    required this.requiredPermission,
  });

  final String id;
  final String label;
  final String description;
  final IconData icon;
  final String requiredPermission;
}

const List<BhwQuickActionDefinition> bhwQuickActionCatalog = [
  BhwQuickActionDefinition(
    id: 'add_patient',
    label: 'Add Patient',
    description: 'Register a patient',
    icon: Icons.person_add_alt_1_rounded,
    requiredPermission: 'patients.create',
  ),
  BhwQuickActionDefinition(
    id: 'add_checkup',
    label: 'Add Checkup',
    description: 'Record a consultation',
    icon: Icons.medical_services_outlined,
    requiredPermission: 'checkups.create',
  ),
  BhwQuickActionDefinition(
    id: 'summary_generation',
    label: 'Summary Generation',
    description: 'Create a health summary',
    icon: Icons.auto_graph_rounded,
    requiredPermission: 'reports.view',
  ),
  BhwQuickActionDefinition(
    id: 'analytics',
    label: 'Analytics',
    description: 'Review barangay insights',
    icon: Icons.insights_rounded,
    requiredPermission: 'reports.view',
  ),
  BhwQuickActionDefinition(
    id: 'prenatal',
    label: 'Prenatal',
    description: 'Open prenatal care',
    icon: Icons.pregnant_woman_rounded,
    requiredPermission: 'prenatal.create',
  ),
  BhwQuickActionDefinition(
    id: 'immunization',
    label: 'Immunization',
    description: 'Record vaccine services',
    icon: Icons.vaccines_outlined,
    requiredPermission: 'immunization.create',
  ),
  BhwQuickActionDefinition(
    id: 'communicable_diseases',
    label: 'Communicable Diseases',
    description: 'Monitor infectious cases',
    icon: Icons.coronavirus_outlined,
    requiredPermission: 'surveillance.view',
  ),
  BhwQuickActionDefinition(
    id: 'non_communicable_diseases',
    label: 'Non-Communicable Diseases',
    description: 'Monitor chronic conditions',
    icon: Icons.health_and_safety_outlined,
    requiredPermission: 'surveillance.view',
  ),
  BhwQuickActionDefinition(
    id: 'morbidity',
    label: 'Morbidity',
    description: 'Open morbidity records',
    icon: Icons.monitor_heart_outlined,
    requiredPermission: 'surveillance.view',
  ),
  BhwQuickActionDefinition(
    id: 'mortality',
    label: 'Mortality',
    description: 'Open mortality records',
    icon: Icons.heart_broken_outlined,
    requiredPermission: 'surveillance.view',
  ),
  BhwQuickActionDefinition(
    id: 'referrals',
    label: 'Referrals',
    description: 'Create or track referrals',
    icon: Icons.outbound_outlined,
    requiredPermission: 'referrals.create',
  ),
];

const List<String> defaultBhwQuickActionIds = [
  'add_patient',
  'add_checkup',
  'summary_generation',
  'analytics',
  'prenatal',
  'immunization',
];

class BhwQuickActionsService {
  BhwQuickActionsService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore,
      _auth = auth;

  final FirebaseFirestore? _firestore;
  final FirebaseAuth? _auth;

  FirebaseFirestore get _db => _firestore ?? getFirestoreInstance();
  FirebaseAuth get _firebaseAuth => _auth ?? FirebaseAuth.instance;

  static Set<String> get validIds =>
      bhwQuickActionCatalog.map((definition) => definition.id).toSet();

  static List<String> sanitizeIds(Object? value) {
    if (value is! List) return const [];
    final sanitized = <String>[];
    for (final item in value) {
      if (item is! String ||
          !validIds.contains(item) ||
          sanitized.contains(item)) {
        continue;
      }
      sanitized.add(item);
      if (sanitized.length == bhwQuickActionLimit) break;
    }
    return sanitized;
  }

  Future<List<String>> load() async {
    final user = _firebaseAuth.currentUser;
    if (user == null) throw StateError('Sign in to load Quick Actions.');
    final snapshot = await _db.collection('users').doc(user.uid).get();
    if (!snapshot.exists) {
      throw StateError('Your BHW profile could not be found.');
    }
    final saved = sanitizeIds(snapshot.data()?['bhwQuickActions']);
    return saved.isEmpty ? defaultBhwQuickActionIds : saved;
  }

  Future<void> save(List<String> actionIds) async {
    final user = _firebaseAuth.currentUser;
    if (user == null) throw StateError('Sign in to save Quick Actions.');
    final sanitized = sanitizeIds(actionIds);
    if (sanitized.isEmpty || sanitized.length != actionIds.length) {
      throw ArgumentError('Select between 1 and 6 unique Quick Actions.');
    }
    await _db.collection('users').doc(user.uid).update({
      'bhwQuickActions': sanitized,
      'bhwQuickActionsUpdatedAt': FieldValue.serverTimestamp(),
    });
  }
}

class BhwQuickActionsSection extends StatelessWidget {
  const BhwQuickActionsSection({
    super.key,
    required this.actionIds,
    required this.onAction,
    required this.onEdit,
    required this.isLoading,
    this.errorMessage,
    this.onRetry,
  });

  final List<String> actionIds;
  final ValueChanged<BhwQuickActionDefinition> onAction;
  final VoidCallback onEdit;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final definitionsById = {
      for (final definition in bhwQuickActionCatalog) definition.id: definition,
    };
    final selected = actionIds
        .map((id) => definitionsById[id])
        .whereType<BhwQuickActionDefinition>()
        .take(bhwQuickActionLimit)
        .toList(growable: false);

    return Semantics(
      container: true,
      label: 'Quick Actions',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.15)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0F071A33),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _QuickActionsHeader(onEdit: onEdit),
            const SizedBox(height: 16),
            if (errorMessage != null)
              _QuickActionsError(message: errorMessage!, onRetry: onRetry)
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 840
                      ? 3
                      : constraints.maxWidth >= 520
                      ? 2
                      : 1;
                  const spacing = 12.0;
                  final cardWidth =
                      (constraints.maxWidth - (spacing * (columns - 1))) /
                      columns;
                  return Wrap(
                    spacing: spacing,
                    runSpacing: spacing,
                    children: List<Widget>.generate(bhwQuickActionLimit, (
                      index,
                    ) {
                      final definition = index < selected.length
                          ? selected[index]
                          : null;
                      return SizedBox(
                        width: cardWidth,
                        height: 112,
                        child: isLoading
                            ? const _QuickActionLoadingCard()
                            : _QuickActionCard(
                                definition: definition,
                                position: index + 1,
                                onTap: definition == null
                                    ? onEdit
                                    : () => onAction(definition),
                              ),
                      );
                    }),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _QuickActionsHeader extends StatelessWidget {
  const _QuickActionsHeader({required this.onEdit});

  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final title = Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.bolt_rounded, color: AppColors.primary),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Quick Actions',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: 3),
              Text(
                'Keep your most-used BHW functions one tap away.',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
    final editButton = OutlinedButton.icon(
      onPressed: onEdit,
      icon: const Icon(Icons.edit_outlined, size: 18),
      label: const Text('Edit Quick Actions'),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(44, 44),
        foregroundColor: AppColors.primary,
        side: BorderSide(color: AppColors.primary.withValues(alpha: 0.35)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 520) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [title, const SizedBox(height: 12), editButton],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: title),
            const SizedBox(width: 12),
            editButton,
          ],
        );
      },
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.definition,
    required this.position,
    required this.onTap,
  });

  final BhwQuickActionDefinition? definition;
  final int position;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final item = definition;
    return Semantics(
      key: ValueKey('bhw-quick-action-slot-$position'),
      button: true,
      label: item == null
          ? 'Choose Quick Action for slot $position'
          : '${item.label}. ${item.description}',
      child: Material(
        color: item == null
            ? AppColors.surfaceSubtle
            : AppColors.primary.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          focusColor: AppColors.primary.withValues(alpha: 0.12),
          hoverColor: AppColors.primary.withValues(alpha: 0.08),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: item == null
                    ? AppColors.border
                    : AppColors.primary.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: item == null
                        ? AppColors.surfaceLight
                        : AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    item?.icon ?? Icons.add_rounded,
                    color: item == null
                        ? AppColors.textSecondary
                        : AppColors.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item?.label ?? 'Choose action',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        item?.description ?? 'Customize this shortcut',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: AppColors.textSecondary,
                  size: 14,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickActionLoadingCard extends StatelessWidget {
  const _QuickActionLoadingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.2),
        ),
      ),
    );
  }
}

class _QuickActionsError extends StatelessWidget {
  const _QuickActionsError({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 10,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Text(
              message,
              style: const TextStyle(color: AppColors.textPrimary),
            ),
          ),
          if (onRetry != null)
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
        ],
      ),
    );
  }
}

Future<List<String>?> showBhwQuickActionsEditor({
  required BuildContext context,
  required List<String> selectedIds,
}) {
  return showDialog<List<String>>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _BhwQuickActionsEditor(selectedIds: selectedIds),
  );
}

class _BhwQuickActionsEditor extends StatefulWidget {
  const _BhwQuickActionsEditor({required this.selectedIds});

  final List<String> selectedIds;

  @override
  State<_BhwQuickActionsEditor> createState() => _BhwQuickActionsEditorState();
}

class _BhwQuickActionsEditorState extends State<_BhwQuickActionsEditor> {
  late final List<String> _selectedIds;

  @override
  void initState() {
    super.initState();
    _selectedIds = BhwQuickActionsService.sanitizeIds(widget.selectedIds);
  }

  void _toggle(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else if (_selectedIds.length < bhwQuickActionLimit) {
        _selectedIds.add(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: size.width < 600 ? 12 : 32,
        vertical: size.height < 700 ? 12 : 24,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820, maxHeight: 760),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 20, 14, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Edit Quick Actions',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 5),
                        Text(
                          'Select up to six functions. Your selection is saved only to your BHW account.',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Close Quick Actions editor',
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Row(
                children: [
                  Text(
                    '${_selectedIds.length} of $bhwQuickActionLimit selected',
                    style: TextStyle(
                      color: _selectedIds.length == bhwQuickActionLimit
                          ? AppColors.primary
                          : AppColors.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  if (_selectedIds.isNotEmpty)
                    TextButton(
                      onPressed: () => setState(_selectedIds.clear),
                      child: const Text('Clear'),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 680 ? 2 : 1;
                  const spacing = 10.0;
                  final width =
                      (constraints.maxWidth - 32 - spacing * (columns - 1)) /
                      columns;
                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Wrap(
                      spacing: spacing,
                      runSpacing: spacing,
                      children: bhwQuickActionCatalog
                          .map((definition) {
                            final selected = _selectedIds.contains(
                              definition.id,
                            );
                            final disabled =
                                !selected &&
                                _selectedIds.length >= bhwQuickActionLimit;
                            return SizedBox(
                              width: width,
                              child: _QuickActionChoice(
                                definition: definition,
                                selected: selected,
                                disabled: disabled,
                                order: selected
                                    ? _selectedIds.indexOf(definition.id) + 1
                                    : null,
                                onTap: disabled
                                    ? null
                                    : () => _toggle(definition.id),
                              ),
                            );
                          })
                          .toList(growable: false),
                    ),
                  );
                },
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: _selectedIds.isEmpty
                        ? null
                        : () => Navigator.of(
                            context,
                          ).pop(List<String>.unmodifiable(_selectedIds)),
                    icon: const Icon(Icons.save_outlined, size: 18),
                    label: const Text('Save Quick Actions'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(44, 44),
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActionChoice extends StatelessWidget {
  const _QuickActionChoice({
    required this.definition,
    required this.selected,
    required this.disabled,
    required this.order,
    required this.onTap,
  });

  final BhwQuickActionDefinition definition;
  final bool selected;
  final bool disabled;
  final int? order;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      checked: selected,
      enabled: !disabled,
      label: definition.label,
      child: Material(
        color: selected
            ? AppColors.primary.withValues(alpha: 0.08)
            : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            constraints: const BoxConstraints(minHeight: 76),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? AppColors.primary : AppColors.border,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  definition.icon,
                  color: disabled
                      ? AppColors.textSecondary.withValues(alpha: 0.45)
                      : AppColors.primary,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        definition.label,
                        style: TextStyle(
                          color: disabled
                              ? AppColors.textSecondary
                              : AppColors.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        definition.description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected ? AppColors.primary : Colors.transparent,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected ? AppColors.primary : AppColors.border,
                    ),
                  ),
                  child: selected
                      ? Text(
                          '$order',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
