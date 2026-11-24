import 'package:flutter/material.dart';

import '../core/theme.dart';

/// 扫码取景框遮罩与四角高亮。
class ScanOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final frame = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.38),
      width: size.width * 0.74,
      height: size.width * 0.52,
    );
    final mask = Paint()..color = Colors.black.withValues(alpha: 0.45);
    final path = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(RRect.fromRectAndRadius(frame, const Radius.circular(16)))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, mask);

    final border = Paint()
      ..color = Colors.white.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawRRect(
      RRect.fromRectAndRadius(frame, const Radius.circular(16)),
      border,
    );

    final corner = Paint()
      ..color = AppColors.brand
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;
    const len = 22.0;
    final r = frame;
    canvas
      ..drawLine(r.topLeft, r.topLeft + const Offset(len, 0), corner)
      ..drawLine(r.topLeft, r.topLeft + const Offset(0, len), corner)
      ..drawLine(r.topRight, r.topRight + const Offset(-len, 0), corner)
      ..drawLine(r.topRight, r.topRight + const Offset(0, len), corner)
      ..drawLine(r.bottomLeft, r.bottomLeft + const Offset(len, 0), corner)
      ..drawLine(r.bottomLeft, r.bottomLeft + const Offset(0, -len), corner)
      ..drawLine(r.bottomRight, r.bottomRight + const Offset(-len, 0), corner)
      ..drawLine(r.bottomRight, r.bottomRight + const Offset(0, -len), corner);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
