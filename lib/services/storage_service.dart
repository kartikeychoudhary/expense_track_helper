import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static const _keyUrl = 'backendUrl';
  static const _keyEmail = 'email';
  static const _keyPassword = 'password';
  static const _keySenders = 'selectedSendersList';
  static const _keyAccessToken = 'accessToken';
  static const _keyLastSmsTimestamp = 'lastSmsTimestamp';
  static const _keySentSmsIds = 'sentSmsIds';

  Future<SharedPreferences> _getPrefs() async {
    return SharedPreferences.getInstance();
  }

  // Save configuration data
  Future<void> saveConfiguration({
    required String url,
    required String email,
    required String password,
    required List<String> selectedSenders,
  }) async {
    final prefs = await _getPrefs();
    await prefs.setString(_keyUrl, url);
    await prefs.setString(_keyEmail, email);
    await prefs.setString(_keyPassword, password);
    await prefs.setStringList(_keySenders, selectedSenders);
  }

  // Load configuration data
  Future<Map<String, dynamic>> loadConfiguration() async {
    final prefs = await _getPrefs();
    return {
      'url': prefs.getString(_keyUrl),
      'email': prefs.getString(_keyEmail),
      'password': prefs.getString(_keyPassword),
      'senders': prefs.getStringList(_keySenders),
    };
  }

  // Save access token
  Future<void> saveAccessToken(String token) async {
    final prefs = await _getPrefs();
    await prefs.setString(_keyAccessToken, token);
  }

  // Load access token
  Future<String?> loadAccessToken() async {
    final prefs = await _getPrefs();
    return prefs.getString(_keyAccessToken);
  }

  // Save last fetched SMS timestamp
  Future<void> saveLastSmsTimestamp(DateTime timestamp) async {
    final prefs = await _getPrefs();
    await prefs.setInt(_keyLastSmsTimestamp, timestamp.millisecondsSinceEpoch);
  }

  // Load last fetched SMS timestamp
  Future<DateTime?> loadLastSmsTimestamp() async {
    final prefs = await _getPrefs();
    final timestampMillis = prefs.getInt(_keyLastSmsTimestamp);
    return timestampMillis != null
        ? DateTime.fromMillisecondsSinceEpoch(timestampMillis)
        : null;
  }

  // Save the set of sent SMS IDs
  Future<void> saveSentSmsIds(Set<String> ids) async {
    final prefs = await _getPrefs();
    await prefs.setStringList(_keySentSmsIds, ids.toList());
  }

  // Load the set of sent SMS IDs
  Future<Set<String>> loadSentSmsIds() async {
    final prefs = await _getPrefs();
    final idList = prefs.getStringList(_keySentSmsIds);
    return idList?.toSet() ?? {};
  }

  // Add a single SMS ID to the sent set
  Future<void> addSentSmsId(String id) async {
    final currentIds = await loadSentSmsIds();
    currentIds.add(id);
    await saveSentSmsIds(currentIds);
  }

  // Clear specific keys (e.g., on logout or error)
  Future<void> clearAccessToken() async {
    final prefs = await _getPrefs();
    await prefs.remove(_keyAccessToken);
  }

  // Method to get individual config values if needed
  Future<String?> getUrl() async => (await _getPrefs()).getString(_keyUrl);
  Future<String?> getEmail() async => (await _getPrefs()).getString(_keyEmail);
  Future<String?> getPassword() async =>
      (await _getPrefs()).getString(_keyPassword);
  Future<List<String>?> getSelectedSenders() async =>
      (await _getPrefs()).getStringList(_keySenders);
}
