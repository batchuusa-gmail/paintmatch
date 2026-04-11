import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:before_after/before_after.dart';
import 'package:cached_network_image/cached_network_image.dart';
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
  String _selectedSurface = 'wall'; // wall | ceiling | floor

  ui.Image? _srcImage;
  Uint8List? _srcRgba;
  Uint8List? _srcJpeg;      // raw JPEG to send to backend
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

      // dart:ui applies EXIF rotation automatically
      final codec = await ui.instantiateImageCodec(rawBytes);
      final frame = await codec.getNextFrame();
      final img = frame.image;
      final byteData = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      _srcImage = img;
      _srcRgba = byteData!.buffer.asUint8List();

      await _runSegmentAndPaint(_selectedSurface);
    } catch (e) {
      if (mounted) setState(() { _rendering = false; _renderStatus = 'Failed: $e'; });
    }
  }

  Future<void> _runSegmentAndPaint(String surface) async {
    if (_srcImage == null || _srcRgba == null || _srcJpeg == null) return;
    setState(() { _rendering = true; _renderedBytes = null; _renderStatus = 'Detecting $surface…'; });
    try {
      // 1. Get AI wall mask from backend
      final imageBase64 = base64Encode(_srcJpeg!);
      final maskBase64 = await ApiService().segmentWall(
        imageBase64: imageBase64,
        surface: surface,
      );

      setState(() => _renderStatus = 'Painting $surface…');

      // 2. Decode mask PNG → RGBA bytes
      final maskBytes = base64Decode(maskBase64);
      final maskCodec = await ui.instantiateImageCodec(maskBytes);
      final maskFrame = await maskCodec.getNextFrame();
      final maskImg = maskFrame.image;
      final maskByteData = await maskImg.toByteData(format: ui.ImageByteFormat.rawRgba);
      final mask = maskByteData!.buffer.asUint8List();

      // 3. Resize mask to match src image if needed
      final srcW = _srcImage!.width, srcH = _srcImage!.height;
      final maskW = maskImg.width, maskH = maskImg.height;

      // 4. Apply color blend where mask is white
      final target = HexColor.fromHex(widget.selectedHex);
      final tR = target.red, tG = target.green, tB = target.blue;
      final src = _srcRgba!;
      final out = Uint8List.fromList(src);

      const blend = 0.72;
      final total = srcW * srcH;

      for (int i = 0; i < total; i++) {
        final srcBase = i * 4;
        // Map src pixel to mask pixel (mask may be different size)
        final mx = ((i % srcW) * maskW / srcW).round().clamp(0, maskW - 1);
        final my = ((i ~/ srcW) * maskH / srcH).round().clamp(0, maskH - 1);
        final maskBase = (my * maskW + mx) * 4;

        final maskVal = mask[maskBase]; // R channel of mask (0=black, 255=white)
        if (maskVal > 127) {
          final r = src[srcBase], g = src[srcBase + 1], b = src[srcBase + 2];
          out[srcBase]     = (r * (1 - blend) + tR * blend).round().clamp(0, 255);
          out[srcBase + 1] = (g * (1 - blend) + tG * blend).round().clamp(0, 255);
          out[srcBase + 2] = (b * (1 - blend) + tB * blend).round().clamp(0, 255);
        }
      }

      // 5. Encode result as PNG
      final c = Completer<ui.Image>();
      ui.decodeImageFromPixels(out, srcW, srcH, ui.PixelFormat.rgba8888, c.complete);
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
          // Color chip + surface selector
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Row(
              children: [
                Container(width: 22, height: 22,
                  decoration: BoxDecoration(color: swatchColor,
                    borderRadius: BorderRadius.circular(5), border: Border.all(color: AppColors.border))),
                const SizedBox(width: 8),
                Expanded(child: Text(widget.selectedColorName,
                    style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14),
                    overflow: TextOverflow.ellipsis)),
              ],
            ),
          ),

          // Surface selector chips
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Row(
              children: [
                const Text('Paint:', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                const SizedBox(width: 10),
                ...[
                  ('wall', Icons.format_paint),
                  ('ceiling', Icons.roofing),
                  ('floor', Icons.layers),
                ].map((item) {
                  final selected = _selectedSurface == item.$1;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: _rendering ? null : () {
                        setState(() => _selectedSurface = item.$1);
                        _runSegmentAndPaint(item.$1);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: selected ? AppColors.accentDim : AppColors.card,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: selected ? AppColors.accent : AppColors.border,
                            width: selected ? 1.5 : 1,
                          ),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(item.$2, size: 13,
                            color: selected ? AppColors.accent : AppColors.textSecondary),
                          const SizedBox(width: 5),
                          Text(item.$1[0].toUpperCase() + item.$1.substring(1),
                            style: TextStyle(
                              color: selected ? AppColors.accent : AppColors.textSecondary,
                              fontSize: 12, fontWeight: selected ? FontWeight.w600 : FontWeight.normal)),
                        ]),
                      ),
                    ),
                  );
                }),
              ],
            ),
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
                                onPressed: () => _runSegmentAndPaint(_selectedSurface),
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
