import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';

class NewsArticle {
  const NewsArticle({
    required this.title,
    required this.url,
    required this.source,
    this.description = '',
    this.imageUrl = '',
    this.publishedAt = '',
  });
  final String title;
  final String url;
  final String source;
  final String description;
  final String imageUrl;
  final String publishedAt;

  factory NewsArticle.fromJson(Map<String, dynamic> json) => NewsArticle(
    title: json['title'] as String? ?? 'Sans titre',
    url: json['url'] as String? ?? '',
    source: (json['source'] as Map?)?['name'] as String? ?? 'Source inconnue',
    description: json['description'] as String? ?? '',
    imageUrl: json['urlToImage'] as String? ?? '',
    publishedAt: json['publishedAt'] as String? ?? '',
  );
  Map<String, dynamic> toJson() => {
    'title': title,
    'url': url,
    'source': {'name': source},
    'description': description,
    'urlToImage': imageUrl,
    'publishedAt': publishedAt,
  };
}

class NewsResult {
  const NewsResult(this.articles, {this.fromCache = false});
  final List<NewsArticle> articles;
  final bool fromCache;
}

class NewsException implements Exception {
  const NewsException(this.message);
  final String message;
  @override
  String toString() => message;
}

abstract interface class NewsRemoteSource {
  Future<List<NewsArticle>> headlines({
    required String country,
    String? category,
  });
  Future<List<NewsArticle>> search(String query);
}

abstract interface class NewsCache {
  Future<List<NewsArticle>?> read(String key);
  Future<void> write(String key, List<NewsArticle> articles);
}

class DioNewsRemoteSource implements NewsRemoteSource {
  DioNewsRemoteSource(this._dio);
  final Dio _dio;
  @override
  Future<List<NewsArticle>> headlines({
    required String country,
    String? category,
  }) => _get('/top-headlines', {'country': country, 'category': ?category});
  @override
  Future<List<NewsArticle>> search(String query) =>
      _get('/everything', {'q': query, 'sortBy': 'publishedAt'});

  Future<List<NewsArticle>> _get(
    String path,
    Map<String, dynamic> params,
  ) async {
    final response = await _dio.get<Map<String, dynamic>>(
      path,
      queryParameters: params,
    );
    final data = response.data ?? const {};
    if (data['status'] == 'error') {
      throw NewsException(data['message'] as String? ?? 'Erreur NewsAPI');
    }
    return (data['articles'] as List? ?? const [])
        .map(
          (item) =>
              NewsArticle.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
  }
}

class HiveNewsCache implements NewsCache {
  HiveNewsCache(this._box);
  final Box<String> _box;
  @override
  Future<List<NewsArticle>?> read(String key) async {
    final raw = _box.get(key);
    if (raw == null) return null;
    return (jsonDecode(raw) as List)
        .map(
          (item) =>
              NewsArticle.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
  }

  @override
  Future<void> write(String key, List<NewsArticle> articles) => _box.put(
    key,
    jsonEncode(articles.map((article) => article.toJson()).toList()),
  );
}

class NewsRepository {
  NewsRepository({required this.remote, required this.cache});
  final NewsRemoteSource remote;
  final NewsCache cache;

  Future<NewsResult> getHeadlines({String country = 'us', String? category}) =>
      _load(
        'headlines:$country:${category ?? 'all'}',
        () => remote.headlines(country: country, category: category),
      );
  Future<NewsResult> search(String query) =>
      _load('search:${query.trim().toLowerCase()}', () => remote.search(query));

  Future<NewsResult> _load(
    String key,
    Future<List<NewsArticle>> Function() fetch,
  ) async {
    try {
      final articles = await fetch();
      await cache.write(key, articles);
      return NewsResult(articles);
    } on DioException catch (error) {
      if (_canUseCache(error)) {
        final cached = await cache.read(key);
        if (cached != null) return NewsResult(cached, fromCache: true);
      }
      throw NewsException(_messageFor(error));
    } on NewsException {
      rethrow;
    } on FormatException {
      throw const NewsException(
        'La réponse NewsAPI est invalide. Réessayez plus tard.',
      );
    }
  }

  bool _canUseCache(DioException error) {
    final status = error.response?.statusCode;
    return error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        (status != null && status >= 500);
  }

  String _messageFor(DioException error) {
    final body = error.response?.data;
    if (body is Map) {
      final message = body['message'];
      if (message is String && message.trim().isNotEmpty) return message;
    }
    if (error.response?.statusCode == 401) {
      return 'Clé NewsAPI invalide ou absente. Vérifiez NEWS_API_KEY.';
    }
    if (error.response?.statusCode == 429) {
      return 'Limite de requêtes NewsAPI atteinte. Réessayez plus tard.';
    }
    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout) {
      return 'Pas de connexion. Réessayez lorsque le réseau sera disponible.';
    }
    return 'Impossible de charger les actualités. Réessayez dans un instant.';
  }
}
