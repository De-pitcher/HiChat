import 'package:flutter/material.dart';
import 'dart:math' as math;

class AnimatedBorderWidget extends StatefulWidget {
  final Widget child;
  final double size;
  final double borderWidth;
  final Color borderColor;
  final Duration duration;

  const AnimatedBorderWidget({
    super.key,
    required this.child,
    required this.size,
    this.borderWidth = 2.0,
    this.borderColor = const Color(0xFF48C6F0),
    this.duration = const Duration(seconds: 3),
  });

  @override
  State<AnimatedBorderWidget> createState() => _AnimatedBorderWidgetState();
}

class _AnimatedBorderWidgetState extends State<AnimatedBorderWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.duration,
      vsync: this,
    )..repeat();
    
    _animation = Tween<double>(
      begin: 0,
      end: 2 * math.pi,
    ).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Animated border
          AnimatedBuilder(
            animation: _animation,
            builder: (context, child) {
              return CustomPaint(
                size: Size(widget.size, widget.size),
                painter: AnimatedBorderPainter(
                  animation: _animation.value,
                  borderColor: widget.borderColor,
                  borderWidth: widget.borderWidth,
                ),
              );
            },
          ),
          // Content
          ClipOval(
            child: Container(
              width: widget.size - (widget.borderWidth * 2 + 8),
              height: widget.size - (widget.borderWidth * 2 + 8),
              child: widget.child,
            ),
          ),
        ],
      ),
    );
  }
}

class AnimatedBorderPainter extends CustomPainter {
  final double animation;
  final Color borderColor;
  final double borderWidth;

  AnimatedBorderPainter({
    required this.animation,
    required this.borderColor,
    required this.borderWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - borderWidth) / 2;

    final paint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth
      ..strokeCap = StrokeCap.round;

    // Create gradient effect by drawing multiple arcs
    for (int i = 0; i < 3; i++) {
      final startAngle = animation + (i * math.pi / 1.5);
      final sweepAngle = math.pi / 3;
      final opacity = 1.0 - (i * 0.3);
      
      paint.color = borderColor.withOpacity(opacity);
      
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(AnimatedBorderPainter oldDelegate) {
    return oldDelegate.animation != animation;
  }
}