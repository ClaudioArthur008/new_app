import 'package:dio/dio.dart';

import 'session_store.dart';

class SessionInterceptor extends Interceptor {
  SessionInterceptor({
    required this.session,
    required this.supabaseUrl,
    required this.anonKey,
    required this.refreshClient,
    required this.replayClient,
  });

  final SessionStore session;
  final String supabaseUrl;
  final String anonKey;
  final Dio refreshClient;
  final Dio replayClient;
  Future<String?>? _refreshing;

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (_isSupabase(options.uri)) {
      options.headers['apikey'] = anonKey;
      final token = await session.accessToken;
      if (token != null) options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (!_isSupabase(err.requestOptions.uri)) {
      handler.next(err);
      return;
    }
    final isAuthRoute =
        err.requestOptions.path.contains('/auth/v1/token') ||
        err.requestOptions.path.contains('/auth/v1/signup') ||
        err.requestOptions.path.contains('/auth/v1/logout');
    if (err.response?.statusCode != 401 ||
        isAuthRoute ||
        err.requestOptions.extra['authRetry'] == true) {
      handler.next(err);
      return;
    }

    final refreshToken = await session.refreshToken;
    if (refreshToken == null || supabaseUrl.isEmpty) {
      handler.next(err);
      return;
    }

    final accessToken = await _refreshAccessToken(refreshToken);
    if (accessToken == null) {
      handler.next(err);
      return;
    }
    try {
      final retry = err.requestOptions;
      retry.headers['Authorization'] = 'Bearer $accessToken';
      retry.extra['authRetry'] = true;
      handler.resolve(await replayClient.fetch<dynamic>(retry));
    } on DioException catch (retryError) {
      handler.next(retryError);
    }
  }

  Future<String?> _refreshAccessToken(String refreshToken) {
    final pending = _refreshing;
    if (pending != null) return pending;
    final refresh = _performRefresh(refreshToken);
    _refreshing = refresh;
    return refresh.whenComplete(() {
      if (identical(_refreshing, refresh)) _refreshing = null;
    });
  }

  Future<String?> _performRefresh(String refreshToken) async {
    try {
      final response = await refreshClient.post<Map<String, dynamic>>(
        '$supabaseUrl/auth/v1/token',
        queryParameters: {'grant_type': 'refresh_token'},
        options: Options(headers: {'apikey': anonKey}),
        data: {'refresh_token': refreshToken},
      );
      final data = response.data ?? const <String, dynamic>{};
      final accessToken = data['access_token'] as String?;
      if (accessToken == null) {
        throw const FormatException('Missing access token');
      }
      await session.save(
        accessToken: accessToken,
        refreshToken: data['refresh_token'] as String? ?? refreshToken,
      );
      return accessToken;
    } on DioException {
      await session.clear();
      return null;
    } on FormatException {
      await session.clear();
      return null;
    }
  }

  bool _isSupabase(Uri uri) =>
      supabaseUrl.isNotEmpty && uri.origin == Uri.parse(supabaseUrl).origin;
}
