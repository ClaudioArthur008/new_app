import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/network/session_store.dart';

class AuthException implements Exception {
  const AuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

class AuthRepository {
  AuthRepository({
    required this.dio,
    required this.session,
    required this.supabaseUrl,
    required this.publishableKey,
  });
  final Dio dio;
  final SessionStore session;
  final String supabaseUrl;
  final String publishableKey;

  Future<Map<String, dynamic>> signIn(String email, String password) async {
    _validateCredentials(email, password);
    try {
      final response = await dio.post<Map<String, dynamic>>(
        '/auth/v1/token',
        queryParameters: {'grant_type': 'password'},
        data: {'email': email, 'password': password},
      );
      final body = response.data;
      if (body == null) {
        throw const AuthException('Réponse d’authentification invalide.');
      }
      return await _saveSession(body);
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  Future<void> signUp(String email, String password) async {
    _validateCredentials(email, password);
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

  Future<void> signInWithGoogle() async {
    if (supabaseUrl.isEmpty || publishableKey.isEmpty) {
      throw const AuthException('Configurez Supabase avant de vous connecter.');
    }
    final verifier = _randomUrlSafe(32);
    final state = _randomUrlSafe(24);
    final challenge = base64Url
        .encode(sha256.convert(ascii.encode(verifier)).bytes)
        .replaceAll('=', '');
    await session.saveOAuthAttempt(verifier: verifier, state: state);
    final redirectUri = Uri.parse('lebrief://login-callback');
    final authorizationUri = Uri.parse('$supabaseUrl/auth/v1/authorize')
        .replace(
          queryParameters: {
            'provider': 'google',
            'redirect_to': redirectUri.toString(),
            'code_challenge': challenge,
            'code_challenge_method': 's256',
            'state': state,
            'apikey': publishableKey,
          },
        );
    if (!await launchUrl(
      authorizationUri,
      mode: LaunchMode.externalApplication,
    )) {
      await session.clearOAuthAttempt();
      throw const AuthException('Impossible d’ouvrir la connexion Google.');
    }
  }

  Future<void> completeOAuthCallback(Uri uri) async {
    final parameters = uri.queryParameters;
    final error = parameters['error_description'] ?? parameters['error'];
    if (error != null) {
      await session.clearOAuthAttempt();
      throw AuthException(error);
    }
    final code = parameters['code'];
    final state = parameters['state'];
    final verifier = await session.oauthVerifier;
    final expectedState = await session.oauthState;
    if (code == null ||
        state == null ||
        verifier == null ||
        expectedState == null) {
      throw const AuthException(
        'La réponse de connexion Google est incomplète ou a expiré.',
      );
    }
    if (state != expectedState) {
      await session.clearOAuthAttempt();
      throw const AuthException('La vérification de sécurité OAuth a échoué.');
    }
    try {
      final response = await dio.post<Map<String, dynamic>>(
        '/auth/v1/token',
        queryParameters: {'grant_type': 'pkce'},
        data: {'auth_code': code, 'code_verifier': verifier},
        options: Options(headers: {'apikey': publishableKey}),
      );
      final body = response.data;
      if (body == null) {
        throw const AuthException('Réponse d’authentification invalide.');
      }
      await _saveSession(body);
    } on DioException catch (error) {
      throw _mapError(error);
    } finally {
      await session.clearOAuthAttempt();
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
        error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout) {
      return const AuthException(
        'Connexion indisponible. Vérifiez votre réseau puis réessayez.',
      );
    }
    final body = error.response?.data;
    if (body is Map) {
      for (final key in ['msg', 'message', 'error_description', 'error']) {
        final message = body[key];
        if (message is String && message.trim().isNotEmpty) {
          return AuthException(message);
        }
      }
    }
    if (error.response?.statusCode == 400 ||
        error.response?.statusCode == 401) {
      return const AuthException('E-mail ou mot de passe invalide.');
    }
    if (error.response?.statusCode == 429) {
      return const AuthException('Trop de tentatives. Réessayez plus tard.');
    }
    return const AuthException('Une erreur est survenue. Réessayez.');
  }

  void _validateCredentials(String email, String password) {
    if (!email.contains('@') || email.trim().isEmpty) {
      throw const AuthException('Saisissez une adresse e-mail valide.');
    }
    if (password.isEmpty) {
      throw const AuthException('Saisissez votre mot de passe.');
    }
    if (password.length < 6) {
      throw const AuthException(
        'Le mot de passe doit contenir au moins 6 caractères.',
      );
    }
  }

  String _randomUrlSafe(int length) {
    final random = Random.secure();
    return base64Url
        .encode(List<int>.generate(length, (_) => random.nextInt(256)))
        .replaceAll('=', '');
  }
}
