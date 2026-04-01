import 'package:flutter/material.dart';

extension HexColor on Color {
  static Color fromHex(String hex) {
    final cleaned = hex.replaceAll('#', '');
    return Color(int.parse('FF$cleaned', radix: 16));
  }
}
