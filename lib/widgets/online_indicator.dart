import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/chat_state_manager.dart';

/// A widget that displays an online/offline indicator
class OnlineIndicator extends StatelessWidget {
  final bool isOnline;
  final double size;
  final bool showPulse;
  final Color? onlineColor;
  final Color? offlineColor;

  const OnlineIndicator({
    super.key,
    required this.isOnline,
    this.size = 12.0,
    this.showPulse = true,
    this.onlineColor,
    this.offlineColor,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveOnlineColor = onlineColor ?? Colors.green;
    final effectiveOfflineColor = offlineColor ?? Colors.grey;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: isOnline ? effectiveOnlineColor : effectiveOfflineColor,
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white,
          width: size * 0.15, // Responsive border width
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: size * 0.15,
            offset: Offset(0, size * 0.1),
          ),
        ],
      ),
      child: showPulse && isOnline
          ? _PulseAnimation(
              color: effectiveOnlineColor,
              size: size,
            )
          : null,
    );
  }
}

/// Internal pulse animation for online indicator
class _PulseAnimation extends StatefulWidget {
  final Color color;
  final double size;

  const _PulseAnimation({
    required this.color,
    required this.size,
  });

  @override
  State<_PulseAnimation> createState() => _PulseAnimationState();
}

class _PulseAnimationState extends State<_PulseAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    _animation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Transform.scale(
          scale: _animation.value,
          child: Container(
            decoration: BoxDecoration(
              color: widget.color.withValues(alpha: 0.6),
              shape: BoxShape.circle,
            ),
          ),
        );
      },
    );
  }
}

/// A presence-aware avatar that shows online status
class PresenceAwareAvatar extends StatelessWidget {
  final String userId;
  final String? imageUrl;
  final String? displayName;
  final double radius;
  final bool showIndicator;
  final bool showPulse;
  final Color backgroundColor;

  const PresenceAwareAvatar({
    super.key,
    required this.userId,
    this.imageUrl,
    this.displayName,
    this.radius = 25.0,
    this.showIndicator = true,
    this.showPulse = true,
    this.backgroundColor = Colors.grey,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<ChatStateManager>(
      builder: (context, chatStateManager, child) {
        final isOnline = chatStateManager.isUserOnline(userId);
        final fallbackText = displayName?.isNotEmpty == true 
            ? displayName![0].toUpperCase() 
            : '?';

        return Stack(
          children: [
            CircleAvatar(
              radius: radius,
              backgroundColor: backgroundColor,
              backgroundImage: imageUrl?.isNotEmpty == true 
                  ? NetworkImage(imageUrl!) 
                  : null,
              child: imageUrl?.isEmpty != false 
                  ? Text(
                      fallbackText,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: radius * 0.6,
                      ),
                    )
                  : null,
            ),
            if (showIndicator)
              Positioned(
                bottom: 0,
                right: 0,
                child: OnlineIndicator(
                  isOnline: isOnline,
                  size: radius * 0.4,
                  showPulse: showPulse,
                ),
              ),
          ],
        );
      },
    );
  }
}