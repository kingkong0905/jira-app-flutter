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
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppTheme.primary,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: AppTheme.textPrimary,
            ),
          ),
          child: child!,
        );
      },
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
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppTheme.primary,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: AppTheme.textPrimary,
            ),
          ),
          child: child!,
        );
      },
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
              padding: AppTheme.padding20,
              decoration: const BoxDecoration(
                color: AppTheme.surfaceMuted,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      AppLocalizations.of(context).createNewSprint,
                      style: const TextStyle(
                        fontSize: AppTheme.fontSizeXlMd,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: AppTheme.textSecondary),
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
                padding: AppTheme.padding20,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Sprint Name
                    Text(
                      AppLocalizations.of(context).sprintName,
                      style: TextStyle(
                        fontSize: AppTheme.fontSizeBase,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: AppTheme.heightLg),
                    TextField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        hintText: AppLocalizations.of(context).enterSprintName,
                        hintStyle: const TextStyle(color: AppTheme.hint),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: AppTheme.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: AppTheme.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: AppTheme.primary, width: AppTheme.widthXs),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                      enabled: !_creating,
                    ),
                    const SizedBox(height: AppTheme.heightXxxxl),

                    // Sprint Goal
                    Text(
                      AppLocalizations.of(context).goalOverview,
                      style: TextStyle(
                        fontSize: AppTheme.fontSizeBase,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: AppTheme.heightLg),
                    TextField(
                      controller: _goalController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: AppLocalizations.of(context).enterSprintGoal,
                        hintStyle: const TextStyle(color: AppTheme.hint),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: AppTheme.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: AppTheme.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: AppTheme.primary, width: AppTheme.widthXs),
                        ),
                        contentPadding: AppTheme.paddingMd,
                      ),
                      enabled: !_creating,
                    ),
                    const SizedBox(height: AppTheme.heightXxxxl),

                    // Start Date
                    Text(
                      AppLocalizations.of(context).startDate,
                      style: TextStyle(
                        fontSize: AppTheme.fontSizeBase,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: AppTheme.heightLg),
                    InkWell(
                      onTap: _creating ? null : _selectStartDate,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: AppTheme.paddingHorizontal12Vertical12,
                        decoration: BoxDecoration(
                          border: Border.all(color: AppTheme.border),
                          borderRadius: BorderRadius.circular(8),
                          color: _creating ? AppTheme.surfaceMuted : Colors.white,
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_today, size: 18, color: AppTheme.textSecondary),
                            const SizedBox(width: AppTheme.widthMd),
                            Text(
                              _formatDate(_startDate) ?? AppLocalizations.of(context).selectStartDate,
                              style: TextStyle(
                                fontSize: AppTheme.fontSizeBase,
                                color: _startDate != null ? AppTheme.textPrimary : AppTheme.hint,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: AppTheme.heightXxxxl),

                    // End Date
                    Text(
                      AppLocalizations.of(context).endDate,
                      style: TextStyle(
                        fontSize: AppTheme.fontSizeBase,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: AppTheme.heightLg),
                    InkWell(
                      onTap: _creating ? null : _selectEndDate,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: AppTheme.paddingHorizontal12Vertical12,
                        decoration: BoxDecoration(
                          border: Border.all(color: AppTheme.border),
                          borderRadius: BorderRadius.circular(8),
                          color: _creating ? AppTheme.surfaceMuted : Colors.white,
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_today, size: 18, color: AppTheme.textSecondary),
                            const SizedBox(width: AppTheme.widthMd),
                            Text(
                              _formatDate(_endDate) ?? AppLocalizations.of(context).selectEndDate,
                              style: TextStyle(
                                fontSize: AppTheme.fontSizeBase,
                                color: _endDate != null ? AppTheme.textPrimary : AppTheme.hint,
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
              padding: AppTheme.padding20,
              decoration: const BoxDecoration(
                color: AppTheme.surfaceMuted,
                borderRadius: BorderRadius.only(
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
                      padding: AppTheme.paddingHorizontal20Vertical12,
                    ),
                    child: Text(
                      AppLocalizations.of(context).cancel,
                      style: TextStyle(
                        fontSize: AppTheme.fontSizeBase,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppTheme.widthLg),
                  ElevatedButton(
                    onPressed: _creating ? null : _handleCreate,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      padding: AppTheme.paddingHorizontal24Vertical12,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: _creating
                        ? const SizedBox(
                            width: AppTheme.widthXl,
                            height: AppTheme.widthXl,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Text(
                            AppLocalizations.of(context).createSprintButton,
                            style: TextStyle(
                              fontSize: AppTheme.fontSizeBase,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
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
