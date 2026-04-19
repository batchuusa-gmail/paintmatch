import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';

import '../services/api_service.dart';
import '../services/subscription_service.dart';

class AnalysisLoadingScreen extends StatefulWidget {
  final File imageFile;

  const AnalysisLoadingScreen({super.key, required this.imageFile});

  @override
  State<AnalysisLoadingScreen> createState() => _AnalysisLoadingScreenState();
}

class _AnalysisLoadingScreenState extends State<AnalysisLoadingScreen> {
  String _status = 'Analyzing your room...';

  @override
  void initState() {
    super.initState();
    _analyze();
  }

  Future<void> _analyze() async {
    try {
      setState(() => _status = 'Detecting wall colors and room style...');
      final analysis = await ApiService().analyzeRoom(widget.imageFile);
      // Deduct one trial analysis on successful completion
      await SubscriptionService().recordAnalysis();

      setState(() => _status = 'Building color palettes...');

      setState(() => _status = 'Building color palettes...');
      await Future.delayed(const Duration(milliseconds: 600));

      if (!mounted) return;
      context.pushReplacement('/palette', extra: {
        'imageFile': widget.imageFile,
        'analysis': analysis,
      });
    } catch (e, stack) {
      print('[PaintMatch ERROR] $e');
      print('[PaintMatch STACK] $stack');
      if (!mounted) return;
      // Show error on screen instead of disappearing snackbar
      setState(() => _status = 'Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Room image thumbnail
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Shimmer.fromColors(
                    baseColor: Colors.grey[300]!,
                    highlightColor: Colors.grey[100]!,
                    child: Container(
                      height: 220,
                      width: double.infinity,
                      color: Colors.grey[300],
                    ),
                  ),
                ),
                const SizedBox(height: 40),
                const CircularProgressIndicator(),
                const SizedBox(height: 20),
                Text(
                  _status,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Claude AI is examining lighting,\nwall surfaces, and room style',
                  style: TextStyle(color: Colors.grey[500], fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
