import 'package:dio/dio.dart';

import 'session_store.dart';

class SessionInterceptor extends Interceptor {
  SessionInterceptor({
    required this.session,
    required this.supabaseUrl,
    required this.anonKey,
  });

  final SessionStore session;
  final String supabaseUrl;
  final String anonKey;
  bool _refreshing = false;

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
    if (err.response?.statusCode != 401 || isAuthRoute || _refreshing) {
      handler.next(err);
      return;
    }

    final refreshToken = await session.refreshToken;
    if (refreshToken == null || supabaseUrl.isEmpty) {
      handler.next(err);
      return;
    }

    _refreshing = true;
    try {
      final response = await Dio().post<Map<String, dynamic>>(
        '$supabaseUrl/auth/v1/token',
        queryParameters: {'grant_type': 'refresh_token'},
        options: Options(headers: {'apikey': anonKey}),
        data: {'refresh_token': refreshToken},
      );
      final data = response.data!;
      await session.save(
        accessToken: data['access_token'] as String,
        refreshToken: data['refresh_token'] as String? ?? refreshToken,
      );
      final retry = err.requestOptions;
      retry.headers['Authorization'] = 'Bearer ${data['access_token']}';
      final retried = await Dio().fetch<dynamic>(retry);
      handler.resolve(retried);
    } on DioException catch (refreshError) {
      await session.clear();
      handler.next(refreshError);
    } finally {
      _refreshing = false;
    }
  }

  bool _isSupabase(Uri uri) =>
      supabaseUrl.isNotEmpty && uri.origin == Uri.parse(supabaseUrl).origin;
}
