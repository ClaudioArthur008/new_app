import 'package:app_links/app_links.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'core/network/session_interceptor.dart';
import 'core/network/session_store.dart';
import 'config/app_config.dart';
import 'features/auth/auth_repository.dart';
import 'features/auth/auth_state.dart';
import 'features/news/news_repository.dart';

const _ink = Color(0xFF172A3A);
const _paper = Color(0xFFF5F4F0);
const _accent = Color(0xFFE56B4A);
const _categories = <String, String>{
  'Général': 'general',
  'Business': 'business',
  'Technologie': 'technology',
  'Science': 'science',
  'Santé': 'health',
  'Culture': 'entertainment',
  'Sport': 'sports',
};

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  final cache = HiveNewsCache(await Hive.openBox<String>('news_cache'));
  final newsKey = AppConfig.newsApiKey;
  final supabaseUrl = AppConfig.supabaseUrl;
  final supabaseKey = AppConfig.supabaseAnonKey;
  final session = SessionStore(const FlutterSecureStorage());
  final interceptor = SessionInterceptor(
    session: session,
    supabaseUrl: supabaseUrl,
    anonKey: supabaseKey,
    refreshClient: Dio(),
    replayClient: Dio(),
  );
  final newsDio = Dio(
    BaseOptions(
      baseUrl: 'https://newsapi.org/v2',
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 12),
      headers: {if (newsKey.isNotEmpty) 'X-Api-Key': newsKey},
    ),
  )..interceptors.add(interceptor);
  final authDio = Dio(
    BaseOptions(
      baseUrl: supabaseUrl,
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 12),
    ),
  )..interceptors.add(interceptor);
  final news = NewsRepository(
    remote: DioNewsRemoteSource(newsDio),
    cache: cache,
  );
  final auth = AuthState(
    AuthRepository(
      dio: authDio,
      session: session,
      supabaseUrl: supabaseUrl,
      publishableKey: supabaseKey,
    ),
  );
  await auth.initialize();
  final appLinks = AppLinks();
  appLinks.uriLinkStream.listen(auth.handleOAuthCallback);
  final initialUri = await appLinks.getInitialLink();
  if (initialUri != null) await auth.handleOAuthCallback(initialUri);
  runApp(
    PressApp(
      news: news,
      auth: auth,
      newsKeyConfigured: newsKey.isNotEmpty,
      authConfigured: supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty,
    ),
  );
}

class PressApp extends StatelessWidget {
  const PressApp({
    super.key,
    required this.news,
    required this.auth,
    required this.newsKeyConfigured,
    required this.authConfigured,
  });
  final NewsRepository news;
  final AuthState auth;
  final bool newsKeyConfigured;
  final bool authConfigured;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Le Brief',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: _paper,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _ink,
        primary: _ink,
        secondary: _accent,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: _paper,
        foregroundColor: _ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide.none,
        ),
      ),
    ),
    home: NewsHome(
      news: news,
      auth: auth,
      newsKeyConfigured: newsKeyConfigured,
      authConfigured: authConfigured,
    ),
  );
}

class NewsHome extends StatefulWidget {
  const NewsHome({
    super.key,
    required this.news,
    required this.auth,
    required this.newsKeyConfigured,
    required this.authConfigured,
  });
  final NewsRepository news;
  final AuthState auth;
  final bool newsKeyConfigured;
  final bool authConfigured;
  @override
  State<NewsHome> createState() => _NewsHomeState();
}

class _NewsHomeState extends State<NewsHome> {
  int _tab = 0;
  @override
  Widget build(BuildContext context) {
    final pages = [
      HeadlinesPage(
        repository: widget.news,
        configured: widget.newsKeyConfigured,
      ),
      CategoryPage(
        repository: widget.news,
        configured: widget.newsKeyConfigured,
      ),
      SearchPage(repository: widget.news, configured: widget.newsKeyConfigured),
      AccountPage(auth: widget.auth, configured: widget.authConfigured),
    ];
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(index: _tab, children: pages),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        backgroundColor: Colors.white,
        indicatorColor: const Color(0xFFE8E9E7),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.auto_stories_outlined),
            selectedIcon: Icon(Icons.auto_stories),
            label: 'À la une',
          ),
          NavigationDestination(
            icon: Icon(Icons.grid_view_rounded),
            label: 'Rubriques',
          ),
          NavigationDestination(
            icon: Icon(Icons.search_rounded),
            label: 'Recherche',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            label: 'Compte',
          ),
        ],
      ),
    );
  }
}

class HeadlinesPage extends StatefulWidget {
  const HeadlinesPage({
    super.key,
    required this.repository,
    required this.configured,
  });
  final NewsRepository repository;
  final bool configured;
  @override
  State<HeadlinesPage> createState() => _HeadlinesPageState();
}

class _HeadlinesPageState extends State<HeadlinesPage> {
  late Future<NewsResult> _future;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => _future = widget.repository.getHeadlines(country: 'us');
  Future<void> _refresh() async {
    setState(_load);
    await _future;
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: _refresh,
    child: CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        const SliverToBoxAdapter(
          child: PageHeader(kicker: 'LE MONDE, EN BREF', title: 'À la une'),
        ),
        if (!widget.configured)
          const SliverToBoxAdapter(child: ApiSetupBanner()),
        SliverToBoxAdapter(
          child: FutureBuilder<NewsResult>(
            future: _future,
            builder: (context, snapshot) =>
                NewsList(snapshot: snapshot, onRetry: () => setState(_load)),
          ),
        ),
      ],
    ),
  );
}

class CategoryPage extends StatefulWidget {
  const CategoryPage({
    super.key,
    required this.repository,
    required this.configured,
  });
  final NewsRepository repository;
  final bool configured;
  @override
  State<CategoryPage> createState() => _CategoryPageState();
}

class _CategoryPageState extends State<CategoryPage> {
  String _selected = 'general';
  late Future<NewsResult> _future;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => _future = widget.repository.getHeadlines(
    country: 'us',
    category: _selected,
  );
  @override
  Widget build(BuildContext context) => CustomScrollView(
    slivers: [
      const SliverToBoxAdapter(
        child: PageHeader(kicker: 'CHOISISSEZ VOTRE SUJET', title: 'Rubriques'),
      ),
      SliverToBoxAdapter(
        child: SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            children: _categories.entries
                .map(
                  (entry) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(entry.key),
                      selected: _selected == entry.value,
                      onSelected: (_) => setState(() {
                        _selected = entry.value;
                        _load();
                      }),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ),
      if (!widget.configured) const SliverToBoxAdapter(child: ApiSetupBanner()),
      SliverToBoxAdapter(
        child: FutureBuilder<NewsResult>(
          key: ValueKey(_selected),
          future: _future,
          builder: (context, snapshot) =>
              NewsList(snapshot: snapshot, onRetry: () => setState(_load)),
        ),
      ),
    ],
  );
}

class SearchPage extends StatefulWidget {
  const SearchPage({
    super.key,
    required this.repository,
    required this.configured,
  });
  final NewsRepository repository;
  final bool configured;
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();
  Future<NewsResult>? _future;
  void _search() {
    final query = _controller.text.trim();
    if (query.isNotEmpty) {
      setState(() => _future = widget.repository.search(query));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CustomScrollView(
    slivers: [
      const SliverToBoxAdapter(
        child: PageHeader(kicker: 'EXPLOREZ L’ACTUALITÉ', title: 'Recherche'),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
          child: TextField(
            controller: _controller,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
            decoration: InputDecoration(
              hintText: 'Un sujet, un mot-clé…',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                icon: const Icon(Icons.arrow_forward_rounded),
                onPressed: _search,
              ),
            ),
          ),
        ),
      ),
      if (!widget.configured) const SliverToBoxAdapter(child: ApiSetupBanner()),
      if (_future != null)
        SliverToBoxAdapter(
          child: FutureBuilder<NewsResult>(
            future: _future,
            builder: (context, snapshot) =>
                NewsList(snapshot: snapshot, onRetry: _search),
          ),
        ),
      if (_future == null)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(28),
            child: Text(
              'Recherchez un sujet pour découvrir les articles récents.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54),
            ),
          ),
        ),
    ],
  );
}

class NewsList extends StatelessWidget {
  const NewsList({super.key, required this.snapshot, required this.onRetry});
  final AsyncSnapshot<NewsResult> snapshot;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return const Padding(
        padding: EdgeInsets.all(50),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (snapshot.hasError) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.wifi_off_rounded, size: 34, color: _accent),
            const SizedBox(height: 12),
            Text(snapshot.error.toString(), textAlign: TextAlign.center),
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer'),
            ),
          ],
        ),
      );
    }
    final result = snapshot.data;
    if (result == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (result.fromCache)
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: OfflinePill(),
          ),
        if (result.articles.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('Aucun article trouvé.'),
          ),
        ...result.articles.map((article) => ArticleTile(article: article)),
        const SizedBox(height: 18),
      ],
    );
  }
}

class ArticleTile extends StatelessWidget {
  const ArticleTile({super.key, required this.article});
  final NewsArticle article;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
    child: Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          backgroundColor: _paper,
          builder: (_) => ArticleSheet(article: article),
        ),
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (article.imageUrl.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: AspectRatio(
                    aspectRatio: 1.8,
                    child: Image.network(
                      article.imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          const ColoredBox(
                            color: Color(0xFFE8E9E7),
                            child: Center(
                              child: Icon(
                                Icons.image_not_supported_outlined,
                                color: Colors.black38,
                              ),
                            ),
                          ),
                    ),
                  ),
                )
              else
                const SizedBox(height: 4),
              const SizedBox(height: 12),
              Text(
                article.source.toUpperCase(),
                style: const TextStyle(
                  color: _accent,
                  fontSize: 10,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                article.title,
                style: const TextStyle(
                  color: _ink,
                  fontSize: 18,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (article.description.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  article.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.black54, height: 1.35),
                ),
              ],
              const SizedBox(height: 9),
              Text(
                _date(article.publishedAt),
                style: const TextStyle(fontSize: 11, color: Colors.black45),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class ArticleSheet extends StatelessWidget {
  const ArticleSheet({super.key, required this.article});
  final NewsArticle article;
  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              article.source.toUpperCase(),
              style: const TextStyle(
                color: _accent,
                letterSpacing: 1.5,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              article.title,
              style: const TextStyle(
                fontSize: 25,
                height: 1.15,
                fontWeight: FontWeight.w800,
                color: _ink,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              article.description.isEmpty
                  ? 'Ouvrez la source pour lire l’article complet.'
                  : article.description,
              style: const TextStyle(fontSize: 16, height: 1.45),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: article.url.isEmpty
                  ? null
                  : () => launchUrl(
                      Uri.parse(article.url),
                      mode: LaunchMode.externalApplication,
                    ),
              icon: const Icon(Icons.open_in_new),
              label: const Text('Lire sur le site'),
            ),
          ],
        ),
      ),
    ),
  );
}

class AccountPage extends StatefulWidget {
  const AccountPage({super.key, required this.auth, required this.configured});
  final AuthState auth;
  final bool configured;
  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _register = false;
  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final ok = _register
        ? await widget.auth.signUp(_email.text.trim(), _password.text)
        : await widget.auth.signIn(_email.text.trim(), _password.text);
    if (mounted && ok && widget.auth.signedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_register ? 'Bienvenue !' : 'Connexion réussie.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.auth,
    builder: (context, _) {
      if (widget.auth.signedIn) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(26),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircleAvatar(
                  radius: 36,
                  backgroundColor: Colors.white,
                  child: Icon(Icons.person, size: 36, color: _ink),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Vous êtes connecté',
                  style: TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.w800,
                    color: _ink,
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton.tonalIcon(
                  onPressed: widget.auth.busy ? null : widget.auth.signOut,
                  icon: const Icon(Icons.logout),
                  label: const Text('Se déconnecter'),
                ),
              ],
            ),
          ),
        );
      }
      return ListView(
        padding: const EdgeInsets.fromLTRB(22, 38, 22, 20),
        children: [
          const Text(
            'VOTRE ESPACE',
            style: TextStyle(
              color: _accent,
              letterSpacing: 2,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _register ? 'Créer un compte' : 'Connexion',
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              color: _ink,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Enregistrez vos préférences et retrouvez votre expérience.',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 24),
          if (!widget.configured) const ApiSetupBanner(auth: true),
          if (widget.configured) ...[
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Adresse e-mail',
                prefixIcon: Icon(Icons.email_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Mot de passe',
                prefixIcon: Icon(Icons.lock_outline),
              ),
            ),
            if (widget.auth.message != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  widget.auth.message!,
                  style: const TextStyle(color: _accent),
                ),
              ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: widget.auth.busy ? null : _submit,
              child: widget.auth.busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_register ? 'Créer mon compte' : 'Se connecter'),
            ),
            OutlinedButton.icon(
              onPressed: widget.auth.busy
                  ? null
                  : () => widget.auth.signInWithGoogle(),
              icon: const Icon(Icons.g_mobiledata_rounded),
              label: const Text('Continuer avec Google'),
            ),
            TextButton(
              onPressed: () => setState(() {
                _register = !_register;
                widget.auth.message = null;
              }),
              child: Text(
                _register ? 'J’ai déjà un compte' : 'Créer un compte',
              ),
            ),
          ],
        ],
      );
    },
  );
}

class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.kicker, required this.title});
  final String kicker;
  final String title;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(22, 28, 22, 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.circle, size: 9, color: _accent),
            const SizedBox(width: 8),
            Text(
              kicker,
              style: const TextStyle(
                color: _accent,
                letterSpacing: 1.7,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          title,
          style: const TextStyle(
            color: _ink,
            fontSize: 34,
            fontWeight: FontWeight.w800,
            letterSpacing: -1,
          ),
        ),
        const SizedBox(height: 2),
        const Text(
          'Le regard juste sur ce qui se passe.',
          style: TextStyle(color: Colors.black45),
        ),
      ],
    ),
  );
}

class ApiSetupBanner extends StatelessWidget {
  const ApiSetupBanner({super.key, this.auth = false});
  final bool auth;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(20, 0, 20, 14),
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: const Color(0xFFFFE9E1),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline, color: _accent),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            auth
                ? 'Configurez SUPABASE_URL et SUPABASE_ANON_KEY pour activer inscription et connexion.'
                : 'Configurez NEWS_API_KEY pour charger les articles (voir le README).',
            style: const TextStyle(color: _ink, height: 1.35),
          ),
        ),
      ],
    ),
  );
}

class OfflinePill extends StatelessWidget {
  const OfflinePill({super.key});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      color: const Color(0xFFE7E9E6),
      borderRadius: BorderRadius.circular(20),
    ),
    child: const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.cloud_off_outlined, size: 15),
        SizedBox(width: 6),
        Text(
          'Mode hors ligne · articles enregistrés',
          style: TextStyle(fontSize: 12),
        ),
      ],
    ),
  );
}

String _date(String value) {
  final date = DateTime.tryParse(value)?.toLocal();
  if (date == null) return 'Date inconnue';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(date.day)}/${two(date.month)}/${date.year} · ${two(date.hour)}:${two(date.minute)}';
}
