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

class DimensionEstimate {
  final double estimatedWallWidthFt;
  final double estimatedRoomDepthFt;
  final String confidence; // 'high' | 'medium' | 'low'
  final String referenceObject;
  final String reason;

  const DimensionEstimate({
    required this.estimatedWallWidthFt,
    required this.estimatedRoomDepthFt,
    required this.confidence,
    required this.referenceObject,
    required this.reason,
  });

  factory DimensionEstimate.fromJson(Map<String, dynamic> j) => DimensionEstimate(
        estimatedWallWidthFt: (j['estimated_wall_width_ft'] as num?)?.toDouble() ?? 12.0,
        estimatedRoomDepthFt: (j['estimated_room_depth_ft'] as num?)?.toDouble() ?? 12.0,
        confidence: j['confidence'] as String? ?? 'low',
        referenceObject: j['reference_object'] as String? ?? 'none',
        reason: j['reason'] as String? ?? '',
      );

  static DimensionEstimate get fallback => const DimensionEstimate(
        estimatedWallWidthFt: 12.0,
        estimatedRoomDepthFt: 12.0,
        confidence: 'low',
        referenceObject: 'none',
        reason: 'Estimated — please verify',
      );
}
