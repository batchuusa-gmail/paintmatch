import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:cached_network_image/cached_network_image.dart';
import '../config/app_theme.dart';
import '../models/paint_color.dart';
import '../models/room_dimensions.dart';
import '../services/api_service.dart';
import '../services/supabase_service.dart';
import '../utils/color_ext.dart';
import '../widgets/cost_estimate_sheet.dart';

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
// Widget
// ─────────────────────────────────────────────────────────────────────────────
class RoomPreviewScreen extends StatefulWidget {
  final String originalImageUrl;
  final String? renderedImageUrl;
  final String selectedHex;
  final String selectedColorName;
  final File? imageFile;
  final String? wallHex;
  final List<PaintColor>? vendorMatches;  // passed from palette screen for cost estimate

  const RoomPreviewScreen({
    super.key,
    required this.originalImageUrl,
    required this.renderedImageUrl,
    required this.selectedHex,
    required this.selectedColorName,
    this.imageFile,
    this.wallHex,
    this.vendorMatches,
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

  // Image data
  ui.Image? _srcImage;
  Uint8List? _srcJpeg;          // original
  Uint8List? _srcJpegSmall;     // compressed for API calls
  Uint8List? _renderedBytes;

  // All-surface renders — key: surface → rendered PNG bytes for current color
  final Map<String, Uint8List> _surfaceRenders = {};
  String _renderedColorHex = ''; // which color the renders are for

  // Room measurements — fetched in parallel with first AI render
  DimensionEstimate? _dimensionEstimate;

  // ── Precision auto-segmentation ───────────────────────────────────────────
  // Pre-computed SAM masks for every surface, loaded once on init.
  // Keys: 'wall', 'ceiling', 'floor', 'trim'
  final Map<String, Uint8List> _surfaceMasks = {};
  final Map<String, int> _surfaceMaskW = {};
  final Map<String, int> _surfaceMaskH = {};
  bool _segmenting = false;    // true while backend is running
  bool _segmentStarted = false; // guard — run analysis exactly once
  bool _segmentFailed = false;
  bool _showedSurfacePicker = false;  // only auto-show once per image

  @override
  void initState() {
    super.initState();
    _selectedHex = widget.selectedHex;
    _selectedColorName = widget.selectedColorName;
    _loadImage();
    // Auto-segment all surfaces exactly once when screen opens
    if (widget.imageFile != null && !_segmentStarted) {
      _segmentStarted = true;
      _autoSegmentRoom();
    }
  }

  Future<void> _loadImage() async {
    if (widget.imageFile == null) return;
    setState(() { _rendering = true; _renderStatus = 'Loading image…'; });
    try {
      final rawBytes = await widget.imageFile!.readAsBytes();
      _srcJpeg = rawBytes;

      // Decode for display
      final codec = await ui.instantiateImageCodec(rawBytes);
      final frame = await codec.getNextFrame();
      _srcImage = frame.image;

      // Compress to max 768px for API — drastically reduces upload size
      final w = _srcImage!.width;
      final h = _srcImage!.height;
      final maxDim = 768;
      if (w > maxDim || h > maxDim) {
        final scale = maxDim / (w > h ? w : h);
        final tw = (w * scale).round();
        final th = (h * scale).round();
        final smallCodec = await ui.instantiateImageCodec(
          rawBytes, targetWidth: tw, targetHeight: th);
        final smallFrame = await smallCodec.getNextFrame();
        final pngBd = await smallFrame.image.toByteData(
            format: ui.ImageByteFormat.png);
        _srcJpegSmall = pngBd?.buffer.asUint8List();
      } else {
        _srcJpegSmall = rawBytes;
      }
    } catch (e) {
      if (mounted) setState(() { _renderStatus = 'Failed to load: $e'; });
    } finally {
      if (mounted) setState(() => _rendering = false);
    }
  }

  // ── Auto-segmentation ─────────────────────────────────────────────────────

  Future<void> _autoSegmentRoom() async {
    if (mounted) setState(() { _segmenting = true; _segmentFailed = false; });
    try {
      final masks = await ApiService().segmentRoom(widget.imageFile!);
      for (final entry in masks.entries) {
        try {
          final pngBytes = base64Decode(entry.value);
          final codec = await ui.instantiateImageCodec(pngBytes);
          final frame = await codec.getNextFrame();
          final maskImg = frame.image;
          final bd = await maskImg.toByteData(format: ui.ImageByteFormat.rawRgba);
          if (bd != null && mounted) {
            _surfaceMasks[entry.key] = bd.buffer.asUint8List();
            _surfaceMaskW[entry.key] = maskImg.width;
            _surfaceMaskH[entry.key] = maskImg.height;
          }
        } catch (_) {}
      }
      if (mounted) {
        setState(() => _segmenting = false);
        if (!_showedSurfacePicker && _surfaceMasks.isNotEmpty) {
          _showedSurfacePicker = true;
          _promptSurfaceSelection();
        }
      }
    } catch (e) {
      debugPrint('[AutoSegment] $e');
      if (mounted) setState(() { _segmenting = false; _segmentFailed = true; });
    }
  }

  /// Auto-show surface picker after room analysis completes.
  void _promptSurfaceSelection() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      builder: (_) => _SurfacePickerSheet(
        availableSurfaces: _surfaceMasks.keys.toList(),
        onPick: (surface) {
          Navigator.of(context).pop();
          setState(() {
            _selectedSurface = surface;
            _renderedBytes = null;
          });
          _aiRenderAll();
        },
      ),
    );
  }

  /// Renders ALL surfaces in one backend trip (parallel on server).
  /// After this, switching surfaces is instant — just swap the cached image.
  Future<void> _aiRenderAll() async {
    if (_srcJpeg == null) return;

    // Already have renders for this color — just show current surface
    if (_renderedColorHex == _selectedHex && _surfaceRenders.isNotEmpty) {
      _showSurfaceRender(_selectedSurface);
      return;
    }

    setState(() {
      _rendering = true;
      _renderedBytes = null;
      _renderStatus = 'Painting all surfaces…';
    });
    try {
      final imageBytes = _srcJpegSmall ?? _srcJpeg!;
      final renders = await ApiService().aiRenderAll(
        imageBase64: base64Encode(imageBytes),
        colorHex: _selectedHex,
        colorName: _selectedColorName,
      );

      _surfaceRenders.clear();
      for (final entry in renders.entries) {
        _surfaceRenders[entry.key] = base64Decode(entry.value);
      }
      _renderedColorHex = _selectedHex;

      _showSurfaceRender(_selectedSurface);
    } catch (e) {
      debugPrint('[AIRenderAll] $e');
      if (mounted) {
        setState(() { _rendering = false; _renderStatus = ''; });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Render failed: $e'),
          backgroundColor: Colors.orange.shade800,
        ));
      }
    } finally {
      if (mounted) setState(() => _rendering = false);
    }
  }

  /// Show already-rendered surface from cache — instant, no network call.
  void _showSurfaceRender(String surface) {
    final bytes = _surfaceRenders[surface];
    if (bytes != null && mounted) {
      setState(() { _renderedBytes = bytes; _renderStatus = ''; });
    }
  }

  void _onImageTap(TapUpDetails details, BoxConstraints box) {
    _aiRenderAll();
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
        _renderedBytes = null;
        _surfaceRenders.clear(); // new color = re-render all
      });
      _aiRenderAll();
    }
  }

  Widget _buildOriginalImage() {
    if (widget.imageFile != null) {
      return Image.file(widget.imageFile!, fit: BoxFit.cover);
    }
    if (widget.originalImageUrl.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: widget.originalImageUrl,
        fit: BoxFit.cover,
        placeholder: (_, __) => Container(
          color: AppColors.card,
          child: const Center(
            child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2)),
        ),
        errorWidget: (_, __, ___) => Container(
          color: AppColors.card,
          child: const Icon(Icons.broken_image_outlined,
              size: 48, color: AppColors.textSecondary),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Future<void> _saveToProject() async {
    if (!SupabaseService().isSignedIn) { context.push('/login'); return; }
    setState(() => _saving = true);
    try {
      // Upload whichever image we have — rendered PNG preferred, fall back to original
      String? renderedUrl;
      String? originalUrl;

      if (_renderedBytes != null) {
        renderedUrl = await SupabaseService().uploadRoomImage(
          _renderedBytes!, ext: 'png');
      }
      if (widget.imageFile != null) {
        final bytes = await widget.imageFile!.readAsBytes();
        originalUrl = await SupabaseService().uploadRoomImage(
          bytes, ext: 'jpg');
      }

      await SupabaseService().saveProject(
        projectName:      _selectedColorName,
        roomImageUrl:     originalUrl ?? renderedUrl,
        renderedImageUrl: renderedUrl ?? originalUrl,
        selectedHex:      _selectedHex,
      );
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Project saved!')));
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
                    // ── Saved image view (no imageFile = no tap-to-paint) ──
                    : widget.imageFile == null
                        ? _buildOriginalImage()
                    // ── Analyzing room overlay ──
                    : _segmenting
                        ? Stack(fit: StackFit.expand, children: [
                            _buildOriginalImage(),
                            Container(color: Colors.black.withValues(alpha: 0.55)),
                            Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                              const SizedBox(
                                width: 36, height: 36,
                                child: CircularProgressIndicator(
                                    color: AppColors.accent, strokeWidth: 2.5),
                              ),
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(20)),
                                child: const Column(mainAxisSize: MainAxisSize.min, children: [
                                  Text('Analyzing your room…',
                                      style: TextStyle(color: Colors.white,
                                          fontSize: 15, fontWeight: FontWeight.w700)),
                                  SizedBox(height: 4),
                                  Text('Mapping walls, ceiling & floor with AI',
                                      style: TextStyle(color: AppColors.textSecondary,
                                          fontSize: 12)),
                                ]),
                              ),
                            ])),
                          ])
                    // ── Tap-to-paint mode (fallback when no masks) ──
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
                  // Segmentation status banner
                  if (_surfaceMasks.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(children: [
                        const Icon(Icons.check_circle,
                            color: AppColors.accent, size: 13),
                        const SizedBox(width: 6),
                        Expanded(child: Text(
                          '${_surfaceMasks.length} surfaces ready — tap chip below to paint',
                          style: const TextStyle(
                              color: AppColors.accent,
                              fontSize: 11,
                              fontWeight: FontWeight.w600),
                        )),
                        GestureDetector(
                          onTap: _promptSurfaceSelection,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.accentDim,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppColors.accent, width: 0.8),
                            ),
                            child: const Text('Pick surface',
                                style: TextStyle(color: AppColors.accent,
                                    fontSize: 11, fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ]),
                    )
                  else if (_segmentFailed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(children: [
                        const Icon(Icons.touch_app,
                            color: AppColors.textSecondary, size: 13),
                        const SizedBox(width: 6),
                        const Text('Tap the surface to paint it',
                            style: TextStyle(
                                color: AppColors.textSecondary, fontSize: 11)),
                      ]),
                    ),

                  Row(children: _surfaces.map((s) {
                    final sel = _selectedSurface == s.id;
                    final hasMask = _surfaceMasks.containsKey(s.id);
                    return Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: GestureDetector(
                        onTap: _rendering ? null : () {
                          setState(() {
                            _selectedSurface = s.id;
                            _renderedBytes = null;
                          });
                          // If renders exist for current color, swap instantly
                          if (_surfaceRenders.containsKey(s.id) &&
                              _renderedColorHex == _selectedHex) {
                            _showSurfaceRender(s.id);
                          } else {
                            _aiRenderAll();
                          }
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: sel ? AppColors.accentDim : AppColors.card,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: sel
                                  ? AppColors.accent
                                  : hasMask
                                      ? AppColors.accent.withValues(alpha: 0.4)
                                      : AppColors.border,
                              width: sel ? 1.5 : 1),
                          ),
                          child: Column(children: [
                            Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Icon(s.icon, size: 20,
                                    color: sel ? AppColors.accent : AppColors.textSecondary),
                                if (hasMask && !sel)
                                  Positioned(
                                    top: -4, right: -6,
                                    child: Container(
                                      width: 8, height: 8,
                                      decoration: const BoxDecoration(
                                        color: AppColors.accent,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
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
            child: Row(children: [
              // Cost estimate button
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.calculate_outlined,
                      color: AppColors.accent, size: 18),
                  label: const Text('Cost',
                      style: TextStyle(color: AppColors.accent, fontSize: 14)),
                  onPressed: () async {
                    // Fetch dimensions on demand (only when user taps Cost)
                    if (_dimensionEstimate == null && widget.imageFile != null) {
                      _dimensionEstimate = await ApiService().estimateDimensions(widget.imageFile!);
                    }
                    if (context.mounted) {
                      showCostEstimateSheet(
                        context,
                        vendorMatches: widget.vendorMatches ?? [],
                        paletteName: _selectedColorName,
                        estimate: _dimensionEstimate,
                      );
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    side: const BorderSide(color: AppColors.accent),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Save button
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  icon: _saving
                      ? const SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                      : const Icon(Icons.bookmark_add_outlined, size: 18, color: Colors.black),
                  label: const Text('Save to Project'),
                  onPressed: _saving ? null : _saveToProject,
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                ),
              ),
            ]),
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
// Surface Picker Bottom Sheet — shown automatically after room analysis
// ─────────────────────────────────────────────────────────────────────────────
class _SurfacePickerSheet extends StatelessWidget {
  final List<String> availableSurfaces;
  final void Function(String surface) onPick;

  const _SurfacePickerSheet({
    required this.availableSurfaces,
    required this.onPick,
  });

  static const _surfaceInfo = {
    'wall':    (Icons.format_paint, 'Walls'),
    'ceiling': (Icons.roofing, 'Ceiling'),
    'floor':   (Icons.layers, 'Floor'),
    'trim':    (Icons.border_all_outlined, 'Trim'),
  };

  @override
  Widget build(BuildContext context) {
    // Keep order: wall, ceiling, floor, trim
    final ordered = ['wall', 'ceiling', 'floor', 'trim']
        .where(availableSurfaces.contains)
        .toList();

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 20),
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2)),
          ),
          Row(children: [
            const Icon(Icons.check_circle, color: AppColors.accent, size: 18),
            const SizedBox(width: 8),
            Text('Room analyzed!',
                style: GoogleFonts.playfairDisplay(
                    color: AppColors.textPrimary,
                    fontSize: 20, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 6),
          const Text('What would you like to paint?',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
          const SizedBox(height: 24),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: ordered.map((id) {
              final info = _surfaceInfo[id];
              final icon = info?.$1 ?? Icons.format_paint;
              final label = info?.$2 ?? id;
              return GestureDetector(
                onTap: () => onPick(id),
                child: Container(
                  width: (MediaQuery.of(context).size.width - 64) / 2,
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.accent.withValues(alpha: 0.4)),
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(icon, color: AppColors.accent, size: 28),
                    const SizedBox(height: 10),
                    Text(label,
                        style: const TextStyle(color: AppColors.textPrimary,
                            fontSize: 15, fontWeight: FontWeight.w600)),
                  ]),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('I\'ll tap manually',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          ),
        ],
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
