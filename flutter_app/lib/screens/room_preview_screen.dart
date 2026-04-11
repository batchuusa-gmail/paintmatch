import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:before_after/before_after.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../config/app_theme.dart';
import '../services/api_service.dart';
import '../services/supabase_service.dart';
import '../utils/color_ext.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Isolate payload — everything compute() needs (no ui.Image allowed across isolates)
// ─────────────────────────────────────────────────────────────────────────────
class _BlendParams {
  final Uint8List srcRgba;
  final int srcW;
  final int srcH;
  final Uint8List maskRgba;
  final int maskW;
  final int maskH;
  final int tR;
  final int tG;
  final int tB;

  const _BlendParams({
    required this.srcRgba,
    required this.srcW,
    required this.srcH,
    required this.maskRgba,
    required this.maskW,
    required this.maskH,
    required this.tR,
    required this.tG,
    required this.tB,
  });
}

/// Runs in an isolate — no Flutter UI access.
/// Overlay blend: preserves luminance texture, applies target hue.
Uint8List _blendIsolate(_BlendParams p) {
  final src = p.srcRgba;
  final mask = p.maskRgba;
  final out = Uint8List.fromList(src);

  final total = p.srcW * p.srcH;
  for (int i = 0; i < total; i++) {
    final sb = i * 4;

    // Bilinear-nearest mask lookup — correct even when mask != src size
    final mx = ((i % p.srcW) * p.maskW / p.srcW).round().clamp(0, p.maskW - 1);
    final my = ((i ~/ p.srcW) * p.maskH / p.srcH).round().clamp(0, p.maskH - 1);
    final maskVal = mask[(my * p.maskW + mx) * 4]; // R channel

    if (maskVal <= 127) continue;

    final r = src[sb] / 255.0;
    final g = src[sb + 1] / 255.0;
    final b = src[sb + 2] / 255.0;
    final tR = p.tR / 255.0;
    final tG = p.tG / 255.0;
    final tB = p.tB / 255.0;

    // Overlay blend: preserves wall texture (shadows/highlights), applies color
    // Formula: if base < 0.5 → 2*base*blend, else → 1 - 2*(1-base)*(1-blend)
    double ovR = r < 0.5 ? 2 * r * tR : 1 - 2 * (1 - r) * (1 - tR);
    double ovG = g < 0.5 ? 2 * g * tG : 1 - 2 * (1 - g) * (1 - tG);
    double ovB = b < 0.5 ? 2 * b * tB : 1 - 2 * (1 - b) * (1 - tB);

    // Blend 80% overlay result with 20% original (keeps some texture detail)
    const strength = 0.80;
    out[sb]     = ((ovR * strength + r * (1 - strength)) * 255).round().clamp(0, 255);
    out[sb + 1] = ((ovG * strength + g * (1 - strength)) * 255).round().clamp(0, 255);
    out[sb + 2] = ((ovB * strength + b * (1 - strength)) * 255).round().clamp(0, 255);
  }

  return out;
}

// ─────────────────────────────────────────────────────────────────────────────
// Screen
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

  // Multi-surface selection
  final Set<String> _selectedSurfaces = {'wall'};

  ui.Image? _srcImage;
  Uint8List? _srcRgba;
  Uint8List? _srcJpeg;
  Uint8List? _renderedBytes;

  @override
  void initState() {
    super.initState();
    _loadAndRender();
  }

  Future<void> _loadAndRender() async {
    setState(() { _rendering = true; _renderStatus = 'Loading image…'; });
    try {
      final rawBytes = await widget.imageFile!.readAsBytes();
      _srcJpeg = rawBytes;

      final codec = await ui.instantiateImageCodec(rawBytes);
      final frame = await codec.getNextFrame();
      final img = frame.image;
      final byteData = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      _srcImage = img;
      _srcRgba = byteData!.buffer.asUint8List();

      await _runSegmentAndPaint();
    } catch (e) {
      if (mounted) setState(() { _rendering = false; _renderStatus = 'Failed: $e'; });
    }
  }

  Future<void> _runSegmentAndPaint() async {
    if (_srcImage == null || _srcRgba == null || _srcJpeg == null) return;
    final surfaceLabel = _selectedSurfaces.join(',');
    setState(() { _rendering = true; _renderedBytes = null; _renderStatus = 'Detecting ${_selectedSurfaces.join(' + ')}…'; });

    try {
      // 1. AI segmentation — returns clean binary mask PNG at orig resolution
      final imageBase64 = base64Encode(_srcJpeg!);
      final maskBase64 = await ApiService().segmentWall(
        imageBase64: imageBase64,
        surface: surfaceLabel,
      );

      setState(() => _renderStatus = 'Painting…');

      // 2. Decode mask
      final maskBytes = base64Decode(maskBase64);
      final maskCodec = await ui.instantiateImageCodec(maskBytes);
      final maskFrame = await maskCodec.getNextFrame();
      final maskImg = maskFrame.image;
      final maskByteData = await maskImg.toByteData(format: ui.ImageByteFormat.rawRgba);
      final maskRgba = maskByteData!.buffer.asUint8List();

      // 3. Blend in isolate (Priority 2: compute() — no UI thread blocking)
      final target = HexColor.fromHex(widget.selectedHex);
      final params = _BlendParams(
        srcRgba: _srcRgba!,
        srcW: _srcImage!.width,
        srcH: _srcImage!.height,
        maskRgba: maskRgba,
        maskW: maskImg.width,
        maskH: maskImg.height,
        tR: target.red,
        tG: target.green,
        tB: target.blue,
      );

      final out = await compute(_blendIsolate, params);

      // 4. Encode result as PNG (back on main isolate — ui.* only works here)
      final c = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        out, _srcImage!.width, _srcImage!.height,
        ui.PixelFormat.rgba8888, c.complete,
      );
      final rendered = await c.future;
      final bd = await rendered.toByteData(format: ui.ImageByteFormat.png);

      if (mounted) setState(() => _renderedBytes = bd!.buffer.asUint8List());
    } catch (e, s) {
      debugPrint('[Render] $e\n$s');
      if (mounted) setState(() => _renderStatus = 'Failed: $e');
    } finally {
      if (mounted) setState(() => _rendering = false);
    }
  }

  void _toggleSurface(String surface) {
    if (_rendering) return;
    setState(() {
      if (_selectedSurfaces.contains(surface)) {
        if (_selectedSurfaces.length > 1) _selectedSurfaces.remove(surface);
      } else {
        _selectedSurfaces.add(surface);
      }
    });
    _runSegmentAndPaint();
  }

  Widget _buildOriginalImage() {
    if (widget.imageFile != null) return Image.file(widget.imageFile!, fit: BoxFit.cover);
    final url = widget.originalImageUrl;
    if (url.startsWith('/') || url.startsWith('file://')) return Image.file(File(url), fit: BoxFit.cover);
    return CachedNetworkImage(imageUrl: url, fit: BoxFit.cover,
      placeholder: (_, __) => Container(color: AppColors.card),
      errorWidget: (_, __, ___) => Container(color: AppColors.card));
  }

  Future<void> _saveToProject() async {
    if (!SupabaseService().isSignedIn) { context.push('/login'); return; }
    setState(() => _saving = true);
    try {
      await SupabaseService().saveProject(
        projectName: widget.selectedColorName,
        renderedImageUrl: null,
        selectedHex: widget.selectedHex,
      );
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved!')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $e'), backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _shareImage() async {
    try {
      final bytes = _renderedBytes ?? await widget.imageFile!.readAsBytes();
      final temp = await getTemporaryDirectory();
      final file = File('${temp.path}/paintmatch_preview.png');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles([XFile(file.path)], text: 'My room in ${widget.selectedColorName} via PaintMatch');
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final swatchColor = HexColor.fromHex(widget.selectedHex);
    final hasRender = _renderedBytes != null;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: AppColors.textPrimary, size: 18),
          onPressed: () => context.pop(),
        ),
        title: Text('Room Preview',
            style: GoogleFonts.playfairDisplay(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
      ),
      body: Column(
        children: [
          // Color chip
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Row(children: [
              Container(width: 22, height: 22,
                decoration: BoxDecoration(color: swatchColor,
                  borderRadius: BorderRadius.circular(5), border: Border.all(color: AppColors.border))),
              const SizedBox(width: 8),
              Expanded(child: Text(widget.selectedColorName,
                style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14),
                overflow: TextOverflow.ellipsis)),
            ]),
          ),

          // Multi-surface selector (Priority 5)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Row(children: [
              const Text('Paint:', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              const SizedBox(width: 10),
              ...[
                ('wall',    Icons.format_paint, 'Wall'),
                ('ceiling', Icons.roofing,      'Ceiling'),
                ('floor',   Icons.layers,       'Floor'),
              ].map((item) {
                final selected = _selectedSurfaces.contains(item.$1);
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => _toggleSurface(item.$1),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: selected ? AppColors.accentDim : AppColors.card,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: selected ? AppColors.accent : AppColors.border,
                          width: selected ? 1.5 : 1),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(item.$2, size: 13,
                          color: selected ? AppColors.accent : AppColors.textSecondary),
                        const SizedBox(width: 5),
                        Text(item.$3,
                          style: TextStyle(
                            color: selected ? AppColors.accent : AppColors.textSecondary,
                            fontSize: 12,
                            fontWeight: selected ? FontWeight.w600 : FontWeight.normal)),
                      ]),
                    ),
                  ),
                );
              }),
            ]),
          ),

          // Image area
          Expanded(
            child: _rendering
                ? Stack(fit: StackFit.expand, children: [
                    _buildOriginalImage(),
                    Container(color: Colors.black54),
                    Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2),
                      const SizedBox(height: 16),
                      Text(_renderStatus,
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                        textAlign: TextAlign.center),
                    ])),
                  ])
                : hasRender
                    ? Stack(children: [
                        Positioned.fill(child: BeforeAfter(
                          thumbColor: AppColors.accent,
                          before: _buildOriginalImage(),
                          after: Image.memory(_renderedBytes!, fit: BoxFit.cover),
                        )),
                        Positioned(bottom: 16, left: 0, right: 0,
                          child: IgnorePointer(child: Center(child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(20)),
                            child: const Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.swap_horiz, color: Colors.white, size: 15),
                              SizedBox(width: 6),
                              Text('Drag to compare', style: TextStyle(color: Colors.white, fontSize: 12)),
                            ]),
                          )))),
                      ])
                    : Stack(fit: StackFit.expand, children: [
                        _buildOriginalImage(),
                        if (_renderStatus.isNotEmpty)
                          Center(child: Container(
                            margin: const EdgeInsets.all(40),
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: AppColors.card, borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppColors.border)),
                            child: Column(mainAxisSize: MainAxisSize.min, children: [
                              Text(_renderStatus,
                                style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                                textAlign: TextAlign.center),
                              const SizedBox(height: 16),
                              FilledButton(
                                onPressed: _runSegmentAndPaint,
                                child: const Text('Retry')),
                            ]),
                          )),
                      ]),
          ),

          // Action bar
          Container(
            color: AppColors.bottomNav,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            child: Row(children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.share_outlined, size: 18),
                label: const Text('Share'),
                onPressed: _shareImage,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 20)),
              ),
              const SizedBox(width: 12),
              Expanded(child: FilledButton.icon(
                icon: _saving
                    ? const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                    : const Icon(Icons.bookmark_add_outlined, size: 18, color: Colors.black),
                label: const Text('Save to Project'),
                onPressed: _saving ? null : _saveToProject,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              )),
            ]),
          ),
        ],
      ),
    );
  }
}
