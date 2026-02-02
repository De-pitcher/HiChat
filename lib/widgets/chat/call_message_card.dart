import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../../models/message.dart';
import '../../constants/app_theme.dart';

/// Call Message Card for displaying call invitations and call-related messages
/// WhatsApp-style minimal design
class CallMessageCard extends StatelessWidget {
  final Message message;
  final bool isCurrentUser;
  final VoidCallback? onRetry;

  const CallMessageCard({
    super.key,
    required this.message,
    required this.isCurrentUser,
    this.onRetry,
  });

  /// Parse call data from message content
  Map<String, dynamic>? _parseCallData() {
    try {
      return jsonDecode(message.content);
    } catch (e) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final callData = _parseCallData();
    if (callData == null) return _buildErrorCard();

    final callType = callData['type'] ?? 'call';
    final isVideoCall = callData['is_video_call'] ?? false;
    final timestamp = callData['timestamp'] != null 
        ? DateTime.parse(callData['timestamp'] as String)
        : DateTime.now();

    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(minHeight: 60, minWidth: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: isCurrentUser
              ? LinearGradient(
                  colors: [
                    AppColors.primary,
                    AppColors.primary.withValues(alpha: 0.8),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: isCurrentUser ? null : Colors.grey[100],
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: Radius.circular(isCurrentUser ? 20 : 4),
            bottomRight: Radius.circular(isCurrentUser ? 4 : 20),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Call icon with background
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _getCallIconColor(callType).withValues(alpha: 0.2),
              ),
              child: Center(
                child: Icon(
                  _getCallIcon(callType, isVideoCall),
                  color: _getCallIconColor(callType),
                  size: 22,
                ),
              ),
            ),
            const SizedBox(width: 14),
            
            // Call info - take available space but don't expand full width
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Call title
                  Text(
                    _getCallTitle(callType),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: isCurrentUser ? Colors.white : Colors.grey[900],
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 3),
                  // Time
                  Text(
                    _formatTime(timestamp),
                    style: TextStyle(
                      fontSize: 13,
                      color: isCurrentUser ? Colors.white70 : Colors.grey[600],
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            
            // Call direction indicator
            Icon(
              isCurrentUser ? Icons.call_made : Icons.call_received,
              color: isCurrentUser ? Colors.white : Colors.grey[600],
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  /// Get icon for call type
  IconData _getCallIcon(String callType, bool isVideoCall) {
    if (isVideoCall) {
      return Icons.videocam;
    }
    return Icons.call;
  }

  /// Get icon background color based on call type
  Color _getCallIconColor(String callType) {
    switch (callType) {
      case 'call_invitation':
        return Colors.blue;
      case 'call_accepted':
        return Colors.green;
      case 'call_rejected':
      case 'call_declined':
        return Colors.red;
      case 'call_cancelled':
        return Colors.orange;
      case 'call_ended':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  /// Get title for call type
  String _getCallTitle(String callType) {
    switch (callType) {
      case 'call_invitation':
        return 'Voice call';
      case 'call_accepted':
        return 'Call accepted';
      case 'call_rejected':
      case 'call_declined':
        return 'Call declined';
      case 'call_cancelled':
        return 'Call cancelled';
      case 'call_ended':
        return 'Call ended';
      default:
        return 'Call';
    }
  }

  /// Format timestamp to readable time
  String _formatTime(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  /// Build error card if JSON parsing fails
  Widget _buildErrorCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.red[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red[200]!),
      ),
      child: Text(
        '📞 Call message',
        style: TextStyle(
          fontSize: 13,
          color: Colors.red[700],
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }
}
