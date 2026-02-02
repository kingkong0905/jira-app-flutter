/// Shared HTTP constants used across API services.
class HttpConstants {
  // HTTP Status Codes
  static const int statusOk = 200;
  static const int statusCreated = 201;
  static const int statusNoContent = 204;
  static const int statusBadRequest = 400;
  static const int statusUnauthorized = 401;
  static const int statusForbidden = 403;
  static const int statusNotFound = 404;
  static const int statusSuccessMin = 200;
  static const int statusSuccessMax = 299;

  // HTTP Headers
  static const String headerAuthorization = 'Authorization';
  static const String headerContentType = 'Content-Type';
  static const String headerAccept = 'Accept';
  static const String headerUserAgent = 'User-Agent';

  // Content Types
  static const String contentTypeJson = 'application/json';

  // Auth Schemes
  static const String authSchemeBasic = 'Basic';
  static const String authSchemeBearer = 'Bearer';
}
