import 'package:flutter/material.dart';

import 'services/api_service.dart' show appEnvironment;

/// Single source of truth for the brand/chrome colour.
///
/// Compile-time constant: `appEnvironment` comes from the existing
/// `--dart-define=APP_ENV` (qa flavor passes `test`), so the committed
/// default (prod) is the IMS blue and ONLY a qa/test build gets the red.
/// The red look cannot ship to live by accident.
///
/// §2.15 contrast: white on #B91C1C = 6.5:1 (>= 4.5:1 AA), and #B91C1C on
/// white = 6.5:1 — both better than the blue it replaces (~4.5:1).
const Color kBrandColor = appEnvironment == 'test'
    ? Color(0xFFB91C1C) // test: red chrome, matches web + TEST ribbon
    : Color(0xFF1a73e8); // prod: IMS blue (unchanged live look)
