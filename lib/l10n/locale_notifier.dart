import 'package:flutter/material.dart';
import '../services/storage_service.dart';

/// Holds the app locale and persists it via [StorageService].
class LocaleNotifier extends ChangeNotifier {
  LocaleNotifier(this._storage) {
    _load();
  }

  final StorageService _storage;
  Locale _locale = const Locale('en');

  static const supportedLanguageCodes = ['en', 'vi'];

  Locale get locale => _locale;

  Future<void> _load() async {
    final code = await _storage.getLocale();
    if (code != null && supportedLanguageCodes.contains(code)) {
      _locale = Locale(code);
      notifyListeners();
    }
  }

  Future<void> setLocale(String languageCode) async {
    if (!supportedLanguageCodes.contains(languageCode)) return;
    await _storage.setLocale(languageCode);
    _locale = Locale(languageCode);
    notifyListeners();
  }
}
