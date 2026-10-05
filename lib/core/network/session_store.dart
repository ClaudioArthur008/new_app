import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SessionStore {
  SessionStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const _accessKey = 'access_token';
  static const _refreshKey = 'refresh_token';
  static const _oauthVerifierKey = 'oauth_code_verifier';
  static const _oauthStateKey = 'oauth_state';

  Future<String?> get accessToken => _storage.read(key: _accessKey);
  Future<String?> get refreshToken => _storage.read(key: _refreshKey);
  Future<String?> get oauthVerifier => _storage.read(key: _oauthVerifierKey);
  Future<String?> get oauthState => _storage.read(key: _oauthStateKey);

  Future<void> saveOAuthAttempt({
    required String verifier,
    required String state,
  }) async {
    await _storage.write(key: _oauthVerifierKey, value: verifier);
    await _storage.write(key: _oauthStateKey, value: state);
  }

  Future<void> clearOAuthAttempt() async {
    await _storage.delete(key: _oauthVerifierKey);
    await _storage.delete(key: _oauthStateKey);
  }

  Future<void> save({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _storage.write(key: _accessKey, value: accessToken);
    await _storage.write(key: _refreshKey, value: refreshToken);
  }

  Future<void> clear() async {
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
    await clearOAuthAttempt();
  }
}
