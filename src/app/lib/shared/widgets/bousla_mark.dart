import 'package:flutter/material.dart';

/// The Bousla mark from the identity (find-your-bousla.base44.app): a
/// direction star (amber up, teal down) inside an open ring. Drawn, not an
/// image, so it is sharp at any size and follows light/dark: on dark the
/// ring is signal teal, on light a faint midnight with the dark teal star.
class BouslaMark extends StatelessWidget {
  const BouslaMark({super.key, this.size = 56});

  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Bousla',
        image: true,
        child: CustomPaint(
          size: Size.square(size),
          painter: _MarkPainter(
            dark: Theme.of(context).brightness == Brightness.dark,
          ),
        ),
      );
}

class _MarkPainter extends CustomPainter {
  _MarkPainter({required this.dark});

  final bool dark;

  static const _midnight = Color(0xFF0B1230);
  static const _signalTeal = Color(0xFF34E3B6);
  static const _darkTeal = Color(0xFF0E9E86);
  static const _amber = Color(0xFFFFB020);
  static const _amberLight = Color(0xFFFFD98A);

  @override
  void paint(Canvas canvas, Size size) {
    // The identity draws on a 100 x 100 box.
    canvas.scale(size.width / 100, size.height / 100);

    final ring = Path()
      ..moveTo(36.7, 18.7)
      ..arcToPoint(
        const Offset(63.3, 18.7),
        radius: const Radius.circular(34),
        largeArc: true,
        clockwise: false,
      );
    canvas.drawPath(
      ring,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round
        ..color = dark
            ? _signalTeal.withValues(alpha: 0.5)
            : _midnight.withValues(alpha: 0.18),
    );

    final up = Path()
      ..moveTo(50, 6)
      ..cubicTo(53, 32, 58, 42, 70, 50)
      ..lineTo(30, 50)
      ..cubicTo(42, 42, 47, 32, 50, 6)
      ..close();
    canvas.drawPath(
      up,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_amberLight, _amber],
        ).createShader(const Rect.fromLTRB(30, 4, 70, 50)),
    );

    final down = Path()
      ..moveTo(30, 50)
      ..cubicTo(42, 58, 47, 68, 50, 74)
      ..cubicTo(53, 68, 58, 58, 70, 50)
      ..close();
    canvas.drawPath(down, Paint()..color = dark ? _signalTeal : _darkTeal);
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.dark != dark;
}
