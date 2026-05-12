import 'package:flutter/material.dart';

Future<void> showValidationDialog(BuildContext context, List<String> issues, {String title = 'Cannot submit'}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: Text(title, style: const TextStyle(color: Color(0xFFc62828), fontWeight: FontWeight.bold)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: issues
              .map((i) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('• ', style: TextStyle(fontSize: 16)),
                        Expanded(child: Text(i, style: const TextStyle(fontSize: 15))),
                      ],
                    ),
                  ))
              .toList(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('OK', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ),
      ],
    ),
  );
}
