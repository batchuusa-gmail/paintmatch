import 'dart:math';

// ── Wall ─────────────────────────────────────────────────────────────────────

class RoomWall {
  final String id;       // "A", "B", "C", "D"
  final String label;    // "north wall" etc.
  final double widthFt;
  final double heightFt;
  final bool estimated;

  const RoomWall({
    required this.id,
    required this.label,
    required this.widthFt,
    required this.heightFt,
    required this.estimated,
  });

  double get areaSqft => widthFt * heightFt;

  factory RoomWall.fromJson(Map<String, dynamic> j) => RoomWall(
        id: j['id'] as String? ?? j['label'] as String? ?? '?',
        label: j['label'] as String? ?? j['id'] as String? ?? 'wall',
        widthFt: (j['width_ft'] as num?)?.toDouble() ?? 12.0,
        heightFt: (j['height_ft'] as num?)?.toDouble() ?? 9.0,
        estimated: j['estimated'] as bool? ?? true,
      );
}

// ── Trim section (keyed by type) ──────────────────────────────────────────────

class TrimSection {
  final String type;       // "baseboards", "crown_molding", "door_casings", "window_casings"
  final double lengthFt;
  final double widthIn;    // inches
  final bool estimated;

  const TrimSection({
    required this.type,
    required this.lengthFt,
    required this.widthIn,
    required this.estimated,
  });

  double get areaSqft => lengthFt * (widthIn / 12.0);

  String get displayLabel => switch (type) {
    'baseboards'     => 'Baseboards',
    'crown_molding'  => 'Crown Molding',
    'door_casings'   => 'Door Casings',
    'window_casings' => 'Window Casings',
    _                => type,
  };

  factory TrimSection.fromJson(String type, Map<String, dynamic> j) => TrimSection(
        type: type,
        lengthFt: (j['length_ft'] as num?)?.toDouble() ?? 0.0,
        widthIn: (j['width_in'] as num?)?.toDouble() ?? 3.5,
        estimated: j['estimated'] as bool? ?? true,
      );
}

// ── Opening ───────────────────────────────────────────────────────────────────

class RoomOpening {
  final String id;       // "D1", "W1"
  final String type;     // "door" | "window"
  final String wallId;   // which wall it belongs to
  final double widthFt;
  final double heightFt;
  final bool estimated;

  const RoomOpening({
    required this.id,
    required this.type,
    required this.wallId,
    required this.widthFt,
    required this.heightFt,
    required this.estimated,
  });

  double get areaSqft => widthFt * heightFt;

  factory RoomOpening.fromJson(Map<String, dynamic> j) => RoomOpening(
        id: j['id'] as String? ?? '?',
        type: j['type'] as String? ?? 'opening',
        wallId: j['wall_id'] as String? ?? '?',
        widthFt: (j['width_ft'] as num?)?.toDouble() ?? 3.0,
        heightFt: (j['height_ft'] as num?)?.toDouble() ?? 6.8,
        estimated: j['estimated'] as bool? ?? true,
      );
}

// ── Main estimate ─────────────────────────────────────────────────────────────

class DimensionEstimate {
  final List<RoomWall> walls;
  final List<TrimSection> trim;      // one entry per visible trim type
  final List<RoomOpening> openings;
  final double ceilingHeightFt;
  final String confidence;           // 'high' | 'medium' | 'low'
  final String referenceUsed;
  final String notes;

  const DimensionEstimate({
    required this.walls,
    required this.trim,
    required this.openings,
    required this.ceilingHeightFt,
    required this.confidence,
    required this.referenceUsed,
    required this.notes,
  });

  // ── Computed totals ─────────────────────────────────────────────────────────

  double get grossWallSqft =>
      walls.fold(0.0, (s, w) => s + w.areaSqft);

  double get openingsSqft =>
      openings.fold(0.0, (s, o) => s + o.areaSqft);

  double get paintableWallSqft => max(0, grossWallSqft - openingsSqft);

  double get trimSqft =>
      trim.fold(0.0, (s, t) => s + t.areaSqft);

  int wallGallons({int coats = 2, int coverageSqft = 400}) =>
      paintableWallSqft <= 0 ? 0 : ((paintableWallSqft * coats) / coverageSqft).ceil();

  int trimGallons({int coats = 2, int coverageSqft = 400}) =>
      trimSqft <= 0 ? 0 : max(1, ((trimSqft * coats) / coverageSqft).ceil());

  bool get hasEstimatedDimensions =>
      walls.any((w) => w.estimated) || openings.any((o) => o.estimated);

  // ── Parsing ─────────────────────────────────────────────────────────────────

  factory DimensionEstimate.fromJson(Map<String, dynamic> j) {
    // Parse walls
    final wallsRaw = j['walls'];
    final walls = wallsRaw is List
        ? wallsRaw.whereType<Map<String, dynamic>>().map(RoomWall.fromJson).toList()
        : <RoomWall>[];

    // Parse trim — new format is a dict keyed by type
    final trimRaw = j['trim'];
    final trim = <TrimSection>[];
    if (trimRaw is Map<String, dynamic>) {
      for (final entry in trimRaw.entries) {
        if (entry.value is Map<String, dynamic>) {
          final t = TrimSection.fromJson(entry.key, entry.value as Map<String, dynamic>);
          if (t.lengthFt > 0) trim.add(t);
        }
      }
    } else if (trimRaw is List) {
      // Legacy list format
      for (final item in trimRaw.whereType<Map<String, dynamic>>()) {
        final label = item['label'] as String? ?? 'trim';
        final type = label.toLowerCase().replaceAll(' ', '_');
        final t = TrimSection.fromJson(type, item);
        if (t.lengthFt > 0) trim.add(t);
      }
    }

    // Parse openings
    final openingsRaw = j['openings'];
    final openings = openingsRaw is List
        ? openingsRaw.whereType<Map<String, dynamic>>().map(RoomOpening.fromJson).toList()
        : <RoomOpening>[];

    // Legacy single-pass format fallback
    if (walls.isEmpty && j.containsKey('estimated_wall_width_ft')) {
      final w = (j['estimated_wall_width_ft'] as num?)?.toDouble() ?? 12.0;
      final d = (j['estimated_room_depth_ft'] as num?)?.toDouble() ?? 12.0;
      const h = 9.0;
      return DimensionEstimate(
        walls: [
          RoomWall(id: 'A', label: 'Wall A', widthFt: w, heightFt: h, estimated: true),
          RoomWall(id: 'B', label: 'Wall B', widthFt: w, heightFt: h, estimated: true),
          RoomWall(id: 'C', label: 'Wall C', widthFt: d, heightFt: h, estimated: true),
          RoomWall(id: 'D', label: 'Wall D', widthFt: d, heightFt: h, estimated: true),
        ],
        trim: [],
        openings: [
          RoomOpening(id: 'D1', type: 'door', wallId: 'A', widthFt: 3.0, heightFt: 6.8, estimated: true),
        ],
        ceilingHeightFt: h,
        confidence: j['confidence'] as String? ?? 'low',
        referenceUsed: '',
        notes: j['reason'] as String? ?? '',
      );
    }

    return DimensionEstimate(
      walls: walls,
      trim: trim,
      openings: openings,
      ceilingHeightFt: (j['ceiling_height_ft'] as num?)?.toDouble() ?? 9.0,
      confidence: j['confidence'] as String? ?? 'medium',
      referenceUsed: j['reference_used'] as String? ?? '',
      notes: j['notes'] as String? ?? '',
    );
  }

  static DimensionEstimate get fallback => DimensionEstimate(
        walls: [
          const RoomWall(id: 'A', label: 'Wall A', widthFt: 14.0, heightFt: 9.0, estimated: true),
          const RoomWall(id: 'B', label: 'Wall B', widthFt: 14.0, heightFt: 9.0, estimated: true),
          const RoomWall(id: 'C', label: 'Wall C', widthFt: 12.0, heightFt: 9.0, estimated: true),
          const RoomWall(id: 'D', label: 'Wall D', widthFt: 12.0, heightFt: 9.0, estimated: true),
        ],
        trim: [
          const TrimSection(type: 'baseboards', lengthFt: 52.0, widthIn: 3.5, estimated: true),
          const TrimSection(type: 'door_casings', lengthFt: 14.0, widthIn: 2.5, estimated: true),
        ],
        openings: [
          const RoomOpening(id: 'D1', type: 'door', wallId: 'A', widthFt: 3.0, heightFt: 6.8, estimated: true),
          const RoomOpening(id: 'W1', type: 'window', wallId: 'B', widthFt: 3.5, heightFt: 4.0, estimated: true),
        ],
        ceilingHeightFt: 9.0,
        confidence: 'low',
        referenceUsed: '',
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
