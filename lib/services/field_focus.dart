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

  /// Bug #30 — viewport alignment for a field that is about to show a
  /// dropdown. 0.2 places the field ~20% from the top so the popup (capped at
  /// 40% of viewport height) has room to open BELOW it, even with the keyboard
  /// occupying the lower part of the screen. Previously 0.5 (mid-viewport),
  /// which left no room below once the keyboard was up and the popup opened
  /// upward over earlier fields.
  static const double dropdownFieldAlignment = 0.2;

  static const Duration _scrollDuration = Duration(milliseconds: 200);

  /// Move focus to [target] after [advanceDelay]. Optionally open a
  /// DropdownSearch popup ([openDropdown]) once focused. The target field is
  /// scrolled to [dropdownFieldAlignment] FIRST; the dropdown is opened only
  /// after that scroll settles, so the popup anchors at the field's new
  /// (higher) position and opens downward.
  static void advance(
    BuildContext context, {
    required FocusNode target,
    GlobalKey<DropdownSearchState<String>>? openDropdown,
  }) {
    Future.delayed(advanceDelay, () {
      if (!context.mounted) return;
      target.requestFocus();
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!context.mounted) return;
        final tctx = target.context;
        if (tctx != null) {
          await Scrollable.ensureVisible(
            tctx,
            alignment: dropdownFieldAlignment,
            duration: _scrollDuration,
            curve: Curves.easeOut,
          );
        }
        if (!context.mounted) return;
        // Open AFTER the scroll completes. DropdownSearch.onBeforePopupOpening
        // (see ensureRoomForDropdown) also re-checks room as a safety net for
        // dropdowns opened by a direct tap rather than through advance().
        openDropdown?.currentState?.openDropDownSearch();
      });
    });
  }

  /// Bug #30 — wired into every DropdownSearch via
  /// `DropdownSearch.onBeforePopupOpening`. Scrolls the dropdown's own field
  /// ([context]) to [dropdownFieldAlignment] BEFORE the popup is positioned,
  /// so it always opens BELOW the field, never upward over earlier fields.
  /// Always returns true so the popup still opens.
  static Future<bool> ensureRoomForDropdown(BuildContext? context) async {
    if (context != null && context.mounted) {
      await Scrollable.ensureVisible(
        context,
        alignment: dropdownFieldAlignment,
        duration: _scrollDuration,
        curve: Curves.easeOut,
      );
    }
    return true;
  }
}
