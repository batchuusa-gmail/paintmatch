import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/app_theme.dart';
import '../models/room_dimensions.dart';

/// Shows a bottom sheet for confirming AI-estimated room dimensions.
/// Pre-fills fields from the Claude Vision estimate.
void showRoomDimensionsSheet(
  BuildContext context, {
  required DimensionEstimate estimate,
  required Function(RoomDimensions) onConfirmed,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => RoomDimensionsSheet(
      estimatedWallWidthFt: estimate.estimatedWallWidthFt,
      estimatedRoomDepthFt: estimate.estimatedRoomDepthFt,
      confidence: estimate.confidence,
      referenceObject: estimate.referenceObject,
      onConfirmed: onConfirmed,
    ),
  );
}

class RoomDimensionsSheet extends StatefulWidget {
  final double estimatedWallWidthFt;
  final double estimatedRoomDepthFt;
  final String confidence;
  final String referenceObject;
  final Function(RoomDimensions) onConfirmed;

  const RoomDimensionsSheet({
    super.key,
    required this.estimatedWallWidthFt,
    required this.estimatedRoomDepthFt,
    required this.confidence,
    required this.referenceObject,
    required this.onConfirmed,
  });

  @override
  State<RoomDimensionsSheet> createState() => _RoomDimensionsSheetState();
}

class _RoomDimensionsSheetState extends State<RoomDimensionsSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _wallWidthCtrl;
  late final TextEditingController _roomDepthCtrl;
  late final TextEditingController _customCeilingCtrl;

  double _ceilingHeightFt = 9.0;
  bool _customCeiling = false;
  int _doorCount = 1;
  int _windowCount = 1;

  @override
  void initState() {
    super.initState();
    _wallWidthCtrl = TextEditingController(
        text: widget.estimatedWallWidthFt.toStringAsFixed(1));
    _roomDepthCtrl = TextEditingController(
        text: widget.estimatedRoomDepthFt.toStringAsFixed(1));
    _customCeilingCtrl = TextEditingController(text: '9.0');
  }

  @override
  void dispose() {
    _wallWidthCtrl.dispose();
    _roomDepthCtrl.dispose();
    _customCeilingCtrl.dispose();
    super.dispose();
  }

  double get _effectiveCeiling => _customCeiling
      ? (double.tryParse(_customCeilingCtrl.text) ?? 9.0)
      : _ceilingHeightFt;

  void _confirm() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(context);
    widget.onConfirmed(RoomDimensions(
      ceilingHeightFt: _effectiveCeiling,
      wallWidthFt: double.tryParse(_wallWidthCtrl.text) ?? widget.estimatedWallWidthFt,
      roomDepthFt: double.tryParse(_roomDepthCtrl.text) ?? widget.estimatedRoomDepthFt,
      doorCount: _doorCount,
      windowCount: _windowCount,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isLow = widget.confidence == 'low';
    final isMedium = widget.confidence == 'medium';

    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Handle
            const SizedBox(height: 12),
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),

            // Title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(children: [
                Expanded(
                  child: Text('Confirm Room Dimensions',
                      style: GoogleFonts.playfairDisplay(
                          color: AppColors.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.w600)),
                ),
              ]),
            ),
            const SizedBox(height: 8),

            // Confidence badge
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isLow
                        ? Colors.orange.shade900.withValues(alpha: 0.3)
                        : Colors.green.shade900.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isLow ? Colors.orange.shade600 : Colors.green.shade600,
                    ),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(
                      isLow ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                      size: 13,
                      color: isLow ? Colors.orange.shade400 : Colors.green.shade400,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      isLow || isMedium
                          ? 'Estimated — please verify'
                          : 'AI detected: ${widget.referenceObject}',
                      style: TextStyle(
                        color: isLow ? Colors.orange.shade300 : Colors.green.shade300,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ]),
                ),
              ]),
            ),
            const SizedBox(height: 16),

            // Form
            Expanded(
              child: SingleChildScrollView(
                controller: controller,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Divider(color: AppColors.border),
                      const SizedBox(height: 16),

                      // Ceiling height
                      _sectionLabel('Ceiling Height'),
                      const SizedBox(height: 10),
                      SegmentedButton<double>(
                        segments: const [
                          ButtonSegment(value: 8.0, label: Text('8 ft')),
                          ButtonSegment(value: 9.0, label: Text('9 ft')),
                          ButtonSegment(value: 10.0, label: Text('10 ft')),
                        ],
                        selected: _customCeiling ? const {} : {_ceilingHeightFt},
                        emptySelectionAllowed: true,
                        onSelectionChanged: (s) => setState(() {
                          if (s.isNotEmpty) {
                            _ceilingHeightFt = s.first;
                            _customCeiling = false;
                          }
                        }),
                        style: ButtonStyle(
                          backgroundColor: WidgetStateProperty.resolveWith((states) {
                            if (states.contains(WidgetState.selected)) return AppColors.accentDim;
                            return AppColors.background;
                          }),
                          foregroundColor: WidgetStateProperty.resolveWith((states) {
                            if (states.contains(WidgetState.selected)) return AppColors.accent;
                            return AppColors.textSecondary;
                          }),
                        ),
                      ),
                      const SizedBox(height: 10),
                      GestureDetector(
                        onTap: () => setState(() => _customCeiling = true),
                        child: Row(children: [
                          Radio<bool>(
                            value: true,
                            groupValue: _customCeiling,
                            activeColor: AppColors.accent,
                            onChanged: (v) => setState(() => _customCeiling = true),
                          ),
                          const Text('Custom',
                              style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                          const SizedBox(width: 12),
                          if (_customCeiling)
                            SizedBox(
                              width: 80,
                              child: TextFormField(
                                controller: _customCeilingCtrl,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                style: const TextStyle(color: AppColors.textPrimary),
                                decoration: const InputDecoration(
                                  suffixText: 'ft',
                                  suffixStyle: TextStyle(color: AppColors.textSecondary),
                                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                ),
                              ),
                            ),
                        ]),
                      ),

                      const SizedBox(height: 20),

                      // Wall width
                      _sectionLabel('Wall Width (longest wall)'),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _wallWidthCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: const TextStyle(color: AppColors.textPrimary),
                        decoration: _inputDeco('e.g. 14.0', 'ft'),
                        validator: (v) => (v == null || double.tryParse(v) == null)
                            ? 'Enter a valid number'
                            : null,
                      ),

                      const SizedBox(height: 16),

                      // Room depth
                      _sectionLabel('Room Depth'),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _roomDepthCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: const TextStyle(color: AppColors.textPrimary),
                        decoration: _inputDeco('e.g. 12.0', 'ft'),
                        validator: (v) => (v == null || double.tryParse(v) == null)
                            ? 'Enter a valid number'
                            : null,
                      ),

                      const SizedBox(height: 24),

                      // Doors stepper
                      _StepperRow(
                        label: 'Doors',
                        icon: Icons.door_front_door_outlined,
                        value: _doorCount,
                        min: 0,
                        max: 5,
                        onChanged: (v) => setState(() => _doorCount = v),
                      ),
                      const SizedBox(height: 16),

                      // Windows stepper
                      _StepperRow(
                        label: 'Windows',
                        icon: Icons.window_outlined,
                        value: _windowCount,
                        min: 0,
                        max: 8,
                        onChanged: (v) => setState(() => _windowCount = v),
                      ),

                      const SizedBox(height: 32),

                      // Confirm button
                      FilledButton(
                        onPressed: _confirm,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        child: const Text('Calculate Paint Needed',
                            style: TextStyle(
                                fontSize: 16,
                                color: Colors.black,
                                fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(text,
      style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4));

  InputDecoration _inputDeco(String hint, String suffix) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.border),
        suffixText: suffix,
        suffixStyle: const TextStyle(color: AppColors.textSecondary),
        filled: true,
        fillColor: AppColors.background,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.accent),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      );
}

class _StepperRow extends StatelessWidget {
  final String label;
  final IconData icon;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  const _StepperRow({
    required this.label,
    required this.icon,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(children: [
        Icon(icon, color: AppColors.textSecondary, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text(label,
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500)),
        ),
        IconButton(
          onPressed: value > min ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove_circle_outline),
          color: AppColors.accent,
          disabledColor: AppColors.border,
          iconSize: 22,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        ),
        SizedBox(
          width: 32,
          child: Text('$value',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700)),
        ),
        IconButton(
          onPressed: value < max ? () => onChanged(value + 1) : null,
          icon: const Icon(Icons.add_circle_outline),
          color: AppColors.accent,
          disabledColor: AppColors.border,
          iconSize: 22,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        ),
      ]),
    );
  }
}
