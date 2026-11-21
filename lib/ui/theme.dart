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
