import 'package:flutter/material.dart';
import 'package:dropdown_search/dropdown_search.dart';

/// Bug #11 — field auto-advance timing + keep-previous-visible.
///
/// The old pattern advanced focus (and auto-opened the next dropdown)
/// instantly on scan/Enter, so the just-completed field was immediately
/// hidden behind the new dropdown overlay / rising keyboard before the
/// operator could visually confirm what they entered.
///
/// [advance] introduces a short, barely-perceptible delay before moving
/// focus, then — once the new field is focused — scrolls so the newly
/// focused field sits ~30% down the viewport, which keeps the
/// previously-completed field visible just above it.
///
/// This is shared so every transaction screen advances identically.
class FieldFocus {
  FieldFocus._();

  /// Delay before auto-advance fires. Long enough for visual confirmation,
  /// short enough not to slow a fast operator.
  static const Duration advanceDelay = Duration(milliseconds: 250);

  /// Move focus to [target] after [advanceDelay]. Optionally open a
  /// DropdownSearch popup ([openDropdown]) once focused, and scroll so the
  /// target — and the field just above it — stay visible.
  static void advance(
    BuildContext context, {
    required FocusNode target,
    GlobalKey<DropdownSearchState<String>>? openDropdown,
  }) {
    Future.delayed(advanceDelay, () {
      if (!context.mounted) return;
      target.requestFocus();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        openDropdown?.currentState?.openDropDownSearch();
        final tctx = target.context;
        if (tctx != null) {
          // Bug #18 — alignment 0.5 sits the new field at mid-viewport, so
          // its auto-opened dropdown (which renders below it, capped at ~40%
          // of viewport height — see each DropdownSearch's constraints) fills
          // the lower half and the previously-completed field's VALUE stays
          // visible in the upper half.
          Scrollable.ensureVisible(
            tctx,
            alignment: 0.5,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    });
  }
}
