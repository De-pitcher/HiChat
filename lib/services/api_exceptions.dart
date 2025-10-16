/// Custom exceptions for API operations
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final String? errorCode;

  const ApiException(
    this.message, {
    this.statusCode,
    this.errorCode,
  });

  @override
  String toString() {
    return 'ApiException: $message (Status: $statusCode, Code: $errorCode)';
  }
}

class NetworkException extends ApiException {
  const NetworkException(super.message);
}

class ServerException extends ApiException {
  const ServerException(super.message, {super.statusCode});
}

class AuthenticationException extends ApiException {
  const AuthenticationException(super.message) : super(statusCode: 401);
}

class ValidationException extends ApiException {
  final Map<String, dynamic>? validationErrors;

  const ValidationException(
    super.message, {
    this.validationErrors,
    super.statusCode,
  });

  /// Get user-friendly error message for display
  String get userMessage => message;

  /// Check if there are specific field errors
  bool get hasFieldErrors => validationErrors != null && validationErrors!.isNotEmpty;

  /// Get errors for a specific field
  List<String> getFieldErrors(String fieldName) {
    if (validationErrors == null) return [];
    final fieldErrors = validationErrors![fieldName];
    if (fieldErrors is List) {
      return fieldErrors.map((e) => e.toString()).toList();
    }
    return [];
  }

  /// Get all error messages as a list
  List<String> get allErrorMessages {
    if (validationErrors == null) return [message];
    
    final List<String> errors = [];
    validationErrors!.forEach((field, messages) {
      if (messages is List && messages.isNotEmpty) {
        errors.addAll(messages.map((e) => e.toString()));
      }
    });
    
    return errors.isEmpty ? [message] : errors;
  }
}