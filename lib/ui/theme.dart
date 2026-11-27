import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

ThemeData appTheme(Brightness b) => ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0F766E), brightness: b),
      inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
    );

final _inr = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
final _inr0 = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
String inr(double v, {bool whole = false}) => (whole ? _inr0 : _inr).format(v);
String when(DateTime t) => DateFormat('d MMM, h:mm a').format(t);

/// One fixed colour per category, so a category looks the same on every chart.
const categoryColors = <String, Color>{
  'food': Color(0xFFE76F51),
  'groceries': Color(0xFF2A9D8F),
  'cosmetics': Color(0xFFD16BA5),
  'shopping': Color(0xFF7B61FF),
  'transport': Color(0xFF3A86FF),
  'bills': Color(0xFFF4A261),
  'health': Color(0xFF43AA8B),
  'entertainment': Color(0xFFFFB703),
  'other': Color(0xFF8D99AE),
};
Color categoryColor(String id) => categoryColors[id] ?? categoryColors['other']!;
