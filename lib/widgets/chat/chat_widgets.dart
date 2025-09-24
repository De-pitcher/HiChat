import 'package:flutter/material.dart';
import '../../models/user.dart';

class UserAvatar extends StatelessWidget {
  final User? user;
  final String? fallbackText;
  final double radius;
  final VoidCallback? onTap;

  const UserAvatar({
    super.key,
    this.user,
    this.fallbackText,
    this.radius = 20,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final displayText = user?.username ?? fallbackText ?? '?';
    
    return GestureDetector(
      onTap: onTap,
      child: CircleAvatar(
        radius: radius,
        backgroundColor: Colors.blue,
        backgroundImage: user?.profileImageUrl != null
            ? NetworkImage(user!.profileImageUrl!)
            : null,
        child: user?.profileImageUrl == null
            ? Text(
                displayText[0].toUpperCase(),
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: radius * 0.6,
                ),
              )
            : null,
      ),
    );
  }
}

class OnlineIndicator extends StatelessWidget {
  final bool isOnline;
  final DateTime? lastSeen;
  final double size;

  const OnlineIndicator({
    super.key,
    required this.isOnline,
    this.lastSeen,
    this.size = 8,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: isOnline ? Colors.green : Colors.grey,
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white,
          width: 1,
        ),
      ),
    );
  }
}

class TypingIndicator extends StatefulWidget {
  final String username;

  const TypingIndicator({
    super.key,
    required this.username,
  });

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();
    _animation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Text(
            '${widget.username} is typing',
            style: TextStyle(
              fontStyle: FontStyle.italic,
              color: Colors.grey[600],
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 4),
          AnimatedBuilder(
            animation: _animation,
            builder: (context, child) {
              return Row(
                children: List.generate(3, (index) {
                  final delay = index * 0.2;
                  final opacity = (_animation.value - delay).clamp(0.0, 1.0);
                  return Opacity(
                    opacity: (1 - opacity).abs(),
                    child: Container(
                      width: 4,
                      height: 4,
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      decoration: BoxDecoration(
                        color: Colors.grey[600],
                        shape: BoxShape.circle,
                      ),
                    ),
                  );
                }),
              );
            },
          ),
        ],
      ),
    );
  }
}