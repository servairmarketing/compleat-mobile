import 'package:flutter/material.dart';
import '../brand.dart';

/// Shared action bar for screens that save an entry and can *optionally* print
/// a label for it. Replaces the old single "Save + Print" buttons so that
/// saving and printing are independent actions:
///
///   [ Save (primary) ]
///   [ Print ]  [ Clear ]
///
/// Print is enabled only once there is something saved to print ([canPrint]),
/// and it stays enabled after a save so the operator can retry printing once
/// they're back on the warehouse network. A failed print never blocks or
/// undoes the save — the caller handles the two results separately.
class SavePrintClearBar extends StatelessWidget {
  final VoidCallback? onSave;
  final bool saving;
  final String saveLabel;
  final String savingLabel;
  final IconData saveIcon;

  final VoidCallback? onPrint;
  final bool printing;

  /// Whether there is a saved entry whose label can be printed. When false the
  /// Print button is disabled (nothing to print yet).
  final bool canPrint;
  final String printLabel;

  final VoidCallback? onClear;

  /// Optional key forwarded to the Save button (preserves existing widget keys
  /// used by tests/automation).
  final Key? saveButtonKey;

  const SavePrintClearBar({
    super.key,
    required this.onSave,
    required this.saving,
    required this.saveLabel,
    this.savingLabel = 'Saving...',
    this.saveIcon = Icons.add_box,
    required this.onPrint,
    required this.printing,
    required this.canPrint,
    this.printLabel = 'Print Label',
    required this.onClear,
    this.saveButtonKey,
  });

  @override
  Widget build(BuildContext context) {
    final printEnabled = canPrint && !printing && !saving;
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton.icon(
            key: saveButtonKey,
            onPressed: saving ? null : onSave,
            icon: saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : Icon(saveIcon, size: 24),
            label: Text(saving ? savingLabel : saveLabel,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
                backgroundColor: kBrandColor,
                foregroundColor: Colors.white),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  key: const Key('printLabelButton'),
                  onPressed: printEnabled ? onPrint : null,
                  icon: printing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.print, size: 22),
                  label: Text(printing ? 'Printing...' : printLabel,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFef6c00),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(0xFFE0E0E0),
                      disabledForegroundColor: const Color(0xFF9E9E9E)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SizedBox(
                height: 52,
                child: OutlinedButton(
                  key: const Key('clearButton'),
                  onPressed: (saving || printing) ? null : onClear,
                  child: const Text('Clear', style: TextStyle(fontSize: 16)),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
