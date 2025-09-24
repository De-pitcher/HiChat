import 'package:flutter/material.dart';

/// Custom page transitions for smooth navigation animations
class PageTransitions {
  // Duration constants
  static const Duration _duration = Duration(milliseconds: 300);
  static const Duration _reverseDuration = Duration(milliseconds: 250);

  /// Slide transition from right to left (default forward navigation)
  static PageRouteBuilder<T> slideFromRight<T>(Widget page, {RouteSettings? settings}) {
    return PageRouteBuilder<T>(
      settings: settings,
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionDuration: _duration,
      reverseTransitionDuration: _reverseDuration,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        // Slide from right animation
        const begin = Offset(1.0, 0.0);
        const end = Offset.zero;
        const curve = Curves.easeInOut;

        var tween = Tween(begin: begin, end: end).chain(
          CurveTween(curve: curve),
        );
        var offsetAnimation = animation.drive(tween);

        // Add a subtle fade effect
        var fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeIn),
        );

        return SlideTransition(
          position: offsetAnimation,
          child: FadeTransition(
            opacity: fadeAnimation,
            child: child,
          ),
        );
      },
    );
  }

  /// Slide transition from left to right (back navigation feel)
  static PageRouteBuilder<T> slideFromLeft<T>(Widget page, {RouteSettings? settings}) {
    return PageRouteBuilder<T>(
      settings: settings,
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionDuration: _duration,
      reverseTransitionDuration: _reverseDuration,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        const begin = Offset(-1.0, 0.0);
        const end = Offset.zero;
        const curve = Curves.easeInOut;

        var tween = Tween(begin: begin, end: end).chain(
          CurveTween(curve: curve),
        );
        var offsetAnimation = animation.drive(tween);

        var fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeIn),
        );

        return SlideTransition(
          position: offsetAnimation,
          child: FadeTransition(
            opacity: fadeAnimation,
            child: child,
          ),
        );
      },
    );
  }

  /// Slide transition from bottom to top (modal-like)
  static PageRouteBuilder<T> slideFromBottom<T>(Widget page, {RouteSettings? settings}) {
    return PageRouteBuilder<T>(
      settings: settings,
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionDuration: _duration,
      reverseTransitionDuration: _reverseDuration,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        const begin = Offset(0.0, 1.0);
        const end = Offset.zero;
        const curve = Curves.easeOutCubic;

        var tween = Tween(begin: begin, end: end).chain(
          CurveTween(curve: curve),
        );
        var offsetAnimation = animation.drive(tween);

        return SlideTransition(
          position: offsetAnimation,
          child: child,
        );
      },
    );
  }

  /// Scale transition with fade (for modals and dialogs)
  static PageRouteBuilder<T> scaleWithFade<T>(Widget page, {RouteSettings? settings}) {
    return PageRouteBuilder<T>(
      settings: settings,
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionDuration: _duration,
      reverseTransitionDuration: _reverseDuration,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        const curve = Curves.easeInOut;

        var scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
          CurvedAnimation(parent: animation, curve: curve),
        );

        var fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeIn),
        );

        return ScaleTransition(
          scale: scaleAnimation,
          child: FadeTransition(
            opacity: fadeAnimation,
            child: child,
          ),
        );
      },
    );
  }

  /// Fade transition (subtle and smooth)
  static PageRouteBuilder<T> fade<T>(Widget page, {RouteSettings? settings}) {
    return PageRouteBuilder<T>(
      settings: settings,
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionDuration: const Duration(milliseconds: 200),
      reverseTransitionDuration: const Duration(milliseconds: 150),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: Tween<double>(begin: 0.0, end: 1.0).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeIn),
          ),
          child: child,
        );
      },
    );
  }

  /// Shared axis transition (material design style)
  static PageRouteBuilder<T> sharedAxis<T>(Widget page, {RouteSettings? settings}) {
    return PageRouteBuilder<T>(
      settings: settings,
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionDuration: _duration,
      reverseTransitionDuration: _reverseDuration,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        const curve = Curves.easeInOut;

        // Outgoing page slides left and fades out
        var exitAnimation = Tween<Offset>(
          begin: Offset.zero,
          end: const Offset(-0.3, 0.0),
        ).animate(CurvedAnimation(parent: secondaryAnimation, curve: curve));

        var exitFade = Tween<double>(
          begin: 1.0,
          end: 0.0,
        ).animate(CurvedAnimation(parent: secondaryAnimation, curve: curve));

        // Incoming page slides from right and fades in
        var enterAnimation = Tween<Offset>(
          begin: const Offset(0.3, 0.0),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: animation, curve: curve));

        var enterFade = Tween<double>(
          begin: 0.0,
          end: 1.0,
        ).animate(CurvedAnimation(parent: animation, curve: curve));

        return Stack(
          children: [
            SlideTransition(
              position: exitAnimation,
              child: FadeTransition(
                opacity: exitFade,
                child: secondaryAnimation.status == AnimationStatus.reverse
                    ? Container() // Hide during reverse
                    : child,
              ),
            ),
            SlideTransition(
              position: enterAnimation,
              child: FadeTransition(
                opacity: enterFade,
                child: child,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Navigation helper with built-in animations
class AnimatedNavigator {
  /// Navigate with slide from right animation (default)
  static Future<T?> push<T>(BuildContext context, Widget page) {
    return Navigator.push<T>(
      context,
      PageTransitions.slideFromRight<T>(page),
    );
  }

  /// Navigate and replace current route with slide animation
  static Future<T?> pushReplacement<T, TO>(BuildContext context, Widget page) {
    return Navigator.pushReplacement<T, TO>(
      context,
      PageTransitions.slideFromRight<T>(page),
    );
  }

  /// Navigate with slide from bottom (modal-like)
  static Future<T?> pushModal<T>(BuildContext context, Widget page) {
    return Navigator.push<T>(
      context,
      PageTransitions.slideFromBottom<T>(page),
    );
  }

  /// Navigate with fade transition
  static Future<T?> pushFade<T>(BuildContext context, Widget page) {
    return Navigator.push<T>(
      context,
      PageTransitions.fade<T>(page),
    );
  }

  /// Navigate with scale animation (for dialogs/overlays)
  static Future<T?> pushScale<T>(BuildContext context, Widget page) {
    return Navigator.push<T>(
      context,
      PageTransitions.scaleWithFade<T>(page),
    );
  }

  /// Navigate and clear all previous routes
  static Future<T?> pushAndClearStack<T>(BuildContext context, Widget page) {
    return Navigator.pushAndRemoveUntil<T>(
      context,
      PageTransitions.fade<T>(page),
      (route) => false,
    );
  }

  /// Navigate with custom transition type
  static Future<T?> pushWithTransition<T>(
    BuildContext context,
    Widget page, {
    PageTransitionType type = PageTransitionType.slideRight,
  }) {
    PageRouteBuilder<T> route;
    switch (type) {
      case PageTransitionType.slideRight:
        route = PageTransitions.slideFromRight<T>(page);
        break;
      case PageTransitionType.slideLeft:
        route = PageTransitions.slideFromLeft<T>(page);
        break;
      case PageTransitionType.slideBottom:
        route = PageTransitions.slideFromBottom<T>(page);
        break;
      case PageTransitionType.fade:
        route = PageTransitions.fade<T>(page);
        break;
      case PageTransitionType.scale:
        route = PageTransitions.scaleWithFade<T>(page);
        break;
      case PageTransitionType.sharedAxis:
        route = PageTransitions.sharedAxis<T>(page);
        break;
    }

    return Navigator.push<T>(context, route);
  }
}

enum PageTransitionType {
  slideRight,
  slideLeft,
  slideBottom,
  fade,
  scale,
  sharedAxis,
}

// Note: This file provides page transition utilities.
// The actual screen widgets should be imported where this utility is used.