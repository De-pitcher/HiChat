// widgets/chat/scroll_to_bottom_fab.dart
import 'package:flutter/material.dart';
import '../../constants/app_theme.dart';

// Alternative implementation with more reliable badge positioning
class ScrollToBottomFab extends StatelessWidget {
  final bool visible;
  final int unreadMessageCount;
  final VoidCallback onPressed;

  const ScrollToBottomFab({
    super.key,
    required this.visible,
    required this.unreadMessageCount,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: visible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 200),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          FloatingActionButton.small(
            onPressed: onPressed,
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            elevation: 4,
            child: const Icon(Icons.keyboard_arrow_down, size: 20),
          ),
          if (unreadMessageCount > 0)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.white,
                    width: 1.5,
                  ),
                ),
                constraints: const BoxConstraints(
                  minWidth: 16,
                  minHeight: 16,
                ),
                child: Center(
                  child: Text(
                    unreadMessageCount > 99 ? '99+' : unreadMessageCount.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}