import 'package:flutter/material.dart';
import 'package:mycapstone_project/shared/user_access_scope.dart';
import 'package:mycapstone_project/web/shared/models/doctor_note.dart';
import 'package:mycapstone_project/web/shared/services/doctor_notes_service.dart';
import 'package:mycapstone_project/web/shared/services/user_access_scope_service.dart';
import 'package:mycapstone_project/web/shared/theme/app_theme.dart';

/// One selectable entry in the check-up dropdown a note gets attached to.
class DoctorNoteCheckupOption {
  const DoctorNoteCheckupOption({required this.id, required this.label});

  final String id;
  final String label;
}

/// Reusable panel that shows the append-only doctor-note history for a
/// patient's check-up, and — for CHO/DOCTOR accounts only — lets the
/// current user add a new note. This is the continuity-of-care surface:
/// any authorized clinician who later treats the same patient sees every
/// note previous doctors left, not just their own.
class DoctorNotesSection extends StatefulWidget {
  const DoctorNotesSection({
    super.key,
    required this.patientId,
    required this.patientName,
    required this.patientBarangayCode,
    required this.checkupOptions,
  });

  final String patientId;
  final String patientName;
  final String patientBarangayCode;
  final List<DoctorNoteCheckupOption> checkupOptions;

  @override
  State<DoctorNotesSection> createState() => _DoctorNotesSectionState();
}

class _DoctorNotesSectionState extends State<DoctorNotesSection> {
  final _notesService = DoctorNotesService();
  final _noteController = TextEditingController();

  String? _selectedCheckupId;
  bool _isSubmitting = false;
  Future<UserAccessScope>? _scopeFuture;

  @override
  void initState() {
    super.initState();
    _selectedCheckupId = widget.checkupOptions.isNotEmpty
        ? widget.checkupOptions.first.id
        : null;
    _scopeFuture = UserAccessScopeService.instance.loadCurrentScope();
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  bool _roleCanAddNotes(String role) {
    final normalized = role.trim().toLowerCase();
    return normalized == 'doctor' ||
        normalized == 'cho' ||
        normalized == 'cho_super_admin' ||
        normalized == 'super_admin' ||
        normalized == 'admin';
  }

  Future<void> _submitNote() async {
    final checkupId = _selectedCheckupId;
    if (checkupId == null || checkupId.isEmpty) {
      return;
    }
    final text = _noteController.text.trim();
    if (text.isEmpty) {
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await _notesService.addNote(
        patientId: widget.patientId,
        patientName: widget.patientName,
        checkupId: checkupId,
        patientBarangayCode: widget.patientBarangayCode,
        note: text,
      );
      if (!mounted) return;
      _noteController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle_outline, color: Colors.white),
              SizedBox(width: 8),
              Expanded(child: Text('Doctor note saved successfully.')),
            ],
          ),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(child: Text('Unable to save note: $error')),
            ],
          ),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  String _twoDigits(int n) => n.toString().padLeft(2, '0');

  String _formatTimestamp(DateTime? value) {
    if (value == null) return 'Just now';
    final hour12 = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final period = value.hour >= 12 ? 'PM' : 'AM';
    return '${value.month}/${value.day}/${value.year} '
        '$hour12:${_twoDigits(value.minute)} $period';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.sticky_note_2_outlined,
                color: AppColors.textPrimary,
                size: 20,
              ),
              SizedBox(width: 8),
              Text(
                'Doctor Notes',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Continuity-of-care notes for this patient\'s check-ups. '
            'Notes cannot be edited or deleted once saved.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
          ),
          const SizedBox(height: 14),
          if (widget.checkupOptions.isEmpty)
            const Text(
              'No check-up records yet. A note can be added once a '
              'check-up has been recorded for this patient.',
              style: TextStyle(color: AppColors.textSecondary),
            )
          else ...[
            if (widget.checkupOptions.length > 1) ...[
              DropdownButtonFormField<String>(
                initialValue: _selectedCheckupId,
                dropdownColor: AppColors.surfaceLight,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: const InputDecoration(
                  labelText: 'Check-up',
                  labelStyle: TextStyle(color: AppColors.textSecondary),
                  isDense: true,
                ),
                items: widget.checkupOptions
                    .map(
                      (option) => DropdownMenuItem(
                        value: option.id,
                        child: Text(
                          option.label,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) =>
                    setState(() => _selectedCheckupId = value),
              ),
              const SizedBox(height: 12),
            ],
            StreamBuilder<List<DoctorNote>>(
              stream: _notesService.watchNotesForCheckup(
                _selectedCheckupId ?? '',
              ),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                      ),
                    ),
                  );
                }
                if (snapshot.hasError) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Icon(
                          Icons.error_outline,
                          color: AppColors.textSecondary,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Unable to load doctor notes.',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        ),
                      ],
                    ),
                  );
                }
                final notes = snapshot.data ?? const <DoctorNote>[];
                if (notes.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'No previous doctor notes for this check-up.',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  );
                }
                return Column(
                  children: notes
                      .map(
                        (note) => Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.backgroundLight,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppColors.primary.withValues(alpha: 0.18),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.person_outline,
                                    size: 14,
                                    color: AppColors.primary,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      note.authorName.isEmpty
                                          ? 'Unknown author'
                                          : note.authorName,
                                      style: const TextStyle(
                                        color: AppColors.textPrimary,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12.5,
                                      ),
                                    ),
                                  ),
                                  if (note.authorRole.isNotEmpty)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppColors.primary.withValues(
                                          alpha: 0.16,
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        note.authorRole.toUpperCase(),
                                        style: const TextStyle(
                                          color: AppColors.primary,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                note.note,
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 12.5,
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _formatTimestamp(note.createdAt),
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 10.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                );
              },
            ),
            const SizedBox(height: 8),
            FutureBuilder<UserAccessScope>(
              future: _scopeFuture,
              builder: (context, snapshot) {
                final role = snapshot.data?.role ?? '';
                if (!_roleCanAddNotes(role)) {
                  return const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 14,
                          color: AppColors.textSecondary,
                        ),
                        SizedBox(width: 6),
                        Text(
                          'Only doctors and CHO staff can add notes.',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _noteController,
                      minLines: 2,
                      maxLines: 4,
                      style: const TextStyle(color: AppColors.textPrimary),
                      decoration: InputDecoration(
                        hintText: 'Add a note for the next attending doctor…',
                        hintStyle: const TextStyle(
                          color: AppColors.textSecondary,
                        ),
                        filled: true,
                        fillColor: AppColors.backgroundLight,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        onPressed: _isSubmitting ? null : _submitNote,
                        icon: _isSubmitting
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.add_comment_outlined, size: 16),
                        label: const Text('Add Note'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}
