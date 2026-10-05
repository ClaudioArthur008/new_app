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

Ne placez pas de clé API dans un fichier suivi par Git. Passez les valeurs au démarrage de Flutter :

```powershell
flutter run `
  --dart-define=NEWS_API_KEY=TA_CLE_NEWSAPI `
  --dart-define=SUPABASE_URL=https://TON_PROJET.supabase.co `
  --dart-define=SUPABASE_ANON_KEY=TA_CLE_PUBLISHABLE
```

Récupérez l’URL et la clé anon/publishable dans le tableau de bord Supabase : **Project Settings → API** (ou **API Keys** selon l’interface). Dans **Authentication → Providers**, activez **Email** pour utiliser inscription et connexion. La clé `anon`/`publishable` est une clé client ; n’utilisez jamais une clé `service_role` dans l’application.

Les valeurs proviennent du tableau de bord NewsAPI et de Supabase. `lib/config/app_config.dart` les lit depuis `String.fromEnvironment`; aucun secret réel n’est commité. Si Supabase n’est pas configuré, les écrans d’actualités restent accessibles mais les fonctions de compte sont désactivées.

## Authentification

Le compte e-mail/mot de passe utilise les endpoints Supabase Auth `signup`, `token?grant_type=password` et `logout`. Les jetons sont conservés par `flutter_secure_storage`. L’intercepteur ajoute la clé publishable et le jeton aux seules requêtes adressées au projet Supabase. Sur une réponse `401`, une seule requête de renouvellement est partagée entre les appels concurrents ; la requête d’origine est ensuite rejouée une fois. Les jetons sont effacés si le renouvellement échoue.

La connexion Google est optionnelle. Pour l’activer :

1. Dans Supabase, ouvrez **Authentication → Providers → Google** et activez le fournisseur. Créez un client OAuth de type **Web application** dans Google Cloud, puis copiez son identifiant et son secret dans Supabase.
2. Dans la console Google Cloud, ajoutez comme URI de redirection autorisée l’URL de rappel Supabase affichée dans la configuration du fournisseur Google (elle se termine par `/auth/v1/callback`).
3. Dans Supabase, ouvrez **Authentication → URL Configuration → Redirect URLs** et ajoutez `lebrief://login-callback`, qui renvoie vers l’application mobile.

La configuration native déclare ce lien profond sur Android et iOS. Désactivez **Confirm email** dans Supabase uniquement si vous souhaitez tester l’inscription sans vérification de boîte de réception.

## Gestion des erreurs et mode hors ligne

Les réponses NewsAPI sont mises en cache dans Hive par rubrique et par recherche. Les erreurs réseau affichent les articles enregistrés avec un indicateur hors ligne ; sans cache, l’interface affiche un message lisible et un bouton Réessayer. Les erreurs de compte distinguent les identifiants refusés, les problèmes réseau et les réponses renvoyées par Supabase. Cette app utilise uniquement les ressources de lecture de NewsAPI.

## Intégration continue

Le workflow `.github/workflows/flutter.yml` vérifie le formatage, l’analyse statique et les tests avec Flutter stable à chaque push et pull request vers `main`. Il produit également un rapport de couverture dans les artefacts de test.

## Notes de déploiement

Les tests du projet sont des tests unitaires du repository avec des sources simulées ; ils n’appellent pas les services distants. Avant une mise en production, ajouter des tests du flux OAuth sur appareil et des tests d’intégration réseau. La clé publishable Supabase est prévue pour le client, mais ne jamais y mettre une clé `secret`/`service_role`. La clé NewsAPI reste extractible d’une application mobile ; le forfait Developer est réservé au développement, donc un serveur intermédiaire et un forfait adapté sont nécessaires pour une app publiée.

## Vérifications

```sh
flutter analyze
flutter test
```
