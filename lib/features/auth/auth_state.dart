import 'package:flutter/foundation.dart';

import 'auth_repository.dart';

class AuthState extends ChangeNotifier {
  AuthState(this._repository);
  final AuthRepository _repository;
  bool signedIn = false;
  bool busy = false;
  String? message;

  Future<void> initialize() async {
    signedIn = await _repository.hasSession();
    notifyListeners();
  }

  Future<bool> signIn(String email, String password) => _run(() async {
    await _repository.signIn(email, password);
    signedIn = true;
  });
  Future<bool> signUp(String email, String password) => _run(() async {
    await _repository.signUp(email, password);
    signedIn = await _repository.hasSession();
    if (!signedIn) message = 'Inscription réussie. Confirmez votre adresse e-mail avant de vous connecter.';
  });

  Future<bool> signInWithGoogle() => _run(_repository.signInWithGoogle);

  Future<void> handleOAuthCallback(Uri uri) async {
    busy = true;
    message = null;
    notifyListeners();
    try {
      await _repository.completeOAuthCallback(uri);
      signedIn = true;
    } on AuthException catch (error) {
      message = error.message;
    } catch (_) {
      message = 'La connexion Google a échoué. Réessayez.';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<bool> signOut() => _run(() async {
    await _repository.signOut();
    signedIn = false;
  });

  Future<bool> _run(Future<void> Function() action) async {
    busy = true;
    message = null;
    notifyListeners();
    try {
      await action();
      return true;
    } on AuthException catch (error) {
      message = error.message;
      return false;
    } catch (_) {
      message = 'Une erreur est survenue. Réessayez.';
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }
}
