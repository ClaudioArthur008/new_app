import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:real_app/core/network/session_store.dart';
import 'package:real_app/features/auth/auth_repository.dart';

class MockSessionStore extends Mock implements SessionStore {}

void main() {
  late MockSessionStore session;
  late List<RequestOptions> requests;

  AuthRepository repository({required bool rejectRequest}) {
    final dio = Dio(BaseOptions(baseUrl: 'https://project.supabase.co'))
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests.add(options);
            if (rejectRequest) {
              handler.reject(
                DioException(
                  requestOptions: options,
                  response: Response<Map<String, dynamic>>(
                    requestOptions: options,
                    statusCode: 401,
                    data: {'msg': 'Invalid login credentials'},
                  ),
                  type: DioExceptionType.badResponse,
                ),
              );
              return;
            }
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                data: {
                  'access_token': 'access-token',
                  'refresh_token': 'refresh-token',
                  'user': {'id': 'user-1'},
                },
              ),
            );
          },
        ),
      );
    return AuthRepository(
      dio: dio,
      session: session,
      supabaseUrl: 'https://project.supabase.co',
      publishableKey: 'test-key',
    );
  }

  setUp(() {
    session = MockSessionStore();
    requests = [];
  });

  test('logs in and securely persists both session tokens', () async {
    when(
      () => session.save(
        accessToken: any(named: 'accessToken'),
        refreshToken: any(named: 'refreshToken'),
      ),
    ).thenAnswer((_) async {});

    final user = await repository(rejectRequest: false)
        .signIn('reader@example.com', 'secret123');

    expect(user, {'id': 'user-1'});
    expect(requests.single.data, {
      'email': 'reader@example.com',
      'password': 'secret123',
    });
    verify(
      () => session.save(
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
      ),
    ).called(1);
  });

  test('converts rejected credentials to a readable auth error', () async {
    await expectLater(
      repository(rejectRequest: true).signIn('reader@example.com', 'wrongpass'),
      throwsA(
        isA<AuthException>().having(
          (error) => error.message,
          'message',
          'Invalid login credentials',
        ),
      ),
    );
  });

  test('rejects malformed email before making a network request', () async {
    await expectLater(
      repository(rejectRequest: false).signIn('not-an-email', 'secret123'),
      throwsA(
        isA<AuthException>().having(
          (error) => error.message,
          'message',
          'Saisissez une adresse e-mail valide.',
        ),
      ),
    );
    expect(requests, isEmpty);
  });
}
