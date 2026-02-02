import 'package:flutter/material.dart';
import '../screens/calls/incoming_call_screen.dart';
import 'call_signaling_service.dart';

/// Manages incoming call notifications and screen presentation
/// Handles showing the full-screen incoming call dialog
class CallNotificationManager {
  static final CallNotificationManager _instance = CallNotificationManager._internal();
  
  factory CallNotificationManager() => _instance;
  
  CallNotificationManager._internal();
  
  BuildContext? _appContext;
  bool _isCallScreenShown = false;
  
  /// Set app context for showing overlays
  /// Call this from main.dart during app initialization
  void setAppContext(BuildContext context) {
    _appContext = context;
    debugPrint('📱 CallNotificationManager: App context set for showing notifications');
  }
  
  /// Show incoming call screen as full-screen dialog
  /// Returns true if successfully shown, false otherwise
  Future<bool> showIncomingCallScreen(CallInvitation invitation) async {
    // Prevent duplicate call screens
    if (_isCallScreenShown) {
      debugPrint('⚠️ CallNotificationManager: Call screen already shown, ignoring duplicate');
      return false;
    }
    
    if (_appContext == null) {
      debugPrint('❌ CallNotificationManager: App context not set, cannot show call screen');
      return false;
    }
    
    _isCallScreenShown = true;
    debugPrint('📞 CallNotificationManager: Showing incoming call screen for ${invitation.fromUserName}');
    
    try {
      // Show as full-screen dialog (barrier dismissible = false)
      final result = await showDialog<bool>(
        context: _appContext!,
        barrierDismissible: false,
        barrierColor: Colors.black87,
        builder: (context) => IncomingCallScreen(
          invitation: invitation,
          onAccepted: () {
            debugPrint('✅ CallNotificationManager: Call accepted by user');
            _isCallScreenShown = false;
          },
          onRejected: () {
            debugPrint('❌ CallNotificationManager: Call rejected by user');
            _isCallScreenShown = false;
          },
        ),
      );
      
      _isCallScreenShown = false;
      return result ?? false;
    } catch (e) {
      debugPrint('❌ CallNotificationManager: Error showing call screen: $e');
      _isCallScreenShown = false;
      return false;
    }
  }
  
  /// Check if a call screen is currently shown
  bool get isCallScreenShown => _isCallScreenShown;
  
  /// Get app context
  BuildContext? get appContext => _appContext;
}
