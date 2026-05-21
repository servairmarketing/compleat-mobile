/// Roll status terminology — shared across Production / Conversion / Stock Take
/// and History screens so labels stay consistent.
///
/// Parent rolls: in_stock | in_production | consumed.
/// Child rolls:  in_stock | in_production | converted | sold.
const Map<String, String> rollStatusLabels = {
  'in_stock': 'In Stock',
  'in_production': 'In Production',
  'consumed': 'Consumed',
  'converted': 'Converted',
  'sold': 'Sold',
};

/// Human-readable label for a raw roll status value. Falls back to a
/// space-separated form for any unrecognised value (e.g. legacy data).
String rollStatusLabel(String status) =>
    rollStatusLabels[status] ?? status.replaceAll('_', ' ');
