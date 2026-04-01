class PaintColor {
  final String? id;
  final String vendor;
  final String colorName;
  final String colorCode;
  final String hex;
  final double? lrv;
  final List<String> finishOptions;
  final double? pricePerGallon;
  final int? coverageSqft;
  final double? deltaE;

  const PaintColor({
    this.id,
    required this.vendor,
    required this.colorName,
    required this.colorCode,
    required this.hex,
    this.lrv,
    this.finishOptions = const [],
    this.pricePerGallon,
    this.coverageSqft,
    this.deltaE,
  });

  factory PaintColor.fromJson(Map<String, dynamic> json) => PaintColor(
        id: json['id'] as String?,
        vendor: json['vendor'] as String,
        colorName: json['color_name'] as String,
        colorCode: json['color_code'] as String,
        hex: json['hex'] as String,
        lrv: (json['lrv'] as num?)?.toDouble(),
        finishOptions: (json['finish_options'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
        pricePerGallon: (json['price_per_gallon'] as num?)?.toDouble(),
        coverageSqft: json['coverage_sqft'] as int?,
        deltaE: (json['delta_e'] as num?)?.toDouble(),
      );

  String get vendorDisplayName {
    const names = {
      'sherwin_williams': 'Sherwin-Williams',
      'benjamin_moore': 'Benjamin Moore',
      'behr': 'Behr',
      'ppg': 'PPG',
      'valspar': 'Valspar',
    };
    return names[vendor] ?? vendor;
  }
}
