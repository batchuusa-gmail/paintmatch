import 'dart:math';

class RoomWall {
  final String label;
  final double widthFt;
  final double heightFt;
  const RoomWall({required this.label, required this.widthFt, required this.heightFt});

  double get areaSqft => widthFt * heightFt;

  factory RoomWall.fromJson(Map<String, dynamic> j) => RoomWall(
        label: j['label'] as String? ?? 'wall',
        widthFt: (j['width_ft'] as num?)?.toDouble() ?? 12.0,
        heightFt: (j['height_ft'] as num?)?.toDouble() ?? 9.0,
      );
}

class TrimSection {
  final String label;
  final double lengthFt;
  final double widthIn; // inches
  const TrimSection({required this.label, required this.lengthFt, required this.widthIn});

  double get areaSqft => lengthFt * (widthIn / 12.0);

  factory TrimSection.fromJson(Map<String, dynamic> j) => TrimSection(
        label: j['label'] as String? ?? 'trim',
        lengthFt: (j['length_ft'] as num?)?.toDouble() ?? 0.0,
        widthIn: (j['width_in'] as num?)?.toDouble() ?? 3.5,
      );
}

class RoomOpening {
  final String label;
  final double widthFt;
  final double heightFt;
  const RoomOpening({required this.label, required this.widthFt, required this.heightFt});

  double get areaSqft => widthFt * heightFt;

  factory RoomOpening.fromJson(Map<String, dynamic> j) => RoomOpening(
        label: j['label'] as String? ?? 'opening',
        widthFt: (j['width_ft'] as num?)?.toDouble() ?? 3.0,
        heightFt: (j['height_ft'] as num?)?.toDouble() ?? 6.8,
      );
}

class DimensionEstimate {
  final List<RoomWall> walls;
  final List<TrimSection> trim;
  final List<RoomOpening> openings;
  final double ceilingHeightFt;
  final String confidence; // 'high' | 'medium' | 'low'
  final String notes;

  const DimensionEstimate({
    required this.walls,
    required this.trim,
    required this.openings,
    required this.ceilingHeightFt,
    required this.confidence,
    required this.notes,
  });

  // ── Computed totals ───────────────────────────────────────────────────────

  /// Gross wall area (all walls added up, before subtracting openings)
  double get grossWallSqft =>
      walls.fold(0.0, (sum, w) => sum + w.areaSqft);

  /// Area to subtract for doors + windows
  double get openingsSqft =>
      openings.fold(0.0, (sum, o) => sum + o.areaSqft);

  /// Net paintable wall area
  double get paintableWallSqft => max(0, grossWallSqft - openingsSqft);

  /// Total trim paint area (length × width converted to sqft)
  double get trimSqft =>
      trim.fold(0.0, (sum, t) => sum + t.areaSqft);

  /// Gallons needed for walls
  int wallGallons({int coats = 2, int coverageSqft = 400}) {
    if (paintableWallSqft <= 0) return 0;
    return ((paintableWallSqft * coats) / coverageSqft).ceil();
  }

  /// Gallons needed for trim
  int trimGallons({int coats = 2, int coverageSqft = 400}) {
    if (trimSqft <= 0) return 0;
    return max(1, ((trimSqft * coats) / coverageSqft).ceil());
  }

  factory DimensionEstimate.fromJson(Map<String, dynamic> j) {
    List<T> parseList<T>(String key, T Function(Map<String, dynamic>) fn) {
      final raw = j[key];
      if (raw is! List) return [];
      return raw.whereType<Map<String, dynamic>>().map(fn).toList();
    }

    // Legacy fallback: if old format (estimated_wall_width_ft), convert it
    if (j.containsKey('estimated_wall_width_ft') && !j.containsKey('walls')) {
      final w = (j['estimated_wall_width_ft'] as num?)?.toDouble() ?? 12.0;
      final d = (j['estimated_room_depth_ft'] as num?)?.toDouble() ?? 12.0;
      const h = 9.0;
      return DimensionEstimate(
        walls: [
          RoomWall(label: 'wall 1', widthFt: w, heightFt: h),
          RoomWall(label: 'wall 2', widthFt: w, heightFt: h),
          RoomWall(label: 'wall 3', widthFt: d, heightFt: h),
          RoomWall(label: 'wall 4', widthFt: d, heightFt: h),
        ],
        trim: [],
        openings: [
          RoomOpening(label: 'door', widthFt: 3.0, heightFt: 6.8),
          RoomOpening(label: 'window', widthFt: 3.5, heightFt: 4.0),
        ],
        ceilingHeightFt: h,
        confidence: j['confidence'] as String? ?? 'low',
        notes: j['reason'] as String? ?? '',
      );
    }

    return DimensionEstimate(
      walls: parseList('walls', RoomWall.fromJson),
      trim: parseList('trim', TrimSection.fromJson),
      openings: parseList('openings', RoomOpening.fromJson),
      ceilingHeightFt: (j['ceiling_height_ft'] as num?)?.toDouble() ?? 9.0,
      confidence: j['confidence'] as String? ?? 'medium',
      notes: j['notes'] as String? ?? '',
    );
  }

  static DimensionEstimate get fallback => DimensionEstimate(
        walls: [
          const RoomWall(label: 'wall 1', widthFt: 14.0, heightFt: 9.0),
          const RoomWall(label: 'wall 2', widthFt: 14.0, heightFt: 9.0),
          const RoomWall(label: 'wall 3', widthFt: 12.0, heightFt: 9.0),
          const RoomWall(label: 'wall 4', widthFt: 12.0, heightFt: 9.0),
        ],
        trim: [
          const TrimSection(label: 'baseboards', lengthFt: 52.0, widthIn: 3.5),
          const TrimSection(label: 'door casings', lengthFt: 14.0, widthIn: 2.5),
        ],
        openings: [
          const RoomOpening(label: 'door', widthFt: 3.0, heightFt: 6.8),
          const RoomOpening(label: 'window', widthFt: 3.5, heightFt: 4.0),
        ],
        ceilingHeightFt: 9.0,
        confidence: 'low',
        notes: 'Estimated — verify with measurements',
      );
}

// Legacy class kept for any remaining references
class RoomDimensions {
  final double ceilingHeightFt;
  final double wallWidthFt;
  final double roomDepthFt;
  final int doorCount;
  final int windowCount;

  const RoomDimensions({
    required this.ceilingHeightFt,
    required this.wallWidthFt,
    required this.roomDepthFt,
    required this.doorCount,
    required this.windowCount,
  });
}
