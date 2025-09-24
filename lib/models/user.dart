import 'dart:convert';

class User {
  final int id;
  final String email;
  final String? imageUrl;
  final String username;
  final String? phoneNumber;
  final String? token;
  final String? about;
  final String? dateOfBirth;
  final String? availability;
  final DateTime createdAt;
  
  // Backward compatibility fields for existing code
  final bool isOnline;
  final DateTime? lastSeen;

  const User({
    required this.id,
    required this.email,
    this.imageUrl,
    required this.username,
    this.phoneNumber,
    this.token,
    this.about,
    this.dateOfBirth,
    this.availability,
    required this.createdAt,
    // Backward compatibility defaults
    this.isOnline = false,
    this.lastSeen,
  });

  // Backward compatibility getter
  String? get profileImageUrl => imageUrl;

  User copyWith({
    int? id,
    String? email,
    String? imageUrl,
    String? username,
    String? phoneNumber,
    String? token,
    String? about,
    String? dateOfBirth,
    String? availability,
    DateTime? createdAt,
    bool? isOnline,
    DateTime? lastSeen,
  }) {
    return User(
      id: id ?? this.id,
      email: email ?? this.email,
      imageUrl: imageUrl ?? this.imageUrl,
      username: username ?? this.username,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      token: token ?? this.token,
      about: about ?? this.about,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      availability: availability ?? this.availability,
      createdAt: createdAt ?? this.createdAt,
      isOnline: isOnline ?? this.isOnline,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'image_url': imageUrl,
      'username': username,
      'phone_number': phoneNumber,
      'token': token,
      'about': about,
      'date_of_birth': dateOfBirth,
      'availability': availability,
      'created_at': createdAt.toIso8601String(),
      // Include backward compatibility fields
      'isOnline': isOnline,
      'lastSeen': lastSeen?.millisecondsSinceEpoch,
    };
  }

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as int,
      email: json['email'] as String,
      imageUrl: json['image_url'] as String?,
      username: json['username'] as String,
      phoneNumber: json['phone_number'] as String?,
      token: json['token'] as String?,
      about: json['about'] as String?,
      dateOfBirth: json['date_of_birth'] as String?,
      availability: json['availability'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      // Handle backward compatibility
      isOnline: json['isOnline'] as bool? ?? (json['availability'] == 'online'),
      lastSeen: json['lastSeen'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['lastSeen'] as int)
          : null,
    );
  }

  // Factory for backward compatibility with old format
  factory User.fromLegacyJson(Map<String, dynamic> json) {
    return User(
      id: int.tryParse(json['id'] as String) ?? 0,
      email: json['email'] as String,
      imageUrl: json['profileImageUrl'] as String?,
      username: json['username'] as String,
      createdAt: json['createdAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int)
          : DateTime.now(),
      isOnline: json['isOnline'] as bool? ?? false,
      lastSeen: json['lastSeen'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['lastSeen'] as int)
          : null,
    );
  }

  /// Convert user to JSON string for storage
  String toStoredJson() {
    return json.encode(toJson());
  }

  /// Create user from stored JSON string
  factory User.fromStoredJson(String jsonString) {
    final jsonData = json.decode(jsonString) as Map<String, dynamic>;
    return User.fromJson(jsonData);
  }

  @override
  String toString() {
    return 'User(id: $id, username: $username, email: $email, availability: $availability)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is User && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}

class LoginRequest {
  final String email;
  final String password;

  const LoginRequest({
    required this.email,
    required this.password,
  });

  Map<String, dynamic> toJson() {
    return {
      'email': email,
      'password': password,
    };
  }

  @override
  String toString() {
    return 'LoginRequest(email: $email)'; // Don't include password in toString
  }
}

class LoginResponse {
  final User user;

  const LoginResponse({
    required this.user,
  });

  factory LoginResponse.fromJson(Map<String, dynamic> json) {
    // Handle both formats: direct user data or wrapped in 'user' key
    if (json.containsKey('user')) {
      // Format: {"user": {...}}
      return LoginResponse(
        user: User.fromJson(json['user'] as Map<String, dynamic>),
      );
    } else {
      // Format: {...} (direct user data)
      return LoginResponse(
        user: User.fromJson(json),
      );
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'user': user.toJson(),
    };
  }

  @override
  String toString() {
    return 'LoginResponse(user: $user)';
  }
}