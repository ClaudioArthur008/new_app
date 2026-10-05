# Le Brief — Flutter + NewsAPI

Application Flutter d’actualités en français avec trois vues connectées à une API REST : les titres du jour, les rubriques et la recherche. Les articles consultés sont gardés localement et restent lisibles sans réseau. L’application comprend aussi la création de compte, la connexion et la déconnexion via Supabase Auth.

## Architecture

Le code est organisé par fonctionnalité, avec séparation des responsabilités :

- `features/news/news_repository.dart` définit le modèle d’article, le contrat de données, la source Dio, le cache Hive et le repository.
- `features/auth/` contient le repository d’authentification et son état de présentation.
- `core/network/` configure l’injection du jeton Supabase, le renouvellement après une réponse 401 et le stockage sécurisé de la session.
- `main.dart` assemble les dépendances et les écrans.

Le repository tente d’abord l’API. En cas de panne réseau, il renvoie la dernière réponse mise en cache. S’il n’existe aucune copie locale, l’application affiche un message et une action pour réessayer.

## Services

- [NewsAPI](https://newsapi.org/docs) fournit les titres par pays et rubrique (`/v2/top-headlines`) et les résultats de recherche (`/v2/everything`). Créez une clé sur [newsapi.org](https://newsapi.org/register). La clé est envoyée dans l’en-tête `X-Api-Key`.
- [Supabase Auth](https://supabase.com/docs/guides/auth) fournit l’inscription, la connexion par e-mail/mot de passe, la déconnexion et le renouvellement des jetons. Créez un projet Supabase puis récupérez son URL et sa clé anon/publishable.
- Hive conserve le cache des réponses d’actualités. `flutter_secure_storage` conserve les jetons de session.

Le niveau gratuit NewsAPI est prévu pour le développement et n’autorise pas un déploiement public en production selon ses conditions. Une application publiée devrait appeler NewsAPI depuis un serveur intermédiaire afin de protéger la clé et respecter la licence du fournisseur.

## Configuration et lancement

Installez Flutter, puis récupérez les dépendances :

```sh
flutter pub get
```

Ouvrez `lib/config/app_config.dart` et renseignez les trois constantes avec vos valeurs locales :

```dart
static const newsApiKey = 'votre_cle_newsapi';
static const supabaseUrl = 'https://votre-projet.supabase.co';
static const supabaseAnonKey = 'votre_cle_anon_supabase';
```

Récupérez l’URL et la clé anon/publishable dans le tableau de bord Supabase : **Project Settings → API** (ou **API Keys** selon l’interface). Dans **Authentication → Providers**, activez **Email** pour utiliser inscription et connexion. La clé `anon`/`publishable` est une clé client ; n’utilisez jamais une clé `service_role` dans l’application.

Puis lancez l’application :

```sh
flutter run
```

Si Supabase n’est pas configuré, les écrans d’actualités restent accessibles mais les fonctions de compte sont désactivées. Si la clé NewsAPI est absente, le cache reste consultable après un premier chargement réussi. Laisse les valeurs vides dans toute version publiée du dépôt public et renseigne-les uniquement dans ta copie locale.

## Vérifications

```sh
flutter analyze
flutter test
```

Les tests du repository vérifient la réponse fraîche, le repli hors ligne sur le cache et le message d’erreur quand aucune copie n’est disponible.
=======
# real_app
Projet pour l'obtention du certificat en Connected app with real backend durant la FlutterFire Summer Camp.
