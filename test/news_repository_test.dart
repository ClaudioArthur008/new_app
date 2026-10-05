import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:real_app/features/news/news_repository.dart';

class MockRemote extends Mock implements NewsRemoteSource {}

class MockCache extends Mock implements NewsCache {}

void main() {
  late MockRemote remote;
  late MockCache cache;
  late NewsRepository repository;
  const article = NewsArticle(
    title: 'Titre',
    url: 'https://example.com',
    source: 'Journal',
  );

  setUp(() {
    remote = MockRemote();
    cache = MockCache();
    repository = NewsRepository(remote: remote, cache: cache);
  });

  test('returns fresh headlines and persists them to cache', () async {
    when(() => remote.headlines(country: 'fr', category: null))
        .thenAnswer((_) async => [article]);
    when(() => cache.write(any(), any())).thenAnswer((_) async {});

    final result = await repository.getHeadlines(country: 'fr');

    expect(result.articles.single.title, 'Titre');
    expect(result.fromCache, isFalse);
    verify(() => cache.write('headlines:fr:all', any())).called(1);
  });

  test('serves cached headlines when the request has no network', () async {
    when(() => remote.headlines(country: 'fr', category: null)).thenThrow(
      DioException(
        requestOptions: RequestOptions(path: '/top-headlines'),
        type: DioExceptionType.connectionError,
      ),
    );
    when(() => cache.read('headlines:fr:all'))
        .thenAnswer((_) async => [article]);

    final result = await repository.getHeadlines(country: 'fr');

    expect(result.articles.single.title, 'Titre');
    expect(result.fromCache, isTrue);
  });

  test('returns a readable network error when no cached copy exists', () async {
    when(() => remote.headlines(country: 'fr', category: null)).thenThrow(
      DioException(
        requestOptions: RequestOptions(path: '/top-headlines'),
        type: DioExceptionType.connectionError,
      ),
    );
    when(() => cache.read('headlines:fr:all')).thenAnswer((_) async => null);

    expect(
      () => repository.getHeadlines(country: 'fr'),
      throwsA(
        isA<NewsException>().having(
          (error) => error.message,
          'message',
          contains('Pas de connexion'),
        ),
      ),
    );
  });
}
