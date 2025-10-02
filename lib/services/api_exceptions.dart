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
}