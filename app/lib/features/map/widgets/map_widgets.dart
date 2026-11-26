import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:brr/core/theme/app_theme.dart';

/// White circular map-control button (map type / compass / GPS).
class MapButton extends StatelessWidget {
  const MapButton({required this.icon, required this.loading, super.key});

  final IconData icon;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black12),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
      ),
      child: loading
          ? const Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.green,
              ),
            )
          : Icon(icon, color: AppColors.green, size: 28),
    );
  }
}

/// เข็มทิศสไตล์ Google Maps — วงกลมขาว เข็มแดงชี้เหนือหมุนตาม
/// bearing ของกล้องจริง แตะเพื่อ reset กลับทิศเหนือ
class CompassButton extends StatelessWidget {
  const CompassButton({required this.bearing, super.key});

  /// Camera bearing in degrees (0 = north).
  final double bearing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black12),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
      ),
      child: Transform.rotate(
        // หมุนเข็มตรงข้ามกล้อง — ปลายแดงชี้เหนือจริงเสมอ
        angle: -bearing * math.pi / 180,
        child: const Padding(
          padding: EdgeInsets.all(12),
          child: CustomPaint(painter: _CompassPainter()),
        ),
      ),
    );
  }
}

class _CompassPainter extends CustomPainter {
  const _CompassPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;

    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = Colors.black12
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    // เข็มเหนือ (แดง)
    canvas.drawPath(
      Path()
        ..moveTo(c.dx, c.dy - r + 2)
        ..lineTo(c.dx - 4.5, c.dy + 2)
        ..lineTo(c.dx + 4.5, c.dy + 2)
        ..close(),
      Paint()..color = const Color(0xFFEA4335),
    );
    // เข็มใต้ (เทา)
    canvas.drawPath(
      Path()
        ..moveTo(c.dx, c.dy + r - 2)
        ..lineTo(c.dx - 4.5, c.dy - 2)
        ..lineTo(c.dx + 4.5, c.dy - 2)
        ..close(),
      Paint()..color = Colors.black38,
    );
    canvas.drawCircle(c, 2, Paint()..color = Colors.black45);
  }

  @override
  bool shouldRepaint(_CompassPainter old) => false;
}

/// Thumbnail tile in the map-type sheet — Google-Maps-style preview
/// tile with a gold ring when selected.
class MapTypeThumb extends StatelessWidget {
  const MapTypeThumb({
    required this.label,
    required this.asset,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final String asset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 112,
            height: 112,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected ? AppColors.gold : Colors.black12,
                width: selected ? 3 : 1,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(selected ? 13 : 15),
              child: Image.asset(
                asset,
                fit: BoxFit.cover,
                width: 112,
                height: 112,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 17,
              fontWeight: selected ? FontWeight.bold : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
