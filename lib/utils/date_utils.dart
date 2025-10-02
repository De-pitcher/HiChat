import '../models/message.dart';

/// Utility functions for date handling in chat messages
class DateUtils {
  
  /// Check if two dates are on the same day
  static bool isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
           date1.month == date2.month &&
           date1.day == date2.day;
  }
  
  /// Group messages by date and insert date separators
  static List<dynamic> groupMessagesByDate(List<Message> messages) {
    if (messages.isEmpty) return [];
    
    final List<dynamic> groupedItems = [];
    DateTime? lastDate;
    
    for (int i = 0; i < messages.length; i++) {
      final message = messages[i];
      final messageDate = message.timestamp;
      
      // Check if we need a date separator
      if (lastDate == null || !isSameDay(lastDate, messageDate)) {
        // Add date separator
        groupedItems.add(DateSeparatorItem(date: messageDate));
        lastDate = messageDate;
      }
      
      // Add the message
      groupedItems.add(message);
    }
    
    return groupedItems;
  }
  
  /// Format date as "Today", "Yesterday", or full date for scroll indicator
  static String formatDateForScrollIndicator(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final messageDate = DateTime(date.year, date.month, date.day);

    if (messageDate == today) {
      return 'Today';
    } else if (messageDate == yesterday) {
      return 'Yesterday';
    } else {
      return _formatFullDate(date);
    }
  }
  
  /// Format full date as "29 September 2025"
  static String _formatFullDate(DateTime date) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];

    final day = date.day;
    final month = months[date.month - 1];
    final year = date.year;

    return '$day $month $year';
  }
}

/// Class to represent a date separator item in the chat list
class DateSeparatorItem {
  final DateTime date;
  
  DateSeparatorItem({required this.date});
}