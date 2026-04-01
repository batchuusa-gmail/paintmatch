import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:before_after/before_after.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:go_router/go_router.dart';

import '../services/supabase_service.dart';
import '../utils/color_ext.dart';

class RoomPreviewScreen extends StatefulWidget {
  final String originalImageUrl;    // local file path or remote URL
  final String? renderedImageUrl;   // remote URL from Replicate/Supabase
  final String selectedHex;
  final String selectedColorName;

  const RoomPreviewScreen({
    super.key,
    required this.originalImageUrl,
    required this.renderedImageUrl,
    required this.selectedHex,
    required this.selectedColorName,
  });

  @override
  State<RoomPreviewScreen> createState() => _RoomPreviewScreenState();
}

class _RoomPreviewScreenState extends State<RoomPreviewScreen> {
  bool _saving = false;

  Widget _buildImage(String url) {
    if (url.startsWith('/') || url.startsWith('file://')) {
      return Image.file(File(url), fit: BoxFit.cover);
    }
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      placeholder: (_, __) => Container(color: Colors.grey[200]),
      errorWidget: (_, __, ___) => Container(color: Colors.grey[300]),
    );
  }

  Future<void> _saveToProject() async {
    if (!SupabaseService().isSignedIn) {
      context.push('/login');
      return;
    }
    setState(() => _saving = true);
    try {
      await SupabaseService().saveProject(
        projectName: widget.selectedColorName,
        renderedImageUrl: widget.renderedImageUrl,
        selectedHex: widget.selectedHex,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved to projects!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _shareImage() async {
    final url = widget.renderedImageUrl ?? widget.originalImageUrl;
    try {
      Uint8List bytes;
      if (url.startsWith('/') || url.startsWith('file://')) {
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
    final color = HexColor.fromHex(widget.selectedHex);
    final hasRender = widget.renderedImageUrl != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Room Preview'),
      ),
      body: Column(
        children: [
          // Color name chip
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  widget.selectedColorName,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    widget.selectedHex.toUpperCase(),
                    style: TextStyle(fontSize: 11, color: Colors.grey[600], fontFamily: 'monospace'),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Before / After slider
          Expanded(
            child: hasRender
                ? BeforeAfter(
                    thumbColor: Theme.of(context).colorScheme.primary,
                    beforeImage: _buildImage(widget.originalImageUrl),
                    afterImage: _buildImage(widget.renderedImageUrl!),
                  )
                : Stack(
                    children: [
                      _buildImage(widget.originalImageUrl),
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(color: Colors.white),
                              SizedBox(height: 12),
                              Text('Rendering (~20-30s)', style: TextStyle(color: Colors.white)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
          ),

          // Action bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.share_outlined),
                    label: const Text('Share'),
                    onPressed: _shareImage,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    icon: _saving
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.bookmark_add_outlined),
                    label: const Text('Save to Project'),
                    onPressed: _saving ? null : _saveToProject,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
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
