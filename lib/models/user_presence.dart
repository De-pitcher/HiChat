class UserPresence {
  final String userId;
  final String username;
  final String? email;
  final bool isOnline;
  final DateTime? lastSeen;

  const UserPresence({
    required this.userId,
    required this.username,
    this.email,
    required this.isOnline,
    this.lastSeen,
  });

  factory UserPresence.fromJson(Map<String, dynamic> json) {
    return UserPresence(
      userId: (json['user_id'] ?? json['id'])?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      email: json['email']?.toString(),
      isOnline: json['is_online'] ?? false,
      lastSeen: json['last_seen'] != null 
          ? DateTime.tryParse(json['last_seen'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'username': username,
      'email': email,
      'is_online': isOnline,
      'last_seen': lastSeen?.toIso8601String(),
    };
  }

  /// Get display-friendly status text
  String get displayStatus {
    if (isOnline) return 'Online';
    if (lastSeen == null) return 'Last seen: Never';
    
    return 'Last seen: ${_formatTimeAgo(lastSeen!)}';
  }

  /// Format time ago in a user-friendly way
  String _formatTimeAgo(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);
    
    if (difference.inMinutes < 1) return 'just now';
    if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
    if (difference.inHours < 24) return '${difference.inHours}h ago';
    if (difference.inDays < 7) return '${difference.inDays}d ago';
    
    return '${time.day}/${time.month}/${time.year}';
  }

  UserPresence copyWith({
    String? userId,
    String? username,
    String? email,
    bool? isOnline,
    DateTime? lastSeen,
  }) {
    return UserPresence(
      userId: userId ?? this.userId,
      username: username ?? this.username,
      email: email ?? this.email,
      isOnline: isOnline ?? this.isOnline,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is UserPresence && other.userId == userId;
  }

  @override
  int get hashCode => userId.hashCode;

  @override
  String toString() {
    return 'UserPresence(userId: $userId, username: $username, isOnline: $isOnline)';
  }
}