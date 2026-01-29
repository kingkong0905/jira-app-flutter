import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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
              primary: Color(0xFF0052CC),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Color(0xFF172B4D),
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
              primary: Color(0xFF0052CC),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Color(0xFF172B4D),
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
        const SnackBar(
          content: Text('Sprint name is required'),
          backgroundColor: Color(0xFFDE350B),
        ),
      );
      return;
    }

    if (_startDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Start date is required'),
          backgroundColor: Color(0xFFDE350B),
        ),
      );
      return;
    }

    if (_endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('End date is required'),
          backgroundColor: Color(0xFFDE350B),
        ),
      );
      return;
    }

    if (_endDate!.isBefore(_startDate!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('End date must be after start date'),
          backgroundColor: Color(0xFFDE350B),
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
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Color(0xFFF4F5F7),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Create New Sprint',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF172B4D),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Color(0xFF42526E)),
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
                    const Text(
                      'Sprint Name *',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF172B4D),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        hintText: 'Enter sprint name',
                        hintStyle: const TextStyle(color: Color(0xFF9FA6B2)),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Color(0xFFDFE1E6)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Color(0xFFDFE1E6)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Color(0xFF0052CC), width: 2),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                      enabled: !_creating,
                    ),
                    const SizedBox(height: 20),

                    // Sprint Goal
                    const Text(
                      'Goal (Overview)',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF172B4D),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _goalController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: 'Enter sprint goal',
                        hintStyle: const TextStyle(color: Color(0xFF9FA6B2)),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Color(0xFFDFE1E6)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Color(0xFFDFE1E6)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Color(0xFF0052CC), width: 2),
                        ),
                        contentPadding: const EdgeInsets.all(12),
                      ),
                      enabled: !_creating,
                    ),
                    const SizedBox(height: 20),

                    // Start Date
                    const Text(
                      'Start Date *',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF172B4D),
                      ),
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: _creating ? null : _selectStartDate,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFFDFE1E6)),
                          borderRadius: BorderRadius.circular(8),
                          color: _creating ? const Color(0xFFF4F5F7) : Colors.white,
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_today, size: 18, color: Color(0xFF42526E)),
                            const SizedBox(width: 8),
                            Text(
                              _formatDate(_startDate) ?? 'Select start date',
                              style: TextStyle(
                                fontSize: 14,
                                color: _startDate != null ? const Color(0xFF172B4D) : const Color(0xFF9FA6B2),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // End Date
                    const Text(
                      'End Date *',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF172B4D),
                      ),
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: _creating ? null : _selectEndDate,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFFDFE1E6)),
                          borderRadius: BorderRadius.circular(8),
                          color: _creating ? const Color(0xFFF4F5F7) : Colors.white,
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_today, size: 18, color: Color(0xFF42526E)),
                            const SizedBox(width: 8),
                            Text(
                              _formatDate(_endDate) ?? 'Select end date',
                              style: TextStyle(
                                fontSize: 14,
                                color: _endDate != null ? const Color(0xFF172B4D) : const Color(0xFF9FA6B2),
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
              decoration: const BoxDecoration(
                color: Color(0xFFF4F5F7),
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
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF42526E),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _creating ? null : _handleCreate,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0052CC),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: _creating
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Text(
                            'Create Sprint',
                            style: TextStyle(
                              fontSize: 14,
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
