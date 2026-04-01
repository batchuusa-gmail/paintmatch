class PaletteSuggestion {
  final String name;
  final String hex;
  final String rationale;

  const PaletteSuggestion({
    required this.name,
    required this.hex,
    required this.rationale,
  });

  factory PaletteSuggestion.fromJson(Map<String, dynamic> json) =>
      PaletteSuggestion(
        name: json['name'] as String,
        hex: json['hex'] as String,
        rationale: json['rationale'] as String,
      );
}

class RoomAnalysis {
  final String wallHex;
  final String roomStyle;
  final String lighting;
  final List<String> furniturePalette;
  final List<PaletteSuggestion> recommendedPalettes;

  const RoomAnalysis({
    required this.wallHex,
    required this.roomStyle,
    required this.lighting,
    required this.furniturePalette,
    required this.recommendedPalettes,
  });

  factory RoomAnalysis.fromJson(Map<String, dynamic> json) => RoomAnalysis(
        wallHex: json['wall_hex'] as String,
        roomStyle: json['room_style'] as String,
        lighting: json['lighting'] as String,
        furniturePalette:
            (json['furniture_palette'] as List<dynamic>?)
                    ?.map((e) => e as String)
                    .toList() ??
                [],
        recommendedPalettes:
            (json['recommended_palettes'] as List<dynamic>)
                .map((e) => PaletteSuggestion.fromJson(e as Map<String, dynamic>))
                .toList(),
      );
}
