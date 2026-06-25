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

  /// Bug #30 (revised) — cap on how long [ensureRoomForDropdown] waits for the
  /// keyboard-dismiss animation + layout reflow to settle before it positions
  /// the popup anyway. Long enough for a typical soft-keyboard dismiss,
  /// bounded so a device that never reports a zero inset cannot stall the UI.
  static const Duration _keyboardDismissMaxWait = Duration(milliseconds: 400);

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

  /// §2.3 — inline validation banners MUST be scrolled into view.
  ///
  /// When a validation error (or any inline banner) is rendered at the TOP of a
  /// scrollable form, the operator has usually scrolled past it — they are down
  /// at the Submit button when validation fails — so the banner appears
  /// off-screen ABOVE the current position and the action looks like it
  /// silently did nothing. After showing the banner, call this with a
  /// [GlobalKey] attached to the banner widget to scroll it back into view
  /// (aligned to the top of the viewport).
  ///
  /// Safe to call inside the same `setState` turn that sets the message: the
  /// scroll runs in a post-frame callback, after the banner has been laid out.
  /// No-ops if the banner is not currently mounted.
  static void revealBanner(GlobalKey bannerKey) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = bannerKey.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.0,
        duration: _scrollDuration,
        curve: Curves.easeOut,
      );
    });
  }

  /// Bug #30 (revised) — wired into every DropdownSearch via
  /// `DropdownSearch.onBeforePopupOpening`, which `_selectSearchMode` AWAITS
  /// before it positions and opens the popup. That await is the whole fix:
  ///
  ///  1. The keyboard may still be up when the field is tapped. If the popup
  ///     were positioned now, the keyboard would then dismiss, the layout
  ///     would reflow, the field would shift up — and the already-anchored
  ///     popup would end up covering / misaligned with the field.
  ///  2. So dismiss the keyboard FIRST, then wait until the dismiss animation
  ///     and the layout reflow it triggers have fully settled
  ///     (`viewInsets.bottom` back to 0).
  ///  3. THEN scroll the field to [dropdownFieldAlignment] (~20% from top).
  ///  4. Only after all of that does this future complete, letting
  ///     dropdown_search compute the popup position against the field's
  ///     FINAL, settled location — so the popup always opens cleanly below.
  ///
  /// Always returns true so the popup still opens.
  static Future<bool> ensureRoomForDropdown(BuildContext? context) async {
    if (context == null || !context.mounted) return true;
    // Step 1+2 — dismiss the keyboard and wait for the reflow to settle.
    FocusScope.of(context).unfocus();
    await _awaitKeyboardDismissed(context);
    if (!context.mounted) return true;
    // Step 3 — now that the field sits at its final position, scroll it up so
    // the popup has room to open below it.
    await Scrollable.ensureVisible(
      context,
      alignment: dropdownFieldAlignment,
      duration: _scrollDuration,
      curve: Curves.easeOut,
    );
    return true;
  }

  /// Bug #30 (revised) — block until the on-screen keyboard is fully gone and
  /// the layout reflow it triggers has settled. Polls `viewInsets.bottom`
  /// until it reaches 0, capped by [_keyboardDismissMaxWait] so a tap with no
  /// keyboard up (inset already 0) returns immediately and a device that
  /// never reports a zero inset cannot stall the popup.
  static Future<void> _awaitKeyboardDismissed(BuildContext context) async {
    const pollInterval = Duration(milliseconds: 16);
    final deadline = DateTime.now().add(_keyboardDismissMaxWait);
    while (context.mounted &&
        MediaQuery.of(context).viewInsets.bottom > 0 &&
        DateTime.now().isBefore(deadline)) {
      await Future.delayed(pollInterval);
    }
    // One more frame so the reflow from the final inset change is laid out
    // before the field is measured for scrolling / popup positioning.
    await WidgetsBinding.instance.endOfFrame;
  }
}
