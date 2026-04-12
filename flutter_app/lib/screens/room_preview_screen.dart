import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../config/app_theme.dart';
import '../models/paint_color.dart';
import '../services/api_service.dart';
import '../services/supabase_service.dart';
import '../utils/color_ext.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Surface definitions
// ─────────────────────────────────────────────────────────────────────────────
class _Surface {
  final String id;      // matches ADE20K label sent to backend
  final String label;
  final IconData icon;
  const _Surface(this.id, this.label, this.icon);
}

const _surfaces = [
  _Surface('wall',    'Walls',    Icons.format_paint),
  _Surface('ceiling', 'Ceiling',  Icons.roofing),
  _Surface('floor',   'Floor',    Icons.layers),
  _Surface('trim',    'Trim',     Icons.border_all_outlined),
];

// ─────────────────────────────────────────────────────────────────────────────
// Isolate blend payload
// ─────────────────────────────────────────────────────────────────────────────
class _BlendParams {
  final Uint8List srcRgba;
  final int srcW, srcH;
  final Uint8List maskRgba;
  final int maskW, maskH;
  final int tR, tG, tB;
  const _BlendParams({
    required this.srcRgba, required this.srcW, required this.srcH,
    required this.maskRgba, required this.maskW, required this.maskH,
    required this.tR, required this.tG, required this.tB,
  });
}

// RGB ↔ HSL helpers (all values 0.0–1.0)
List<double> _rgbToHsl(double r, double g, double b) {
  final max = [r, g, b].reduce((a, x) => x > a ? x : a);
  final min = [r, g, b].reduce((a, x) => x < a ? x : a);
  final l = (max + min) / 2.0;
  if (max == min) return [0.0, 0.0, l];
  final d = max - min;
  final s = l > 0.5 ? d / (2.0 - max - min) : d / (max + min);
  double h;
  if (max == r)      h = (g - b) / d + (g < b ? 6 : 0);
  else if (max == g) h = (b - r) / d + 2;
  else               h = (r - g) / d + 4;
  return [h / 6.0, s, l];
}

double _hue2rgb(double p, double q, double t) {
  if (t < 0) t += 1;
  if (t > 1) t -= 1;
  if (t < 1/6) return p + (q - p) * 6 * t;
  if (t < 1/2) return q;
  if (t < 2/3) return p + (q - p) * (2/3 - t) * 6;
  return p;
}

List<double> _hslToRgb(double h, double s, double l) {
  if (s == 0) return [l, l, l];
  final q = l < 0.5 ? l * (1 + s) : l + s - l * s;
  final p = 2 * l - q;
  return [_hue2rgb(p, q, h + 1/3), _hue2rgb(p, q, h), _hue2rgb(p, q, h - 1/3)];
}

Uint8List _blendIsolate(_BlendParams p) {
  final src  = p.srcRgba;
  final mask = p.maskRgba;
  final out  = Uint8List.fromList(src);
  final total = p.srcW * p.srcH;

  final tR = p.tR / 255.0, tG = p.tG / 255.0, tB = p.tB / 255.0;
  final targetHsl = _rgbToHsl(tR, tG, tB);
  final tH = targetHsl[0], tS = targetHsl[1], tL = targetHsl[2];

  for (int i = 0; i < total; i++) {
    final sb = i * 4;
    final mx = ((i % p.srcW) * p.maskW / p.srcW).round().clamp(0, p.maskW - 1);
    final my = ((i ~/ p.srcW) * p.maskH / p.srcH).round().clamp(0, p.maskH - 1);
    if (mask[(my * p.maskW + mx) * 4] <= 127) continue;

    final r = src[sb] / 255.0, g = src[sb+1] / 255.0, b = src[sb+2] / 255.0;
    final srcHsl = _rgbToHsl(r, g, b);
    final srcL   = srcHsl[2];

    // Use target H + S (full color swap)
    // Lightness: 40% original (keeps shadows/texture) + 60% target (shows true color)
    // This makes dark colors look dark and bright colors look bright
    final blendL = srcL * 0.40 + tL * 0.60;

    final recolored = _hslToRgb(tH, tS, blendL);
    out[sb]   = (recolored[0] * 255).round().clamp(0, 255);
    out[sb+1] = (recolored[1] * 255).round().clamp(0, 255);
    out[sb+2] = (recolored[2] * 255).round().clamp(0, 255);
  }
  return out;
}

// ─────────────────────────────────────────────────────────────────────────────
// Widget
// ─────────────────────────────────────────────────────────────────────────────
class RoomPreviewScreen extends StatefulWidget {
  final String originalImageUrl;
  final String? renderedImageUrl;
  final String selectedHex;
  final String selectedColorName;
  final File? imageFile;
  final String? wallHex;

  const RoomPreviewScreen({
    super.key,
    required this.originalImageUrl,
    required this.renderedImageUrl,
    required this.selectedHex,
    required this.selectedColorName,
    this.imageFile,
    this.wallHex,
  });

  @override
  State<RoomPreviewScreen> createState() => _RoomPreviewScreenState();
}

class _RoomPreviewScreenState extends State<RoomPreviewScreen> {
  bool _saving = false;
  bool _rendering = false;
  String _renderStatus = '';
  String _environment = 'interior';
  String _selectedSurface = 'wall';

  late String _selectedHex;
  late String _selectedColorName;

  // Tap seed — normalized 0–1 coords within the displayed image
  double? _seedX, _seedY;

  // Image data
  ui.Image? _srcImage;
  Uint8List? _srcRgba;
  Uint8List? _srcJpeg;
  Uint8List? _renderedBytes;

  // Cached mask — reuse on color change, only re-fetch on new tap
  Uint8List? _cachedMaskRgba;
  int? _cachedMaskW, _cachedMaskH;

  @override
  void initState() {
    super.initState();
    _selectedHex = widget.selectedHex;
    _selectedColorName = widget.selectedColorName;
    _loadImage();
  }

  Future<void> _loadImage() async {
    if (widget.imageFile == null) return;
    setState(() { _rendering = true; _renderStatus = 'Loading image…'; });
    try {
      final rawBytes = await widget.imageFile!.readAsBytes();
      _srcJpeg = rawBytes;
      final codec = await ui.instantiateImageCodec(rawBytes);
      final frame = await codec.getNextFrame();
      final img = frame.image;
      final bd = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      _srcImage = img;
      _srcRgba = bd!.buffer.asUint8List();
    } catch (e) {
      if (mounted) setState(() { _renderStatus = 'Failed to load: $e'; });
    } finally {
      if (mounted) setState(() => _rendering = false);
    }
  }

  Future<void> _paint({double? seedX, double? seedY}) async {
    if (_srcImage == null || _srcRgba == null || _srcJpeg == null) return;

    final isNewTap = seedX != null || seedY != null;
    if (seedX != null) _seedX = seedX;
    if (seedY != null) _seedY = seedY;

    setState(() {
      _rendering = true;
      _renderedBytes = null;
      _renderStatus = isNewTap ? 'Segmenting surface…' : 'Applying color…';
    });

    try {
      // Only call SAM on a new tap — reuse cached mask for color changes
      if (isNewTap || _cachedMaskRgba == null) {
        setState(() => _renderStatus = 'Analyzing surface… (10–15s first time)');
        final result = await ApiService().segmentWall(
          imageBase64: base64Encode(_srcJpeg!),
          surface: _selectedSurface,
          seedX: _seedX,
          seedY: _seedY,
        );
        final maskBytes = base64Decode(result['mask'] as String);
        final coverage  = (result['coverage'] as double?) ?? 0.0;

        // Coverage < 3% means a tiny object (switch/frame/pillow) was hit, not a wall.
        // Warn the user immediately before painting.
        if (coverage < 0.03 && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'That looks like a small object, not a wall.\n'
                'Tap on a plain open wall area for best results.',
              ),
              backgroundColor: Colors.orange.shade800,
              duration: const Duration(seconds: 4),
              action: SnackBarAction(
                label: 'OK',
                textColor: Colors.white,
                onPressed: () {},
              ),
            ),
          );
          setState(() { _rendering = false; _renderStatus = ''; });
          return;
        }

        final maskCodec = await ui.instantiateImageCodec(maskBytes);
        final maskFrame = await maskCodec.getNextFrame();
        final maskImg   = maskFrame.image;
        final maskBd    = await maskImg.toByteData(format: ui.ImageByteFormat.rawRgba);
        _cachedMaskRgba = maskBd!.buffer.asUint8List();
        _cachedMaskW    = maskImg.width;
        _cachedMaskH    = maskImg.height;
      }

      setState(() => _renderStatus = 'Applying color…');
      final target = HexColor.fromHex(_selectedHex);
      final out = await compute(_blendIsolate, _BlendParams(
        srcRgba: _srcRgba!, srcW: _srcImage!.width, srcH: _srcImage!.height,
        maskRgba: _cachedMaskRgba!, maskW: _cachedMaskW!, maskH: _cachedMaskH!,
        tR: (target.r * 255).round(),
        tG: (target.g * 255).round(),
        tB: (target.b * 255).round(),
      ));

      final c = Completer<ui.Image>();
      ui.decodeImageFromPixels(out, _srcImage!.width, _srcImage!.height, ui.PixelFormat.rgba8888, c.complete);
      final rendered = await c.future;
      final renderBd = await rendered.toByteData(format: ui.ImageByteFormat.png);
      if (mounted) setState(() => _renderedBytes = renderBd!.buffer.asUint8List());
    } catch (e, s) {
      debugPrint('[Render] $e\n$s');
      if (mounted) setState(() => _renderStatus = 'Failed: $e');
    } finally {
      if (mounted) setState(() => _rendering = false);
    }
  }

  void _onImageTap(TapUpDetails details, BoxConstraints box) {
    // BoxFit.cover crops the image — correct tap coords to image space.
    // Without this, tapping the wall on a portrait photo sends wrong
    // coordinates to SAM (e.g. hits a switch instead of the wall).
    double dx, dy;
    if (_srcImage != null) {
      final imgW = _srcImage!.width.toDouble();
      final imgH = _srcImage!.height.toDouble();
      final boxW = box.maxWidth;
      final boxH = box.maxHeight;
      final scale = math.max(boxW / imgW, boxH / imgH);
      final scaledW = imgW * scale;
      final scaledH = imgH * scale;
      final cropX = (scaledW - boxW) / 2;
      final cropY = (scaledH - boxH) / 2;
      dx = ((details.localPosition.dx + cropX) / scaledW).clamp(0.0, 1.0);
      dy = ((details.localPosition.dy + cropY) / scaledH).clamp(0.0, 1.0);
    } else {
      dx = (details.localPosition.dx / box.maxWidth).clamp(0.0, 1.0);
      dy = (details.localPosition.dy / box.maxHeight).clamp(0.0, 1.0);
    }
    _paint(seedX: dx, seedY: dy);
  }

  void _openColorPicker() async {
    final result = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ColorPickerSheet(
        currentHex: _selectedHex,
        currentName: _selectedColorName,
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _selectedHex = result['hex']!;
        _selectedColorName = result['name']!;
      });
      if (_seedX != null) {
        _paint(); // re-paint with same seed, new color
      }
    }
  }

  Widget _buildOriginalImage() {
    if (widget.imageFile != null) return Image.file(widget.imageFile!, fit: BoxFit.cover);
    return const SizedBox.shrink();
  }

  Future<void> _saveToProject() async {
    if (!SupabaseService().isSignedIn) { context.push('/login'); return; }
    setState(() => _saving = true);
    try {
      await SupabaseService().saveProject(
        projectName: _selectedColorName,
        renderedImageUrl: null,
        selectedHex: _selectedHex,
      );
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved!')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $e'), backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _share() async {
    try {
      final bytes = _renderedBytes ?? await widget.imageFile!.readAsBytes();
      final temp = await getTemporaryDirectory();
      final file = File('${temp.path}/paintmatch_preview.png');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles([XFile(file.path)], text: 'My room in $_selectedColorName via PaintMatch');
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;
    final swatchColor = HexColor.fromHex(_selectedHex);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: AppColors.textPrimary, size: 18),
          onPressed: () => context.go('/'),
        ),
        title: Text('Preview',
            style: GoogleFonts.playfairDisplay(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined, color: AppColors.textSecondary),
            onPressed: _share,
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Room image preview (48% height) ──────────────────────────────
          SizedBox(
            height: screenH * 0.48,
            child: _rendering
                ? Stack(fit: StackFit.expand, children: [
                    _buildOriginalImage(),
                    Container(color: Colors.black54),
                    Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2),
                      const SizedBox(height: 12),
                      Text(_renderStatus,
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          textAlign: TextAlign.center),
                    ])),
                  ])
                : _renderedBytes != null
                    ? Stack(children: [
                        Positioned.fill(child: _BeforeAfterSlider(
                          before: _buildOriginalImage(),
                          after: Image.memory(_renderedBytes!, fit: BoxFit.cover),
                        )),
                        // Tap-again hint
                        Positioned(top: 10, right: 10,
                          child: GestureDetector(
                            onTap: () => setState(() {
                              _renderedBytes = null;
                              _seedX = null;
                              _seedY = null;
                              _cachedMaskRgba = null;
                            }),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(12)),
                              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                                Icon(Icons.touch_app, color: AppColors.accent, size: 13),
                                SizedBox(width: 4),
                                Text('Re-tap', style: TextStyle(color: Colors.white, fontSize: 11)),
                              ]),
                            ),
                          )),
                      ])
                    // ── Tap-to-paint mode ──
                    : LayoutBuilder(builder: (ctx, box) => GestureDetector(
                        onTapUp: (d) => _onImageTap(d, box),
                        child: Stack(fit: StackFit.expand, children: [
                          _buildOriginalImage(),
                          Container(color: Colors.black.withValues(alpha: 0.35)),
                          Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: AppColors.accent,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.touch_app, color: Colors.black, size: 28),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(20)),
                              child: Text(
                                'Tap the ${_selectedSurface} to paint it',
                                style: const TextStyle(color: Colors.white,
                                    fontSize: 14, fontWeight: FontWeight.w600),
                              ),
                            ),
                            if (_renderStatus.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(_renderStatus,
                                  style: const TextStyle(color: Colors.red, fontSize: 12)),
                            ],
                          ])),
                        ]),
                      )),
          ),

          // ── Controls panel ───────────────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  // Environment row
                  const Text('Environment',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 11,
                          fontWeight: FontWeight.w600, letterSpacing: 0.8)),
                  const SizedBox(height: 10),
                  Row(children: [
                    _EnvChip(
                      icon: Icons.home_outlined,
                      label: 'Interior',
                      selected: _environment == 'interior',
                      onTap: () => setState(() => _environment = 'interior'),
                    ),
                    const SizedBox(width: 10),
                    _EnvChip(
                      icon: Icons.location_city_outlined,
                      label: 'Exterior',
                      selected: _environment == 'exterior',
                      onTap: () => setState(() => _environment = 'exterior'),
                    ),
                  ]),

                  const SizedBox(height: 24),

                  // What to Paint
                  const Text('What to Paint',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 11,
                          fontWeight: FontWeight.w600, letterSpacing: 0.8)),
                  const SizedBox(height: 10),
                  Row(children: _surfaces.map((s) {
                    final sel = _selectedSurface == s.id;
                    return Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: GestureDetector(
                        onTap: _rendering ? null : () {
                          setState(() {
                            _selectedSurface = s.id;
                            _renderedBytes = null;
                            _seedX = null;
                            _seedY = null;
                            _cachedMaskRgba = null;
                          });
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: sel ? AppColors.accentDim : AppColors.card,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: sel ? AppColors.accent : AppColors.border,
                              width: sel ? 1.5 : 1),
                          ),
                          child: Column(children: [
                            Icon(s.icon, size: 20,
                                color: sel ? AppColors.accent : AppColors.textSecondary),
                            const SizedBox(height: 4),
                            Text(s.label,
                                style: TextStyle(
                                  color: sel ? AppColors.accent : AppColors.textSecondary,
                                  fontSize: 11,
                                  fontWeight: sel ? FontWeight.w600 : FontWeight.normal)),
                          ]),
                        ),
                      ),
                    );
                  }).toList()),

                  const SizedBox(height: 24),

                  // Selected color row
                  const Text('Color',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 11,
                          fontWeight: FontWeight.w600, letterSpacing: 0.8)),
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: _openColorPicker,
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(children: [
                        Container(
                          width: 44, height: 44,
                          decoration: BoxDecoration(
                            color: swatchColor,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.border),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_selectedColorName,
                                style: const TextStyle(color: AppColors.textPrimary,
                                    fontWeight: FontWeight.w600, fontSize: 15)),
                            const SizedBox(height: 3),
                            Text(_selectedHex.toUpperCase(),
                                style: const TextStyle(color: AppColors.textSecondary,
                                    fontSize: 12, fontFamily: 'monospace')),
                          ],
                        )),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.accent,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text('Select Color',
                              style: TextStyle(color: Colors.black,
                                  fontSize: 12, fontWeight: FontWeight.w700)),
                        ),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Bottom action bar ─────────────────────────────────────────────
          Container(
            color: AppColors.bottomNav,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            child: FilledButton.icon(
              icon: _saving
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                  : const Icon(Icons.bookmark_add_outlined, size: 18, color: Colors.black),
              label: const Text('Save to Project'),
              onPressed: _saving ? null : _saveToProject,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Custom before/after slider
// ─────────────────────────────────────────────────────────────────────────────
class _BeforeAfterSlider extends StatefulWidget {
  final Widget before;
  final Widget after;
  const _BeforeAfterSlider({required this.before, required this.after});

  @override
  State<_BeforeAfterSlider> createState() => _BeforeAfterSliderState();
}

class _BeforeAfterSliderState extends State<_BeforeAfterSlider> {
  double _split = 0.5; // 0.0 = all before, 1.0 = all after

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, constraints) {
      final w = constraints.maxWidth;
      final h = constraints.maxHeight;
      final splitX = w * _split;

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (d) {
          setState(() {
            _split = ((_split * w + d.delta.dx) / w).clamp(0.02, 0.98);
          });
        },
        onTapDown: (d) {
          setState(() => _split = (d.localPosition.dx / w).clamp(0.02, 0.98));
        },
        child: Stack(children: [
          // After (full width underneath)
          Positioned.fill(child: widget.after),
          // Before (clipped to left of split)
          Positioned(
            left: 0, top: 0, bottom: 0,
            width: splitX,
            child: ClipRect(
              child: OverflowBox(
                alignment: Alignment.centerLeft,
                maxWidth: w,
                child: SizedBox(width: w, height: h, child: widget.before),
              ),
            ),
          ),
          // Divider line
          Positioned(
            left: splitX - 1, top: 0, bottom: 0,
            child: Container(width: 2, color: AppColors.accent),
          ),
          // Handle
          Positioned(
            left: splitX - 20, top: h / 2 - 20,
            child: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: AppColors.accent,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: Colors.black38, blurRadius: 6)],
              ),
              child: const Icon(Icons.swap_horiz, color: Colors.black, size: 20),
            ),
          ),
          // Labels
          Positioned(top: 10, left: 10,
            child: _label('BEFORE')),
          Positioned(top: 10, right: 10,
            child: _label('AFTER')),
        ]),
      );
    });
  }

  Widget _label(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: Colors.black54,
      borderRadius: BorderRadius.circular(6)),
    child: Text(text,
      style: const TextStyle(color: Colors.white, fontSize: 10,
          fontWeight: FontWeight.w700, letterSpacing: 0.5)),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Environment chip
// ─────────────────────────────────────────────────────────────────────────────
class _EnvChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _EnvChip({required this.icon, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.accent : AppColors.card,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: selected ? AppColors.accent : AppColors.border),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: selected ? Colors.black : AppColors.textSecondary),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(
            color: selected ? Colors.black : AppColors.textSecondary,
            fontSize: 13, fontWeight: selected ? FontWeight.w700 : FontWeight.normal)),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Color Picker Bottom Sheet
// ─────────────────────────────────────────────────────────────────────────────
class _ColorPickerSheet extends StatefulWidget {
  final String currentHex;
  final String currentName;
  const _ColorPickerSheet({required this.currentHex, required this.currentName});

  @override
  State<_ColorPickerSheet> createState() => _ColorPickerSheetState();
}

class _ColorPickerSheetState extends State<_ColorPickerSheet> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  String _vendorFilter = 'all';
  List<PaintColor> _filtered = [];
  bool _loading = true;
  String? _selectedHex;
  String? _selectedName;

  static const _vendors = [
    ('all', 'All'),
    ('sherwin_williams', 'Sherwin-Williams'),
    ('benjamin_moore', 'Benjamin Moore'),
    ('behr', 'Behr'),
    ('ppg', 'PPG'),
    ('valspar', 'Valspar'),
  ];

  @override
  void initState() {
    super.initState();
    _selectedHex = widget.currentHex;
    _selectedName = widget.currentName;
    _loadColors();
    _searchCtrl.addListener(_filter);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadColors() async {
    setState(() => _loading = true);
    try {
      final colors = await ApiService().listColors(
        vendor: _vendorFilter == 'all' ? null : _vendorFilter,
        search: _searchCtrl.text.trim().isEmpty ? null : _searchCtrl.text.trim(),
        limit: 200,
      );
      if (mounted) {
        setState(() { _filtered = colors; _loading = false; });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _filter() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _loadColors);
  }

  void _selectVendor(String v) {
    setState(() => _vendorFilter = v);
    _loadColors();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2)),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(children: [
                Text('Select Color',
                    style: GoogleFonts.playfairDisplay(
                        color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.w600)),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context,
                      _selectedHex != null ? {'hex': _selectedHex!, 'name': _selectedName!} : null),
                  child: const Text('Apply',
                      style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700)),
                ),
              ]),
            ),
            // Search
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: TextField(
                controller: _searchCtrl,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Search paint color names…',
                  hintStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  prefixIcon: const Icon(Icons.search, color: AppColors.textSecondary, size: 18),
                  filled: true,
                  fillColor: AppColors.background,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.border)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.border)),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.accent)),
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
            // Vendor filter tabs
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                itemCount: _vendors.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final v = _vendors[i];
                  final sel = _vendorFilter == v.$1;
                  return GestureDetector(
                    onTap: () => _selectVendor(v.$1),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: sel ? AppColors.accent : AppColors.background,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: sel ? AppColors.accent : AppColors.border)),
                      child: Text(v.$2,
                          style: TextStyle(
                            color: sel ? Colors.black : AppColors.textSecondary,
                            fontSize: 12, fontWeight: sel ? FontWeight.w700 : FontWeight.normal)),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            // Color grid
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
                  : _filtered.isEmpty
                      ? const Center(child: Text('No colors found',
                          style: TextStyle(color: AppColors.textSecondary)))
                      : GridView.builder(
                          controller: scrollCtrl,
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: 0.8,
                          ),
                          itemCount: _filtered.length,
                          itemBuilder: (_, i) {
                            final c = _filtered[i];
                            final sel = _selectedHex == c.hex;
                            return GestureDetector(
                              onTap: () => setState(() {
                                _selectedHex = c.hex;
                                _selectedName = c.colorName;
                              }),
                              child: Column(children: [
                                Expanded(
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 150),
                                    decoration: BoxDecoration(
                                      color: HexColor.fromHex(c.hex),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: sel ? AppColors.accent : AppColors.border,
                                        width: sel ? 2.5 : 1),
                                      boxShadow: sel ? [BoxShadow(
                                        color: AppColors.accent.withValues(alpha: 0.4),
                                        blurRadius: 8, spreadRadius: 1)] : null,
                                    ),
                                    child: sel
                                        ? const Center(child: Icon(Icons.check, color: Colors.white, size: 20))
                                        : null,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(c.colorName,
                                    style: const TextStyle(color: AppColors.textPrimary,
                                        fontSize: 10, fontWeight: FontWeight.w500),
                                    maxLines: 1, overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center),
                                Text(c.colorCode,
                                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 9),
                                    maxLines: 1, overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center),
                              ]),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
