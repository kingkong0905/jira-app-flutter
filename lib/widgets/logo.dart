import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../l10n/app_localizations.dart';

/// Branded logo using [AppTheme.appName].
class Logo extends StatelessWidget {
  const Logo({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: AppTheme.height64,
          height: AppTheme.height64,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Center(
            child: Text('✓', style: TextStyle(fontSize: AppTheme.fontSizeXxxlXxl, color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(height: AppTheme.heightXxl),
        const Text(
          AppTheme.appName,
          style: TextStyle(
            fontSize: AppTheme.fontSizeXxl,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            letterSpacing: 0.3,
          ),
        ),
        Text(
          AppLocalizations.of(context).taskManager,
          style: TextStyle(
            fontSize: AppTheme.fontSizeMd,
            color: Colors.white.withValues(alpha: 0.85),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
