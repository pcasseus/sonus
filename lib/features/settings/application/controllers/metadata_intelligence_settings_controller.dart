import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/privacy/online_lookup_consent.dart';

class MetadataIntelligenceSettingsController extends ChangeNotifier
    implements OnlineLookupConsent {
  MetadataIntelligenceSettingsController({
    Future<SharedPreferences> Function()? preferencesLoader,
  }) : _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  static const onlineMetadataLookupKey =
      'metadata_intelligence.online_metadata_lookup_enabled';
  static const coverArtSuggestionsKey =
      'metadata_intelligence.cover_art_suggestions_enabled';
  static const onlineLookupAcceptedKey =
      'metadata_intelligence.online_lookup_disclosure_accepted';

  final Future<SharedPreferences> Function() _preferencesLoader;

  bool _isLoaded = false;
  bool _onlineMetadataLookupEnabled = true;
  bool _coverArtSuggestionsEnabled = true;
  bool _onlineLookupAccepted = false;

  bool get isLoaded => _isLoaded;

  bool get onlineMetadataLookupEnabled => _onlineMetadataLookupEnabled;

  bool get coverArtSuggestionsEnabled => _coverArtSuggestionsEnabled;

  /// Whether the user has accepted the online lookup disclosure. Until they
  /// have, no lookup contacts MusicBrainz or the Cover Art Archive.
  @override
  bool get isOnlineLookupAccepted => _onlineLookupAccepted;

  @override
  Future<void> acceptOnlineLookup() async {
    if (_onlineLookupAccepted) {
      return;
    }

    _onlineLookupAccepted = true;
    notifyListeners();

    final preferences = await _preferencesLoader();
    await preferences.setBool(onlineLookupAcceptedKey, true);
  }

  bool get effectiveCoverArtSuggestionsEnabled =>
      _onlineMetadataLookupEnabled && _coverArtSuggestionsEnabled;

  Future<void> load() async {
    final preferences = await _preferencesLoader();

    _onlineMetadataLookupEnabled =
        preferences.getBool(onlineMetadataLookupKey) ?? true;

    _coverArtSuggestionsEnabled =
        preferences.getBool(coverArtSuggestionsKey) ?? true;

    _onlineLookupAccepted =
        preferences.getBool(onlineLookupAcceptedKey) ?? false;

    _isLoaded = true;
    notifyListeners();
  }

  Future<void> setOnlineMetadataLookupEnabled(bool enabled) async {
    if (_onlineMetadataLookupEnabled == enabled) {
      return;
    }

    _onlineMetadataLookupEnabled = enabled;
    notifyListeners();

    final preferences = await _preferencesLoader();
    await preferences.setBool(onlineMetadataLookupKey, enabled);
  }

  Future<void> setCoverArtSuggestionsEnabled(bool enabled) async {
    if (_coverArtSuggestionsEnabled == enabled) {
      return;
    }

    _coverArtSuggestionsEnabled = enabled;
    notifyListeners();

    final preferences = await _preferencesLoader();
    await preferences.setBool(coverArtSuggestionsKey, enabled);
  }
}
