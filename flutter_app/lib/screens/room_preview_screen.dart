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
  String? _renderedUrl;
  bool _rendering = false;
  String _renderStatus = 'Rendering your room…';

  @override
  void initState() {
    super.initState();
    _renderedUrl = widget.renderedImageUrl;
    if (_renderedUrl == null && widget.imageFile != null) {
      _triggerRender();
    }
  }

  Future<void> _triggerRender() async {
    setState(() { _rendering = true; _renderStatus = 'Creating wall mask…'; });
    try {
      // Read raw JPEG bytes — Flutter Image.file handles EXIF rotation for display
      // Backend will apply exif_transpose before sending to Replicate
      final bytes = await widget.imageFile!.readAsBytes();
      final imageBase64 = base64Encode(bytes);

      // Decode image — dart:ui applies EXIF correction here
      // We use this ONLY for mask generation (correct dimensions)
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final img = frame.image;

      final maskBase64 = widget.wallHex != null
          ? await _generateWallMask(img, widget.wallHex!)
          : await _whiteMask(img);

      setState(() => _renderStatus = 'AI is painting your room (~30s)…');

      final result = await ApiService().renderRoom(
        imageBase64: imageBase64,
        wallMaskBase64: maskBase64,
        targetHex: widget.selectedHex,
        finish: 'eggshell',
      );

      debugPrint('[Render] result: $result');

      if (mounted) setState(() => _renderedUrl = result['rendered_image_url']);
    } catch (e, stack) {
      debugPrint('[Render] error: $e\n$stack');
      if (mounted) setState(() => _renderStatus = 'Render failed: $e');
    } finally {
      if (mounted) setState(() => _rendering = false);
    }
  }

  /// White mask covering the entire image (fallback when wall_hex unknown)
  Future<String> _whiteMask(ui.Image img) async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      Paint()..color = Colors.white,
    );
    final maskImg = await recorder.endRecording().toImage(img.width, img.height);
    final byteData = await maskImg.toByteData(format: ui.ImageByteFormat.png);
    return base64Encode(byteData!.buffer.asUint8List());
  }

  /// Smart mask: white where pixels are close to wall color, black elsewhere
  Future<String> _generateWallMask(ui.Image img, String wallHex) async {
    final wallColor = HexColor.fromHex(wallHex);
    final wR = wallColor.red, wG = wallColor.green, wB = wallColor.blue;

    final imgByteData = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    final src = imgByteData!.buffer.asUint8List();

    final mask = Uint8List(img.width * img.height * 4);
    const threshold = 70;
    final total = img.width * img.height;
    for (int i = 0; i < total; i++) {
      final b = i * 4;
      final dist = ((src[b] - wR).abs() + (src[b + 1] - wG).abs() + (src[b + 2] - wB).abs()) ~/ 3;
      final v = dist < threshold ? 255 : 0;
      mask[b] = v; mask[b + 1] = v; mask[b + 2] = v; mask[b + 3] = 255;
    }

    final c = Completer<ui.Image>();
    ui.decodeImageFromPixels(mask, img.width, img.height, ui.PixelFormat.rgba8888, c.complete);
    final maskImg = await c.future;
    final byteData = await maskImg.toByteData(format: ui.ImageByteFormat.png);
    return base64Encode(byteData!.buffer.asUint8List());
  }

  Widget _buildOriginalImage() {
    // Image.file handles EXIF rotation automatically on iOS — no conversion needed
    if (widget.imageFile != null) {
      return Image.file(widget.imageFile!, fit: BoxFit.cover);
    }
    final url = widget.originalImageUrl;
    if (url.startsWith('/') || url.startsWith('file://')) {
      return Image.file(File(url), fit: BoxFit.cover);
    }
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      placeholder: (_, __) => Container(color: AppColors.card),
      errorWidget: (_, __, ___) => Container(color: AppColors.card),
    );
  }

  Widget _buildRenderedImage(String url) {
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      placeholder: (_, __) => Container(color: AppColors.card),
      errorWidget: (_, __, ___) => Container(color: AppColors.card),
    );
  }

  Future<void> _saveToProject() async {
    if (!SupabaseService().isSignedIn) { context.push('/login'); return; }
    setState(() => _saving = true);
    try {
      await SupabaseService().saveProject(
        projectName: widget.selectedColorName,
        renderedImageUrl: _renderedUrl,
        selectedHex: widget.selectedHex,
      );
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved to projects!')),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $e'), backgroundColor: AppColors.error),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _shareImage() async {
    try {
      Uint8List bytes;
      final url = _renderedUrl ?? widget.originalImageUrl;
      if (widget.imageFile != null && _renderedUrl == null) {
        bytes = await widget.imageFile!.readAsBytes();
      } else if (url.startsWith('/') || url.startsWith('file://')) {
        bytes = await File(url).readAsBytes();
      } else {
        bytes = (await http.get(Uri.parse(url))).bodyBytes;
      }
      final temp = await getTemporaryDirectory();
      final file = File('${temp.path}/paintmatch_preview.png');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles([XFile(file.path)], text: 'My room in ${widget.selectedColorName} via PaintMatch');
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final swatchColor = HexColor.fromHex(widget.selectedHex);
    final hasRender = _renderedUrl != null;

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
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: Row(
              children: [
                Container(
                  width: 26, height: 26,
                  decoration: BoxDecoration(
                    color: swatchColor,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.border),
                  ),
                ),
                const SizedBox(width: 10),
                Text(widget.selectedColorName,
                    style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 15)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Text(widget.selectedHex.toUpperCase(),
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 11, fontFamily: 'monospace')),
                ),
              ],
            ),
          ),

          // Image area
          Expanded(
            child: hasRender
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      BeforeAfter(
                        thumbColor: AppColors.accent,
                        before: _buildOriginalImage(),
                        after: _buildRenderedImage(_renderedUrl!),
                      ),
                      // Drag hint overlay
                      Positioned(
                        bottom: 16,
                        left: 0, right: 0,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.swap_horiz, color: Colors.white, size: 15),
                                SizedBox(width: 6),
                                Text('Drag to compare',
                                    style: TextStyle(color: Colors.white, fontSize: 12)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      _buildOriginalImage(),
                      Container(color: Colors.black54),
                      Center(
                        child: Container(
                          margin: const EdgeInsets.all(40),
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: AppColors.card,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_rendering)
                                const CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2),
                              if (_rendering) const SizedBox(height: 16),
                              Text(_renderStatus,
                                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                                  textAlign: TextAlign.center),
                              if (!_rendering && _renderedUrl == null) ...[
                                const SizedBox(height: 16),
                                FilledButton(
                                  onPressed: _triggerRender,
                                  child: const Text('Retry'),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
          ),

          // Action bar
          Container(
            color: AppColors.bottomNav,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Row(
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.share_outlined, size: 18),
                  label: const Text('Share'),
                  onPressed: _shareImage,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
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
          ),
        ],
      ),
    );
  }
}
