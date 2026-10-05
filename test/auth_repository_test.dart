import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:real_app/core/network/session_store.dart';
import 'package:real_app/features/auth/auth_repository.dart';

class MockSessionStore extends Mock implements SessionStore {}

void main() {
  late MockSessionStore session;
  late AuthRepository repository;
  late Dio dio;
  late List<RequestOptions> requests;

  setUp(() {
    session = MockSessionStore();
    requests = [];
    dio = Dio(BaseOptions(baseUrl: 'https://project.supabase.co'))
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests.add(options);
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                data: {
                  'access_token': 'access-123',
                  'refresh_token': 'refresh-456',
                  'user': {'id': 'user-1'},
                },
              ),
            );
          },
        ),
      );
    repository = AuthRepository(
      dio: dio,
      session: session,
      supabaseUrl: 'https://project.supabase.co',
      publishableKey: 'test-publishable-key',
    );
  });

  test('exchanges OAuth code with the saved PKCE verifier', () async {
    when(() => session.oauthVerifier).thenAnswer((_) async => 'verifier-abc');
    when(() => session.oauthState).thenAnswer((_) async => 'state-123');
    when(() => session.clearOAuthAttempt()).thenAnswer((_) async {});
    when(
      () => session.save(
        accessToken: any(named: 'accessToken'),
        refreshToken: any(named: 'refreshToken'),
      ),
    ).thenAnswer((_) async {});

    await repository.completeOAuthCallback(
      Uri.parse('lebrief://login-callback?code=auth-code&state=state-123'),
    );

    expect(requests, hasLength(1));
    expect(requests.single.queryParameters, {'grant_type': 'pkce'});
    expect(requests.single.data, {
      'auth_code': 'auth-code',
      'code_verifier': 'verifier-abc',
    });
    expect(requests.single.headers['apikey'], 'test-publishable-key');
    verify(
      () =>
          session.save(accessToken: 'access-123', refreshToken: 'refresh-456'),
    ).called(1);
  });

  test(
    'rejects OAuth callbacks with an invalid state before exchanging a code',
    () async {
      when(() => session.oauthVerifier).thenAnswer((_) async => 'verifier-abc');
      when(() => session.oauthState).thenAnswer((_) async => 'expected-state');
      when(() => session.clearOAuthAttempt()).thenAnswer((_) async {});
      expect(
        repository.completeOAuthCallback(
          Uri.parse(
            'lebrief://login-callback?code=auth-code&state=wrong-state',
          ),
        ),
        throwsA(
          isA<AuthException>().having(
            (error) => error.message,
            'message',
            'La vérification de sécurité OAuth a échoué.',
          ),
        ),
      );
      expect(requests, isEmpty);
    },
  );

  test('surfaces provider errors from the OAuth callback', () async {
    when(() => session.clearOAuthAttempt()).thenAnswer((_) async {});
    expect(
      repository.completeOAuthCallback(
        Uri.parse('lebrief://login-callback?error=access_denied'),
      ),
      throwsA(
        isA<AuthException>().having(
          (error) => error.message,
          'message',
          'access_denied',
        ),
      ),
    );
  });

  test('rejects callbacks with missing PKCE state', () async {
    when(() => session.oauthVerifier).thenAnswer((_) async => null);
    when(() => session.oauthState).thenAnswer((_) async => null);
    expect(
      repository.completeOAuthCallback(
        Uri.parse('lebrief://login-callback?code=auth-code'),
      ),
      throwsA(isA<AuthException>()),
    );
  });

  test(
    'clears the local session when signing out without a stored token',
    () async {
      when(() => session.accessToken).thenAnswer((_) async => null);
      when(() => session.clear()).thenAnswer((_) async {});

      await repository.signOut();

      verify(() => session.clear()).called(1);
    },
  );
}
