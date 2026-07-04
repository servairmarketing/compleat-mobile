import 'package:flutter/material.dart';

/// §2.16 — a persistent, actionable data-load error with a Retry button.
///
/// Mirrors the sales customer-picker error card (sales_screen.dart) so every
/// failed data load looks and behaves the same: a red banner with the message
/// and a Retry that re-runs the load — never a silently-empty dropdown/list.
/// Show this only when a load actually FAILED (ApiService.get returned
/// {'error': ...} or the expected key was absent), distinct from a genuinely
/// empty result.
class LoadErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final EdgeInsetsGeometry margin;

  const LoadErrorCard({
    super.key,
    required this.message,
    required this.onRetry,
    this.margin = const EdgeInsets.only(bottom: 12),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: margin,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red[50],
        border: Border.all(color: Colors.red[200]!),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text('⚠ $message',
                style: TextStyle(color: Colors.red[800])),
          ),
          const SizedBox(width: 8),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
