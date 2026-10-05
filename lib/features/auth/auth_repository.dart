import 'package:dio/dio.dart';

import '../../core/network/session_store.dart';

class AuthException implements Exception {
  const AuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

class AuthRepository {
  AuthRepository({required this.dio, required this.session});
  final Dio dio;
  final SessionStore session;

  Future<Map<String, dynamic>> signIn(String email, String password) async {
    try {
      final response = await dio.post<Map<String, dynamic>>(
        '/auth/v1/token',
        queryParameters: {'grant_type': 'password'},
        data: {'email': email, 'password': password},
      );
      return await _saveSession(response.data!);
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  Future<void> signUp(String email, String password) async {
    try {
      final response = await dio.post<Map<String, dynamic>>(
        '/auth/v1/signup',
        data: {'email': email, 'password': password},
      );
      final body = response.data;
      if (body?['access_token'] is String) await _saveSession(body!);
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  Future<void> signOut() async {
    try {
      if (await session.accessToken != null) {
        await dio.post<void>('/auth/v1/logout');
      }
    } on DioException catch (error) {
      if (error.response?.statusCode != 401) throw _mapError(error);
    } finally {
      await session.clear();
    }
  }

  Future<bool> hasSession() async => await session.accessToken != null;

  Future<Map<String, dynamic>> _saveSession(Map<String, dynamic> body) async {
    final accessToken = body['access_token'] as String?;
    final refreshToken = body['refresh_token'] as String?;
    if (accessToken == null || refreshToken == null) {
      throw const AuthException(
        'Compte créé. Vérifiez votre e-mail pour confirmer l’inscription.',
      );
    }
    await session.save(accessToken: accessToken, refreshToken: refreshToken);
    return Map<String, dynamic>.from(body['user'] as Map? ?? const {});
  }

  AuthException _mapError(DioException error) {
    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout) {
      return const AuthException(
        'Connexion indisponible. Vérifiez votre réseau puis réessayez.',
      );
    }
    final body = error.response?.data;
    if (body is Map && body['msg'] is String) {
      return AuthException(body['msg'] as String);
    }
    if (body is Map && body['message'] is String) {
      return AuthException(body['message'] as String);
    }
    if (error.response?.statusCode == 400 ||
        error.response?.statusCode == 401) {
      return const AuthException('E-mail ou mot de passe invalide.');
    }
    return const AuthException('Une erreur est survenue. Réessayez.');
  }
}
