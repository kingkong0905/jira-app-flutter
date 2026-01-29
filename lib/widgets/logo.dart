import 'package:flutter/material.dart';

/// Branded "Jira Management" logo (same concept as reference app).
class Logo extends StatelessWidget {
  const Logo({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Center(
            child: Text('✓', style: TextStyle(fontSize: 36, color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Jira Management',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            letterSpacing: 0.3,
          ),
        ),
        Text(
          'Task Manager',
          style: TextStyle(
            fontSize: 13,
            color: Colors.white.withValues(alpha: 0.85),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
