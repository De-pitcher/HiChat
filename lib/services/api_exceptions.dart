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
  const NetworkException(String message) : super(message);
}

class ServerException extends ApiException {
  const ServerException(String message, {int? statusCode})
      : super(message, statusCode: statusCode);
}

class AuthenticationException extends ApiException {
  const AuthenticationException(String message)
      : super(message, statusCode: 401);
}

class ValidationException extends ApiException {
  final Map<String, dynamic>? validationErrors;

  const ValidationException(
    String message, {
    this.validationErrors,
    int? statusCode,
  }) : super(message, statusCode: statusCode);
}