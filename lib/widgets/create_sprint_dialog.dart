import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../l10n/app_localizations.dart';

class CreateSprintDialog extends StatefulWidget {
  final Function(String name, String goal, DateTime? startDate, DateTime? endDate) onCreate;

  const CreateSprintDialog({
    super.key,
    required this.onCreate,
  });

  @override
  State<CreateSprintDialog> createState() => _CreateSprintDialogState();
}

class _CreateSprintDialogState extends State<CreateSprintDialog> {
  final _nameController = TextEditingController();
  final _goalController = TextEditingController();
  DateTime? _startDate;
  DateTime? _endDate;
  bool _creating = false;

  @override
  void dispose() {
    _nameController.dispose();
    _goalController.dispose();
    super.dispose();
  }

  Future<void> _selectStartDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (context, child) => child!,
    );
    if (picked != null) {
      setState(() => _startDate = picked);
    }
  }

  Future<void> _selectEndDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? (_startDate ?? DateTime.now()).add(const Duration(days: 14)),
      firstDate: _startDate ?? DateTime(2020),
      lastDate: DateTime(2030),
      builder: (context, child) => child!,
    );
    if (picked != null) {
      setState(() => _endDate = picked);
    }
  }

  Future<void> _handleCreate() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).sprintNameRequired),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }

    if (_startDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).startDateRequired),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }

    if (_endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).endDateRequired),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }

    if (_endDate!.isBefore(_startDate!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).endDateAfterStart),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }

    setState(() => _creating = true);
    widget.onCreate(
      _nameController.text.trim(),
      _goalController.text.trim(),
      _startDate,
      _endDate,
    );
  }

  String? _formatDate(DateTime? date) {
    if (date == null) return null;
    return DateFormat('MMM dd, yyyy').format(date);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      AppLocalizations.of(context).createNewSprint,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: colorScheme.onSurfaceVariant),
                    onPressed: _creating ? null : () => Navigator.of(context).pop(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
            // Body
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Sprint Name
                    Text(
                      AppLocalizations.of(context).sprintName,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        hintText: AppLocalizations.of(context).enterSprintName,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: colorScheme.outline),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: colorScheme.outline),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: colorScheme.primary, width: 2),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                      enabled: !_creating,
                    ),
                    const SizedBox(height: 20),

                    // Sprint Goal
                    Text(
                      AppLocalizations.of(context).goalOverview,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _goalController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: AppLocalizations.of(context).enterSprintGoal,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: colorScheme.outline),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: colorScheme.outline),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: colorScheme.primary, width: 2),
                        ),
                        contentPadding: const EdgeInsets.all(12),
                      ),
                      enabled: !_creating,
                    ),
                    const SizedBox(height: 20),

                    // Start Date
                    Text(
                      AppLocalizations.of(context).startDate,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: _creating ? null : _selectStartDate,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: colorScheme.outline),
                          borderRadius: BorderRadius.circular(8),
                          color: _creating ? colorScheme.surfaceContainerHighest : colorScheme.surface,
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.calendar_today, size: 18, color: colorScheme.onSurfaceVariant),
                            const SizedBox(width: 8),
                            Text(
                              _formatDate(_startDate) ?? AppLocalizations.of(context).selectStartDate,
                              style: TextStyle(
                                fontSize: 14,
                                color: _startDate != null ? colorScheme.onSurface : colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // End Date
                    Text(
                      AppLocalizations.of(context).endDate,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: _creating ? null : _selectEndDate,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: colorScheme.outline),
                          borderRadius: BorderRadius.circular(8),
                          color: _creating ? colorScheme.surfaceContainerHighest : colorScheme.surface,
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.calendar_today, size: 18, color: colorScheme.onSurfaceVariant),
                            const SizedBox(width: 8),
                            Text(
                              _formatDate(_endDate) ?? AppLocalizations.of(context).selectEndDate,
                              style: TextStyle(
                                fontSize: 14,
                                color: _endDate != null ? colorScheme.onSurface : colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Footer
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _creating ? null : () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                    child: Text(
                      AppLocalizations.of(context).cancel,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _creating ? null : _handleCreate,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colorScheme.primary,
                      foregroundColor: colorScheme.onPrimary,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: _creating
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(colorScheme.onPrimary),
                            ),
                          )
                        : Text(
                            AppLocalizations.of(context).createSprintButton,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onPrimary,
                            ),
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
