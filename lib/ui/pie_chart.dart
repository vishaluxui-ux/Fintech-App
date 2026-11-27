import 'dart:math' as math;

import 'package:flutter/material.dart';

/// One slice: a category's share of spend.
class PieSlice {
  final String id;
  final double value;
  final Color color;
  const PieSlice(this.id, this.value, this.color);
}

/// Donut chart of spend by category, with the period total in the middle.
/// Tapping a slice reports its id (used to filter the transaction list).
class SpendPie extends StatelessWidget {
  final List<PieSlice> slices;
  final String centerTop;
  final String centerBottom;
  final String? selectedId;
  final ValueChanged<String>? onTap;
  final double size;

  const SpendPie({
    super.key,
    required this.slices,
    required this.centerTop,
    required this.centerBottom,
    this.selectedId,
    this.onTap,
    this.size = 220,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Spend by category chart. $centerTop $centerBottom',
      child: SizedBox(
        width: size,
        height: size,
        child: GestureDetector(
          onTapUp: onTap == null
              ? null
              : (d) {
                  final id = _hit(d.localPosition, Size.square(size));
                  if (id != null) onTap!(id);
                },
          child: CustomPaint(
            painter: _PiePainter(slices, selectedId, cs.surface),
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(centerTop, style: t.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
                Text(centerBottom, style: t.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  String? _hit(Offset p, Size s) {
    final c = s.center(Offset.zero);
    final v = p - c;
    final r = s.shortestSide / 2;
    if (v.distance > r || v.distance < r * _hole) return null;
    var a = math.atan2(v.dy, v.dx) + math.pi / 2; // 0 at 12 o'clock, clockwise
    if (a < 0) a += 2 * math.pi;
    final total = slices.fold(0.0, (s, e) => s + e.value);
    if (total <= 0) return null;
    var acc = 0.0;
    for (final sl in slices) {
      acc += sl.value / total * 2 * math.pi;
      if (a <= acc) return sl.id;
    }
    return slices.last.id;
  }
}

const _hole = 0.62; // inner radius as a share of the outer radius

class _PiePainter extends CustomPainter {
  final List<PieSlice> slices;
  final String? selected;
  final Color gap;
  _PiePainter(this.slices, this.selected, this.gap);

  @override
  void paint(Canvas canvas, Size size) {
    final total = slices.fold(0.0, (s, e) => s + e.value);
    final r = size.shortestSide / 2;
    final c = size.center(Offset.zero);
    final stroke = r * (1 - _hole);
    if (total <= 0) {
      canvas.drawCircle(c, r - stroke / 2,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = stroke
            ..color = gap.withValues(alpha: 0.4));
      return;
    }
    var start = -math.pi / 2;
    for (final s in slices) {
      final sweep = s.value / total * 2 * math.pi;
      final dim = selected != null && selected != s.id;
      final w = selected == s.id ? stroke * 1.12 : stroke;
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r - stroke / 2),
        start,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w
          ..color = dim ? s.color.withValues(alpha: 0.35) : s.color,
      );
      // Thin gap between slices so neighbours stay distinct.
      if (slices.length > 1) {
        final edge = Offset(math.cos(start), math.sin(start));
        canvas.drawLine(c + edge * (r * _hole - 2), c + edge * (r + 2),
            Paint()
              ..color = gap
              ..strokeWidth = 2);
      }
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_PiePainter old) => old.slices != slices || old.selected != selected || old.gap != gap;
}
