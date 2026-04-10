import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path_provider/path_provider.dart';
import 'package:app_links/app_links.dart';
import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

// Deep Link Service - Handles incoming app links for invite tokens
class DeepLinkService {
  static final DeepLinkService _instance = DeepLinkService._internal();
  factory DeepLinkService() => _instance;
  DeepLinkService._internal();

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;
  String? _pendingInviteToken;
  final StreamController<String> _inviteTokenController = StreamController<String>.broadcast();

  Stream<String> get inviteTokenStream => _inviteTokenController.stream;
  String? get pendingInviteToken => _pendingInviteToken;

  void clearPendingToken() {
    _pendingInviteToken = null;
  }

  Future<void> initialize() async {
    // Handle initial link (app opened via link)
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        debugPrint('📎 Initial deep link: $initialUri');
        _handleUri(initialUri);
      }
    } catch (e) {
      debugPrint('❌ Error getting initial link: $e');
    }

    // Listen for incoming links while app is running
    _linkSubscription = _appLinks.uriLinkStream.listen((Uri uri) {
      debugPrint('📎 Incoming deep link: $uri');
      _handleUri(uri);
    }, onError: (err) {
      debugPrint('❌ Error in link stream: $err');
    });
  }

  void _handleUri(Uri uri) {
    // Expected format: mbt://invite?token=XXXXX
    final token = uri.queryParameters['token'];
    if (token != null && token.isNotEmpty) {
      debugPrint('🔑 Extracted invite token: $token');
      _pendingInviteToken = token;
      _inviteTokenController.add(token);
    }
  }

  void dispose() {
    _linkSubscription?.cancel();
    _inviteTokenController.close();
  }
}

// Settings Manager - Central storage for all app settings
class SettingsManager {
  static final SettingsManager _instance = SettingsManager._internal();
  factory SettingsManager() => _instance;
  SettingsManager._internal();

  Map<String, dynamic> _settings = {
    'language': 'en',
    'ttsSpeed': 100.0,
    'favoriteFoods': '',
    'allergies': <String>[],
    'lastConnectedDeviceName': null,
    'lastConnectedDeviceAddress': null,
    'isLoggedIn': false,
    'username': null,
    'accessToken': null,
    'refreshToken': null,
    'firstName': null,
    'lastName': null,
    'email': null,
    'role': null, // 'user' or 'relative'
    'userId': null,
  };

  Future<File> _getSettingsFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/app_settings.json');
  }

  Future<void> loadSettings() async {
    try {
      final file = await _getSettingsFile();
      if (await file.exists()) {
        final contents = await file.readAsString();
        _settings = jsonDecode(contents);
        debugPrint('📖 Loaded settings: $_settings');
      } else {
        debugPrint('📄 No settings file found, using defaults');
      }
    } catch (e) {
      debugPrint('❌ Error loading settings: $e');
    }
  }

  Future<void> saveSettings() async {
    try {
      final file = await _getSettingsFile();
      await file.writeAsString(jsonEncode(_settings));
      debugPrint('✅ Saved settings: $_settings');
    } catch (e) {
      debugPrint('❌ Error saving settings: $e');
    }
  }

  String get language => _settings['language'] as String;
  set language(String value) {
    _settings['language'] = value;
    saveSettings();
  }

  double get ttsSpeed => _settings['ttsSpeed'] as double;
  set ttsSpeed(double value) {
    _settings['ttsSpeed'] = value;
    saveSettings();
  }

  String get favoriteFoods => _settings['favoriteFoods'] as String;
  set favoriteFoods(String value) {
    _settings['favoriteFoods'] = value;
    saveSettings();
  }

  List<String> get allergies => List<String>.from(_settings['allergies'] as List);
  set allergies(List<String> value) {
    _settings['allergies'] = value;
    saveSettings();
  }

  void toggleAllergy(String allergy, bool value) {
    final currentAllergies = allergies;
    if (value && !currentAllergies.contains(allergy)) {
      currentAllergies.add(allergy);
    } else if (!value) {
      currentAllergies.remove(allergy);
    }
    allergies = currentAllergies;
  }

  bool hasAllergy(String allergy) {
    return allergies.contains(allergy);
  }

  String? get lastConnectedDeviceName => _settings['lastConnectedDeviceName'] as String?;
  String? get lastConnectedDeviceAddress => _settings['lastConnectedDeviceAddress'] as String?;
  
  void setLastConnectedDevice(String? name, String? address) {
    _settings['lastConnectedDeviceName'] = name;
    _settings['lastConnectedDeviceAddress'] = address;
    saveSettings();
  }

  bool get isLoggedIn => _settings['isLoggedIn'] as bool? ?? false;
  String? get username => _settings['username'] as String?;
  String? get accessToken => _settings['accessToken'] as String?;
  String? get refreshToken => _settings['refreshToken'] as String?;
  String? get firstName => _settings['firstName'] as String?;
  String? get lastName => _settings['lastName'] as String?;
  String? get email => _settings['email'] as String?;
  String? get role => _settings['role'] as String?;
  
  bool get isRelative => role == 'relative';
  bool get isUser => role == 'user';

  void login(String username, {String? accessToken, String? refreshToken, String? firstName, String? lastName, String? email, String? role, String? userId}) {
    _settings['isLoggedIn'] = true;
    _settings['username'] = username;
    _settings['accessToken'] = accessToken;
    _settings['refreshToken'] = refreshToken;
    _settings['firstName'] = firstName;
    _settings['lastName'] = lastName;
    _settings['email'] = email;
    _settings['role'] = role;
    _settings['userId'] = userId;
    saveSettings();
  }

  void logout() {
    _settings['isLoggedIn'] = false;
    _settings['username'] = null;
    _settings['accessToken'] = null;
    _settings['refreshToken'] = null;
    _settings['firstName'] = null;
    _settings['lastName'] = null;
    _settings['email'] = null;
    _settings['role'] = null;
    _settings['userId'] = null;
    saveSettings();
  }

  String? get userId => _settings['userId'] as String?;

  void updateTokens({String? accessToken, String? refreshToken}) {
    if (accessToken != null) _settings['accessToken'] = accessToken;
    if (refreshToken != null) _settings['refreshToken'] = refreshToken;
    saveSettings();
  }

  Map<String, dynamic> getAllSettings() => Map.from(_settings);
}

// API Service - Handles all backend API calls
class ApiService {
  static const String baseUrl =
      'https://bdad-2a01-5a8-307-c9c-7c13-b42e-edb9-2980.ngrok-free.app/api';
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
  };

  Map<String, String> get _authHeaders => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer ${SettingsManager().accessToken}',
  };

  dynamic _tryDecodeJson(String responseBody) {
    if (responseBody.isEmpty) return {};
    try {
      return jsonDecode(responseBody);
    } catch (_) {
      return null;
    }
  }

  String _extractErrorMessage(http.Response response, dynamic body) {
    if (body is Map<String, dynamic>) {
      final message = body['message'] ?? body['error'] ?? body['detail'];
      if (message is List) return message.join(', ');
      if (message != null) return message.toString();
    }

    if (body is List && body.isNotEmpty) {
      return body.join(', ');
    }

    final rawBody = response.body.trim();
    final lowered = rawBody.toLowerCase();
    if (rawBody.contains('ERR_NGROK_3200') ||
        (lowered.contains('ngrok') && lowered.contains('offline'))) {
      return 'Backend tunnel is offline. Start ngrok again and update the app base URL if it changed.';
    }

    if (rawBody.isNotEmpty) {
      return rawBody.split('\n').first.trim();
    }

    return 'An error occurred';
  }

  Future<Map<String, dynamic>> _handleResponse(http.Response response) async {
    debugPrint('📡 API Response [${response.statusCode}]: ${response.body}');
    
    if (response.statusCode == 401) {
      // Try to refresh token
      final refreshed = await refreshTokens();
      if (!refreshed) {
        throw ApiException('Session expired. Please login again.', 401);
      }
      throw ApiException('Token refreshed, please retry.', 401, shouldRetry: true);
    }

    final body = _tryDecodeJson(response.body);
    
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return body is Map<String, dynamic> ? body : {'data': body};
    }
    
    final message = _extractErrorMessage(response, body);
    throw ApiException(message, response.statusCode);
  }

  // Auth endpoints
  Future<Map<String, dynamic>> register({
    required String firstName,
    required String lastName,
    required String email,
    required String password,
  }) async {
    debugPrint('📤 Registering user: $email');
    final response = await http.post(
      Uri.parse('$baseUrl/auth/register'),
      headers: _headers,
      body: jsonEncode({
        'firstName': firstName,
        'lastName': lastName,
        'email': email,
        'password': password,
      }),
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    debugPrint('📤 Logging in: $email');
    final response = await http.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: _headers,
      body: jsonEncode({
        'email': email,
        'password': password,
      }),
    );
    return _handleResponse(response);
  }

  Future<bool> refreshTokens() async {
    final refreshToken = SettingsManager().refreshToken;
    if (refreshToken == null) return false;

    try {
      debugPrint('🔄 Refreshing tokens...');
      final response = await http.post(
        Uri.parse('$baseUrl/auth/refresh'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $refreshToken',
        },
      );

      if (response.statusCode == 200) {
        final body = _tryDecodeJson(response.body);
        if (body is! Map<String, dynamic>) {
          debugPrint('❌ Invalid refresh token response format');
          return false;
        }
        SettingsManager().updateTokens(
          accessToken: body['accessToken'],
          refreshToken: body['refreshToken'],
        );
        debugPrint('✅ Tokens refreshed successfully');
        return true;
      }
    } catch (e) {
      debugPrint('❌ Failed to refresh tokens: $e');
    }
    return false;
  }

  // User endpoints
  Future<Map<String, dynamic>> getMe() async {
    debugPrint('📤 Getting current user profile');
    final response = await http.get(
      Uri.parse('$baseUrl/users/me'),
      headers: _authHeaders,
    );
    return _handleResponse(response);
  }

  Future<List<dynamic>> getMyRelatives() async {
    debugPrint('📤 Getting my relatives');
    final response = await http.get(
      Uri.parse('$baseUrl/users/my-relatives'),
      headers: _authHeaders,
    );
    final result = await _handleResponse(response);
    return result['data'] ?? result['relatives'] ?? [];
  }

  // Relatives endpoints (for relatives to manage blind users)
  Future<Map<String, dynamic>> createBlindUser({
    required String firstName,
    required String lastName,
    required String email,
    required String password,
  }) async {
    debugPrint('📤 Creating blind user: $email');
    final response = await http.post(
      Uri.parse('$baseUrl/relatives'),
      headers: _authHeaders,
      body: jsonEncode({
        'firstName': firstName,
        'lastName': lastName,
        'email': email,
        'password': password,
      }),
    );
    return _handleResponse(response);
  }

  Future<void> sendInvite({required String email}) async {
    debugPrint('📤 Sending invite to: $email');
    final response = await http.post(
      Uri.parse('$baseUrl/relatives/invite'),
      headers: _authHeaders,
      body: jsonEncode({'email': email}),
    );
    await _handleResponse(response);
  }

  Future<void> acceptInvite({required String token}) async {
    debugPrint('📤 Accepting invite with token');
    final response = await http.post(
      Uri.parse('$baseUrl/relatives/accept-invite'),
      headers: _authHeaders,
      body: jsonEncode({'token': token}),
    );
    await _handleResponse(response);
  }

  Future<void> removeRelativeLink({required String id}) async {
    debugPrint('📤 Removing relative link: $id');
    final response = await http.delete(
      Uri.parse('$baseUrl/relatives/$id'),
      headers: _authHeaders,
    );
    await _handleResponse(response);
  }

  // Food endpoints - Preferred Foods
  Future<List<dynamic>> getPreferredFoods() async {
    debugPrint('📤 Getting preferred foods');
    final response = await http.get(
      Uri.parse('$baseUrl/food/preferred'),
      headers: _authHeaders,
    );
    final result = await _handleResponse(response);
    return result['data'] ?? result['foods'] ?? [];
  }

  Future<Map<String, dynamic>> addPreferredFood({required String name}) async {
    debugPrint('📤 Adding preferred food: $name');
    final response = await http.post(
      Uri.parse('$baseUrl/food/preferred'),
      headers: _authHeaders,
      body: jsonEncode({'name': name}),
    );
    return _handleResponse(response);
  }

  Future<void> deletePreferredFood({required String id}) async {
    debugPrint('📤 Deleting preferred food: $id');
    final response = await http.delete(
      Uri.parse('$baseUrl/food/preferred/$id'),
      headers: _authHeaders,
    );
    await _handleResponse(response);
  }

  // Food endpoints - Allergies
  Future<List<dynamic>> getAllergies() async {
    debugPrint('📤 Getting allergies');
    final response = await http.get(
      Uri.parse('$baseUrl/food/allergies'),
      headers: _authHeaders,
    );
    final result = await _handleResponse(response);
    return result['data'] ?? result['allergies'] ?? [];
  }

  Future<Map<String, dynamic>> addAllergy({required String name}) async {
    debugPrint('📤 Adding allergy: $name');
    final response = await http.post(
      Uri.parse('$baseUrl/food/allergies'),
      headers: _authHeaders,
      body: jsonEncode({'name': name}),
    );
    return _handleResponse(response);
  }

  Future<void> deleteAllergy({required String id}) async {
    debugPrint('📤 Deleting allergy: $id');
    final response = await http.delete(
      Uri.parse('$baseUrl/food/allergies/$id'),
      headers: _authHeaders,
    );
    await _handleResponse(response);
  }
}

class ApiException implements Exception {
  final String message;
  final int statusCode;
  final bool shouldRetry;

  ApiException(this.message, this.statusCode, {this.shouldRetry = false});

  @override
  String toString() => message;
}

// Simple localization class
class AppLocalizations {
  final Locale locale;
  AppLocalizations(this.locale);

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

  static final Map<String, Map<String, String>> _localizedValues = {
    'en': {
      'appTitle': 'MyBaT',
      'connect': 'Connection',
      'foodPreferences': 'Food Preferences',
      'settings': 'Settings',
      'scanning': 'Scanning...',
      'refreshBondedDevices': 'Refresh Bonded Devices',
      'creatingRFCOMM': 'Creating RFCOMM Link...',
      'status': 'Status',
      'bondedDevices': 'Bonded Devices:',
      'unknown': 'Unknown',
      'setup': 'Setup',
      'wifiSSID': 'WiFi SSID',
      'enterSSID': 'Enter WiFi network name',
      'wifiPassword': 'WiFi Password',
      'enterWifiPassword': 'Enter WiFi password',
      'configuring': 'Configuring...',
      'configureWiFi': 'Configure WiFi',
      'piResponse': 'Pi Response:',
      'favoriteFoods': 'Favorite Foods',
      'enterFavoriteFoods': 'Enter your favorite foods...',
      'allergiesIntolerances': 'Allergies & Intolerances',
      'selectAllergies': 'Select any allergies or intolerances you have:',
      'dairy': 'Dairy',
      'eggs': 'Eggs',
      'peanuts': 'Peanuts',
      'treeNuts': 'Tree Nuts',
      'soy': 'Soy',
      'wheatGluten': 'Wheat/Gluten',
      'fish': 'Fish',
      'shellfish': 'Shellfish',
      'sesame': 'Sesame',
      'lactose': 'Lactose',
      'language': 'Language',
      'english': 'English',
      'bulgarian': 'Bulgarian',
      'ttsSpeed': 'TTS Speed',
      'connected': 'Connected',
      'disconnect': 'Disconnect',
      'wifiSetup': 'WiFi Setup',
      'internetStatusUnknown': 'Pi internet status unknown',
      'piConnectedToInternet': 'Pi is connected to internet',
      'piNotConnectedToInternet': 'Pi is not connected to internet',
      'welcome': 'Welcome to MyBaT',
      'loginTitle': 'Login',
      'registerTitle': 'Register as Relative',
      'username': 'Username',
      'password': 'Password',
      'email': 'Email',
      'firstName': 'First Name',
      'lastName': 'Last Name',
      'enterUsername': 'Enter your username',
      'enterPassword': 'Enter your password',
      'enterEmail': 'Enter your email',
      'enterFirstName': 'Enter first name',
      'enterLastName': 'Enter last name',
      'login': 'Login',
      'register': 'Register',
      'registerAsRelative': 'Register as Relative',
      'dontHaveAccount': "Don't have an account?",
      'alreadyHaveAccount': 'Already have an account?',
      'loginHere': 'Login here',
      'registerHere': 'Register here',
      'usernameRequired': 'Username is required',
      'passwordRequired': 'Password is required',
      'emailRequired': 'Email is required',
      'firstNameRequired': 'First name is required',
      'lastNameRequired': 'Last name is required',
      'tempBypass': 'Temporary Bypass (Dev)',
      'createUser': 'Create User Account',
      'inviteExistingUser': 'Invite Existing User',
      'manageUsers': 'Manage Users',
      'createNewUser': 'Create New User',
      'userCreated': 'User account created successfully',
      'inviteSent': 'Invitation sent successfully',
      'createUserFor': 'Create account for blind user',
      'inviteUserFor': 'Invite existing user',
      'networkError': 'Network error. Please check your connection.',
      'blindUserCreated': 'Blind user created and linked successfully',
      'inviteAlreadySent': 'Invitation sent to existing user',
      'userNotFound': 'User not found with this email',
      'myRelatives': 'My Relatives',
      'acceptInvite': 'Accept Invitation',
      'acceptInviteDescription': 'Enter the invitation token you received via email to link with a relative.',
      'inviteToken': 'Invitation Token',
      'enterInviteToken': 'Paste the token from email',
      'acceptInviteButton': 'Accept Invitation',
      'inviteAccepted': 'Invitation accepted successfully',
      'inviteExpired': 'This invitation has expired',
      'inviteNotFound': 'Invalid invitation token',
      'tokenRequired': 'Token is required',
      'linkedRelatives': 'Linked Relatives',
      'noRelativesYet': 'No relatives linked yet. Accept an invitation to get started.',
      'loginToAcceptInvite': 'Please log in to accept the invitation',
      'scanFoodLabel': 'Scan Food Label',
      'scanResult': 'Scan Result',
      'safe': 'SAFE',
      'unsafe': 'UNSAFE',
      'allergenDetected': 'Allergens detected',
      'preferredItemFound': 'Contains preferred items',
      'scanFailed': 'Scan failed',
      'detectedText': 'Detected text',
      'typeFoodName': 'Type a food name and press Add...',
      'typeAllergyName': 'Type an allergy and press Add...',
      'add': 'Add',
      'noFoodsAdded': 'No preferred foods added yet.',
      'noAllergiesAdded': 'No allergies added yet.',
      'errorLoading': 'Error loading data. Tap to retry.',
      'sosSending': 'Sending SOS alert...',
      'sosSent': 'SOS alert sent! Your location has been shared with your relatives.',
      'sosFailed': 'Failed to send SOS',
      'sosLocationPermissionDenied': 'Location permission is required to send SOS.',
    },
    'bg': {
      'appTitle': 'MyBaT',
      'connect': 'Връзка',
      'foodPreferences': 'Хранителни Предпочитания',
      'settings': 'Настройки',
      'scanning': 'Сканиране...',
      'refreshBondedDevices': 'Обнови Сдвоени Устройства',
      'creatingRFCOMM': 'Създаване на RFCOMM Връзка...',
      'status': 'Състояние',
      'bondedDevices': 'Сдвоени Устройства:',
      'unknown': 'Неизвестно',
      'setup': 'Настройка',
      'wifiSSID': 'WiFi SSID',
      'enterSSID': 'Въведете име на WiFi мрежа',
      'wifiPassword': 'WiFi Парола',
      'enterWifiPassword': 'Въведете WiFi парола',
      'configuring': 'Конфигуриране...',
      'configureWiFi': 'Конфигурирай WiFi',
      'piResponse': 'Отговор от Pi:',
      'favoriteFoods': 'Любими Храни',
      'enterFavoriteFoods': 'Въведете вашите любими храни...',
      'allergiesIntolerances': 'Алергии и Непоносимости',
      'selectAllergies': 'Изберете алергии или непоносимости:',
      'dairy': 'Млечни Продукти',
      'eggs': 'Яйца',
      'peanuts': 'Фъстъци',
      'treeNuts': 'Ядки',
      'soy': 'Соя',
      'wheatGluten': 'Пшеница/Глутен',
      'fish': 'Риба',
      'shellfish': 'Миди',
      'sesame': 'Сусам',
      'lactose': 'Лактоза',
      'language': 'Език',
      'english': 'Английски',
      'bulgarian': 'Български',
      'ttsSpeed': 'Скорост на Глас',
      'connected': 'Свързано',
      'disconnect': 'Прекъсни',
      'wifiSetup': 'WiFi Настройка',
      'internetStatusUnknown': 'Интернет статусът на Pi е неизвестен',
      'piConnectedToInternet': 'Pi е свързано с интернет',
      'piNotConnectedToInternet': 'Pi не е свързано с интернет',
      'welcome': 'Добре дошли в MyBaT',
      'loginTitle': 'Вход',
      'registerTitle': 'Регистрация като Роднина',
      'username': 'Потребителско име',
      'password': 'Парола',
      'email': 'Имейл',
      'firstName': 'Име',
      'lastName': 'Фамилия',
      'enterUsername': 'Въведете потребителско име',
      'enterPassword': 'Въведете парола',
      'enterEmail': 'Въведете имейл',
      'enterFirstName': 'Въведете име',
      'enterLastName': 'Въведете фамилия',
      'login': 'Вход',
      'register': 'Регистрация',
      'registerAsRelative': 'Регистрация като Роднина',
      'dontHaveAccount': 'Нямате акаунт?',
      'alreadyHaveAccount': 'Вече имате акаунт?',
      'loginHere': 'Влезте тук',
      'registerHere': 'Регистрирайте се тук',
      'usernameRequired': 'Потребителското име е задължително',
      'passwordRequired': 'Паролата е задължителна',
      'emailRequired': 'Имейлът е задължителен',
      'firstNameRequired': 'Името е задължително',
      'lastNameRequired': 'Фамилията е задължителна',
      'tempBypass': 'Временен Заобикаляне (Dev)',
      'createUser': 'Създай Потребител',
      'inviteExistingUser': 'Покани Съществуващ Потребител',
      'manageUsers': 'Управление на Потребители',
      'createNewUser': 'Създай Нов Потребител',
      'userCreated': 'Потребителят е създаден успешно',
      'inviteSent': 'Поканата е изпратена успешно',
      'createUserFor': 'Създай акаунт за незрящ потребител',
      'inviteUserFor': 'Покани съществуващ потребител',
      'networkError': 'Мрежова грешка. Проверете връзката си.',
      'blindUserCreated': 'Незрящият потребител е създаден и свързан успешно',
      'inviteAlreadySent': 'Поканата е изпратена до съществуващ потребител',
      'userNotFound': 'Потребител с този имейл не е намерен',
      'myRelatives': 'Моите Близки',
      'acceptInvite': 'Приеми Покана',
      'acceptInviteDescription': 'Въведете токена от поканата, която получихте по имейл, за да се свържете с близък.',
      'inviteToken': 'Токен за Покана',
      'enterInviteToken': 'Поставете токена от имейла',
      'acceptInviteButton': 'Приеми Покана',
      'inviteAccepted': 'Поканата е приета успешно',
      'inviteExpired': 'Тази покана е изтекла',
      'inviteNotFound': 'Невалиден токен за покана',
      'tokenRequired': 'Токенът е задължителен',
      'linkedRelatives': 'Свързани Близки',
      'noRelativesYet': 'Все още няма свързани близки. Приемете покана, за да започнете.',
      'loginToAcceptInvite': 'Моля, влезте в профила си, за да приемете поканата',
      'scanFoodLabel': 'Сканирай Етикет',
      'scanResult': 'Резултат от Сканиране',
      'safe': 'БЕЗОПАСНО',
      'unsafe': 'ОПАСНО',
      'allergenDetected': 'Открити алергени',
      'preferredItemFound': 'Съдържа предпочитани храни',
      'scanFailed': 'Грешка при сканиране',
      'detectedText': 'Разпознат текст',
      'typeFoodName': 'Въведете храна и натиснете Добави...',
      'typeAllergyName': 'Въведете алергия и натиснете Добави...',
      'add': 'Добави',
      'noFoodsAdded': 'Все още няма добавени любими храни.',
      'noAllergiesAdded': 'Все още няма добавени алергии.',
      'errorLoading': 'Грешка при зареждане. Натиснете за повторен опит.',
      'sosSending': 'Изпращане на SOS сигнал...',
      'sosSent': 'SOS сигналът е изпратен! Вашето местоположение беше споделено с близките ви.',
      'sosFailed': 'Неуспешно изпращане на SOS',
      'sosLocationPermissionDenied': 'Необходимо е разрешение за местоположение за изпращане на SOS.',
    },
  };

  String translate(String key) {
    return _localizedValues[locale.languageCode]?[key] ?? key;
  }
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => ['en', 'bg'].contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) async {
    return AppLocalizations(locale);
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SettingsManager().loadSettings();
  await DeepLinkService().initialize();
  
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('FLUTTER ERROR: ${details.exception}');
  };
  runApp(const MyApp());
}

// Global navigator key for navigating from anywhere
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  
  static void setLocale(BuildContext context, Locale newLocale) {
    _MyAppState? state = context.findAncestorStateOfType<_MyAppState>();
    state?.setLocale(newLocale);
  }

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late Locale _locale;
  StreamSubscription<String>? _inviteSubscription;

  @override
  void initState() {
    super.initState();
    _locale = Locale(SettingsManager().language);
    
    // Listen for incoming invite tokens
    _inviteSubscription = DeepLinkService().inviteTokenStream.listen(_handleInviteToken);
    
    // Check if there's a pending token from initial launch
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final pendingToken = DeepLinkService().pendingInviteToken;
      if (pendingToken != null) {
        _handleInviteToken(pendingToken);
      }
    });
  }

  @override
  void dispose() {
    _inviteSubscription?.cancel();
    super.dispose();
  }

  void _handleInviteToken(String token) {
    final isLoggedIn = SettingsManager().isLoggedIn;
    debugPrint('🔔 Handling invite token. Logged in: $isLoggedIn');
    
    if (isLoggedIn) {
      // User is logged in, navigate to accept invite and auto-process
      _navigateToAcceptInvite(token);
    } else {
      // User is not logged in, go to login page with pending token
      _navigateToLoginWithPendingInvite(token);
    }
  }

  void _navigateToAcceptInvite(String token) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (context) => MainScreen(
            initialTab: 2, // My Relatives / Accept Invite tab
            pendingInviteToken: token,
          ),
        ),
        (route) => false,
      );
    });
  }

  void _navigateToLoginWithPendingInvite(String token) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (context) => LoginPage(pendingInviteToken: token),
        ),
        (route) => false,
      );
    });
  }

  void setLocale(Locale locale) {
    setState(() {
      _locale = locale;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isLoggedIn = SettingsManager().isLoggedIn;
    
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'MyBaT',
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      locale: _locale,
      supportedLocales: const [
        Locale('en', ''),
        Locale('bg', ''),
      ],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: isLoggedIn ? const MainScreen() : const LoginPage(),
    );
  }
}

class MainScreen extends StatefulWidget {
  final int initialTab;
  final String? pendingInviteToken;
  
  const MainScreen({super.key, this.initialTab = 0, this.pendingInviteToken});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  late int _selectedIndex;
  
  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialTab;
  }
  
  List<Widget> _getPages() {
    final isRelative = SettingsManager().isRelative;
    if (isRelative) {
      return [
        const BluetoothConnectionPage(),
        const ManageUsersPage(),
        const EmptyPage(),
      ];
    } else {
      return [
        const BluetoothConnectionPage(),
        const TextBoxPage(),
        AcceptInvitePage(pendingToken: widget.pendingInviteToken),
        const EmptyPage(),
      ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final isRelative = SettingsManager().isRelative;
    final pages = _getPages();

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 0,
        elevation: 0,
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (i) => setState(() => _selectedIndex = i),
        type: BottomNavigationBarType.fixed,
        items: isRelative
          ? [
              BottomNavigationBarItem(icon: const Icon(Icons.wifi), label: localizations.translate('connect')),
              BottomNavigationBarItem(icon: const Icon(Icons.people), label: localizations.translate('manageUsers')),
              BottomNavigationBarItem(icon: const Icon(Icons.settings), label: localizations.translate('settings')),
            ]
          : [
              BottomNavigationBarItem(icon: const Icon(Icons.wifi), label: localizations.translate('connect')),
              BottomNavigationBarItem(icon: const Icon(Icons.local_dining), label: localizations.translate('foodPreferences')),
              BottomNavigationBarItem(icon: const Icon(Icons.family_restroom), label: localizations.translate('myRelatives')),
              BottomNavigationBarItem(icon: const Icon(Icons.settings), label: localizations.translate('settings')),
            ],
      ),
    );
  }
}

class BluetoothConnectionPage extends StatefulWidget {
  const BluetoothConnectionPage({super.key});
  @override
  State<BluetoothConnectionPage> createState() => _BluetoothConnectionPageState();
}

class _BluetoothConnectionPageState extends State<BluetoothConnectionPage> {
  List<BluetoothDevice> _devicesList = [];
  bool _isScanning = false;
  bool _isConnecting = false;
  BluetoothConnection? _connection;
  Stream<Uint8List>? _broadcastInputStream;
  BluetoothDevice? _connectedDevice;
  String? _lastError;
  bool? _piHasInternet;
  bool _checkingInternet = false;
  Timer? _internetCheckTimer;
  String? _piIpAddress;
  StreamSubscription? _bluetoothSubscription;


  String _compactError(Object error) {
    final raw = error.toString();
    final firstLine = raw.split('\n').first;
    if (firstLine.length <= 140) return firstLine;
    return '${firstLine.substring(0, 140)}...';
  }

  Future<bool> _refreshBond(BluetoothDevice device) async {
    final serial = FlutterBluetoothSerial.instance;
    try {
      debugPrint('Attempting bond refresh for ${device.address}');
      await serial.removeDeviceBondWithAddress(device.address);
      await Future.delayed(const Duration(milliseconds: 1500));
      final bonded = await serial.bondDeviceAtAddress(device.address);
      debugPrint('Bond refresh result for ${device.address}: $bonded');
      
      if (bonded == true) {
        debugPrint('Waiting for bond to stabilize...');
        await Future.delayed(const Duration(milliseconds: 2000));
      }
      
      return bonded == true;
    } catch (e) {
      debugPrint('Bond refresh failed: $e');
      return false;
    }
  }

  Future<BluetoothConnection> _connectSocket(String address) {
    return BluetoothConnection.toAddress(address)
        .timeout(const Duration(seconds: 20));
  }

  @override
  void initState() {
    super.initState();
    _initBluetooth();
    _startInternetCheck();
    _restoreConnectionState();
  }

  @override
  void dispose() {
    _internetCheckTimer?.cancel();
    _bluetoothSubscription?.cancel();
    _connection?.finish();
    super.dispose();
  }

  Future<void> _restoreConnectionState() async {
    final settings = SettingsManager();
    final deviceAddress = settings.lastConnectedDeviceAddress;
    final deviceName = settings.lastConnectedDeviceName;
    
    if (deviceAddress != null && deviceName != null) {
      debugPrint('Attempting to restore connection to $deviceName ($deviceAddress)');
      
      // Try to reconnect automatically
      try {
        final connection = await _connectSocket(deviceAddress);
        if (mounted) {
          _broadcastInputStream = connection.input?.asBroadcastStream();
          setState(() {
            _connection = connection;
            _connectedDevice = BluetoothDevice(
              name: deviceName,
              address: deviceAddress,
            );
          });
          debugPrint('✅ Restored connection to $deviceName');
        }
      } catch (e) {
        debugPrint('⚠️ Could not restore connection to $deviceName: $e');
        // Clear saved device if we can't reconnect
        settings.setLastConnectedDevice(null, null);
      }
    }
  }

  void _startInternetCheck() {
    // Check immediately
    _checkPiInternetStatus();
    // Then check periodically every 10 seconds
    _internetCheckTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _checkPiInternetStatus();
    });
  }

  Future<void> _checkPiInternetStatus() async {
    if (_checkingInternet) return;
    
    setState(() => _checkingInternet = true);
    
    try {
      // Try to reach the Pi's HTTP status server
      // The Pi runs a simple HTTP server on port 8888 for internet status checks
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 3);
      
      // Build list of addresses to try
      final addresses = <String>[];
      
      // Try the Pi's IP address first if we have it
      if (_piIpAddress != null) {
        addresses.add(_piIpAddress!);
      }
      
      // Then try mDNS hostname
      addresses.add('raspberrypi.local');
      
      for (final addr in addresses) {
        try {
          final request = await client.getUrl(Uri.parse('http://$addr:8888/internet_status'));
          final response = await request.close().timeout(const Duration(seconds: 3));
          final body = await response.transform(utf8.decoder).join();
          
          if (mounted) {
            setState(() {
              _piHasInternet = body.contains('connected');
              _checkingInternet = false;
            });
          }
          client.close();
          return;
        } catch (e) {
          debugPrint('Failed to connect to $addr: $e');
          // Try next address
        }
      }
      
      // If we couldn't reach the Pi's HTTP server, status unknown
      if (mounted) {
        setState(() {
          _piHasInternet = null;
          _checkingInternet = false;
        });
      }
      client.close();
    } catch (e) {
      debugPrint('Internet check error: $e');
      if (mounted) {
        setState(() {
          _piHasInternet = null;
          _checkingInternet = false;
        });
      }
    }
  }

  Future<void> _initBluetooth() async {
    if (!Platform.isAndroid) return;
    try {
      await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.location,
        Permission.bluetooth,
      ].request();
    } catch (e) {
      debugPrint('Permission error: $e');
    }
  }

  Future<void> _scanForDevices() async {
    setState(() { _isScanning = true; _devicesList = []; _lastError = null; });
    try {
      await FlutterBluetoothSerial.instance.cancelDiscovery();
      final results = await FlutterBluetoothSerial.instance.getBondedDevices();
      setState(() { _devicesList = results; });
    } catch (e) {
      setState(() => _lastError = e.toString());
    } finally {
      setState(() => _isScanning = false);
    }
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    if (_isConnecting) return;

    setState(() {
      _isConnecting = true;
      _lastError = null;
    });

    debugPrint('--- Attempting Connection to ${device.name} (${device.address}) ---');

    try {
      final serial = FlutterBluetoothSerial.instance;
      await serial.cancelDiscovery();
      await Future.delayed(const Duration(milliseconds: 2500));

      if (_connection != null) {
        try { await _connection!.finish(); } catch (_) {}
        _connection = null;
      }

      BluetoothConnection connection;
      try {
        connection = await _connectSocket(device.address);
      } catch (firstError) {
        final msg = firstError.toString().toLowerCase();
        if (msg.contains('read failed') || msg.contains('timeout')) {
          final refreshed = await _refreshBond(device);
          if (!refreshed) rethrow;
          connection = await _connectSocket(device.address);
        } else {
          rethrow;
        }
      }

      if (mounted) {
        _broadcastInputStream = connection.input?.asBroadcastStream();
        setState(() {
          _connection = connection;
          _connectedDevice = device;
          _isConnecting = false;
        });
        
        // Save the connected device to settings
        SettingsManager().setLastConnectedDevice(device.name, device.address);
        debugPrint('✅ Saved connection state for ${device.name}');
        
        // Request IP address from Pi and listen for response
        _listenForPiMessages();
        _requestPiIpAddress();
        _sendPreferencesToPi();

        // Stay on the Bluetooth page - user can tap WiFi Setup button to open WiFi page
      }
    } catch (e) {
      debugPrint('CONNECTION ATTEMPT FAILED: $e');
      if (mounted) {
        setState(() {
          _isConnecting = false;
          final errorMsg = e.toString();
          if (errorMsg.contains('read failed') || errorMsg.contains('timeout')) {
            _lastError = 'Cannot connect to ${device.name}. Ensure Pi server is running.';
          } else {
            _lastError = 'Connection failed: ${_compactError(e)}';
          }
        });
      }
    }
  }

  Future<void> _disconnectDevice() async {
    if (_connection != null) {
      try {
        await _connection!.finish();
      } catch (_) {}
    }
    
    // Clear saved connection state
    SettingsManager().setLastConnectedDevice(null, null);
    debugPrint('🔌 Cleared connection state');
    
    setState(() {
      _connection = null;
      _connectedDevice = null;
      _piIpAddress = null;
    });
  }

  void _listenForPiMessages() {
    _bluetoothSubscription?.cancel();
    _bluetoothSubscription = _broadcastInputStream?.listen(
      (data) {
        final message = String.fromCharCodes(data).trim();
        debugPrint('Received from Pi: $message');

        // Check if this is an IP address response
        if (message.startsWith('IP:')) {
          final ip = message.substring(3);
          if (ip != 'unknown' && ip.isNotEmpty) {
            setState(() {
              _piIpAddress = ip;
            });
            debugPrint('✅ Got Pi IP address: $ip');
            _checkPiInternetStatus();
          }
          return;
        }

        if (message == 'SCANNING') {
          debugPrint('[BT] Pi is scanning...');
          return;
        }

        if (message.startsWith('SCAN_RESULT:')) {
          final jsonStr = message.substring('SCAN_RESULT:'.length);
          try {
            final result = jsonDecode(jsonStr) as Map<String, dynamic>;
            if (mounted) _showScanResult(result);
          } catch (e) {
            debugPrint('[BT] Failed to parse SCAN_RESULT: $e');
          }
          return;
        }
      },
      onDone: () {
        debugPrint('Bluetooth connection closed');
        if (mounted) _disconnectDevice();
      },
    );
  }

  Future<void> _requestPiIpAddress() async {
    if (_connection == null) return;
    
    try {
      _connection!.output.add(Uint8List.fromList('GET_IP\n'.codeUnits));
      await _connection!.output.allSent;
      debugPrint('📡 Requested IP address from Pi');
    } catch (e) {
      debugPrint('Failed to request IP: $e');
    }
  }

  /// Fetch preferences from the backend and push them to the Pi via BT.
  Future<void> _sendPreferencesToPi() async {
    if (_connection == null) return;
    try {
      final preferred = await ApiService().getPreferredFoods();
      final allergies = await ApiService().getAllergies();
      final prefs = {
        'preferred': preferred
            .map((f) => (f['name'] ?? '').toString())
            .where((s) => s.isNotEmpty)
            .toList(),
        'allergies': allergies
            .map((a) => (a['name'] ?? '').toString())
            .where((s) => s.isNotEmpty)
            .toList(),
      };
      final payload = 'PREFS:${jsonEncode(prefs)}\n';
      _connection!.output.add(Uint8List.fromList(payload.codeUnits));
      await _connection!.output.allSent;
      debugPrint('📤 Sent preferences to Pi — '
          '${prefs['preferred']!.length} preferred, '
          '${prefs['allergies']!.length} allergies');
    } catch (e) {
      debugPrint('⚠️ Could not send preferences to Pi: $e');
    }
  }

  /// Show OCR scan result in a bottom sheet.
  void _showScanResult(Map<String, dynamic> result) {
    if (!mounted) return;
    final loc = AppLocalizations.of(context);
    final safe = result['safe'] as bool?;
    final allergens = List<String>.from(result['allergens_found'] ?? []);
    final preferred = List<String>.from(result['preferred_found'] ?? []);
    final summary = (result['summary'] as String? ?? '').replaceAll('|', '\n');
    final rawText = result['raw_text'] as String? ?? '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 24, right: 24, top: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              safe == null
                  ? Icons.help_outline
                  : safe
                      ? Icons.check_circle_rounded
                      : Icons.warning_amber_rounded,
              size: 72,
              color: safe == null
                  ? Colors.grey
                  : safe
                      ? Colors.green
                      : Colors.red,
            ),
            const SizedBox(height: 8),
            Text(
              safe == null
                  ? '—'
                  : safe
                      ? loc.translate('safe')
                      : loc.translate('unsafe'),
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: safe == null
                    ? Colors.grey
                    : safe
                        ? Colors.green
                        : Colors.red,
              ),
            ),
            const SizedBox(height: 16),
            Text(summary,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, height: 1.5)),
            if (allergens.isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(children: [
                  const Icon(Icons.warning_rounded, color: Colors.red),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${loc.translate("allergenDetected")}: ${allergens.join(", ")}',
                      style: const TextStyle(
                          color: Colors.red, fontWeight: FontWeight.w600),
                    ),
                  ),
                ]),
              ),
            ],
            if (preferred.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(children: [
                  const Icon(Icons.star_rounded, color: Colors.green),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${loc.translate("preferredItemFound")}: ${preferred.join(", ")}',
                      style: const TextStyle(
                          color: Colors.green, fontWeight: FontWeight.w600),
                    ),
                  ),
                ]),
              ),
            ],
            if (rawText.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                '${loc.translate("detectedText")}: $rawText',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openWiFiSetup() {
    if (_connection != null && _connectedDevice != null && _broadcastInputStream != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => WiFiSetupPage(
            connection: _connection!,
            inputStream: _broadcastInputStream!,
            device: _connectedDevice!,
          ),
        ),
      );
    }
  }

  Widget _buildInternetStatusIcon() {
    if (_checkingInternet) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    
    if (_piHasInternet == null) {
      return const Icon(Icons.wifi_off, color: Colors.grey, size: 24);
    }
    
    return Icon(
      _piHasInternet! ? Icons.wifi : Icons.wifi_off,
      color: _piHasInternet! ? Colors.green : Colors.red,
      size: 24,
    );
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final isConnected = _connection != null && _connectedDevice != null;
    
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Connected device section with WiFi setup button
          if (isConnected) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.bluetooth_connected, color: Colors.green, size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              localizations.translate('connected'),
                              style: const TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                            Text(
                              _connectedDevice!.name ?? localizations.translate('unknown'),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: _disconnectDevice,
                        icon: const Icon(Icons.close, color: Colors.red),
                        tooltip: localizations.translate('disconnect'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // WiFi Setup button with internet status indicator
                  ElevatedButton(
                    onPressed: _openWiFiSetup,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
                      minimumSize: const Size(double.infinity, 50),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildInternetStatusIcon(),
                        const SizedBox(width: 12),
                        Text(
                          localizations.translate('wifiSetup'),
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.arrow_forward_ios, size: 16),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: _checkPiInternetStatus,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _piHasInternet == null 
                            ? localizations.translate('internetStatusUnknown')
                            : _piHasInternet! 
                              ? localizations.translate('piConnectedToInternet')
                              : localizations.translate('piNotConnectedToInternet'),
                          style: TextStyle(
                            color: _piHasInternet == null 
                              ? Colors.grey[600]
                              : _piHasInternet! 
                                ? Colors.green[700]
                                : Colors.red[700],
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.refresh,
                          size: 14,
                          color: _piHasInternet == null 
                            ? Colors.grey[600]
                            : _piHasInternet! 
                              ? Colors.green[700]
                              : Colors.red[700],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
          
          ElevatedButton.icon(
            onPressed: _isScanning || _isConnecting ? null : _scanForDevices,
            icon: const Icon(Icons.bluetooth_searching),
            label: Text(_isScanning ? localizations.translate('scanning') : localizations.translate('refreshBondedDevices')),
          ),
          const SizedBox(height: 10),
          if (_isConnecting) 
             Row(children: [
              const SpinKitThreeBounce(color: Colors.blue, size: 20),
              const SizedBox(width: 10),
              Text(localizations.translate('creatingRFCOMM'), style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold))
             ]),
          if (_lastError != null)
            Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200)
              ),
              child: Text('${localizations.translate('status')}: $_lastError', maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.red, fontSize: 13)),
            ),
          const Divider(height: 30),
          Text(localizations.translate('bondedDevices'), style: const TextStyle(fontWeight: FontWeight.bold)),
          Expanded(
            child: ListView.builder(
              itemCount: _devicesList.length,
              itemBuilder: (context, index) {
                final device = _devicesList[index];
                final isCurrentDevice = _connectedDevice?.address == device.address;
                return Card(
                  color: isCurrentDevice ? Colors.green[50] : null,
                  child: ListTile(
                    leading: Icon(
                      isCurrentDevice ? Icons.bluetooth_connected : Icons.memory,
                      color: isCurrentDevice ? Colors.green : null,
                    ),
                    title: Text(device.name ?? localizations.translate('unknown')),
                    subtitle: Text(device.address),
                    trailing: isCurrentDevice 
                      ? const Icon(Icons.check_circle, color: Colors.green)
                      : (_isConnecting ? null : const Icon(Icons.login)),
                    onTap: isCurrentDevice || _isConnecting ? null : () => _connectToDevice(device),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class WiFiSetupPage extends StatefulWidget {
  final BluetoothConnection connection;
  final Stream<Uint8List> inputStream;
  final BluetoothDevice device;
  const WiFiSetupPage({super.key, required this.connection, required this.inputStream, required this.device});

  @override
  State<WiFiSetupPage> createState() => _WiFiSetupPageState();
}

class _WiFiSetupPageState extends State<WiFiSetupPage> {
  final TextEditingController _ssidController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isSending = false;
  String? _statusMessage;
  bool _passwordVisible = false;
  String _response = '';
  StreamSubscription? _responseSubscription;

  @override
  void initState() {
    super.initState();
    _listenForResponses();
  }

  void _listenForResponses() {
    _responseSubscription = widget.inputStream.listen(
      (data) {
        final message = String.fromCharCodes(data).trim();
        debugPrint('Received from Pi: $message');
        if (mounted) {
          setState(() {
            _response += '$message\n';
            if (message.contains('SUCCESS')) {
              _statusMessage = '✓ WiFi configured successfully!';
              _isSending = false;
            } else if (message.contains('ERROR')) {
              _statusMessage = '✗ Configuration failed: $message';
              _isSending = false;
            }
          });
        }
      },
      onDone: () {
        debugPrint('Connection closed');
        if (mounted) {
          setState(() {
            _statusMessage = 'Connection closed';
            _isSending = false;
          });
        }
      },
    );
  }

  Future<void> _sendWiFiCredentials() async {
    final ssid = _ssidController.text.trim();
    final password = _passwordController.text.trim();

    if (ssid.isEmpty) {
      setState(() => _statusMessage = 'Please enter WiFi name (SSID)');
      return;
    }

    setState(() {
      _isSending = true;
      _statusMessage = 'Sending WiFi credentials...';
      _response = '';
    });

    try {
      final payload = 'WIFI:$ssid:$password\n';
      widget.connection.output.add(Uint8List.fromList(payload.codeUnits));
      await widget.connection.output.allSent;
      
      debugPrint('Sent WiFi credentials: SSID=$ssid');
    } catch (e) {
      setState(() {
        _statusMessage = 'Error sending credentials: $e';
        _isSending = false;
      });
    }
  }

  @override
  void dispose() {
    _responseSubscription?.cancel();
    _ssidController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text('${localizations.translate('setup')} ${widget.device.name}')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.wifi, color: Colors.blue, size: 80),
            const SizedBox(height: 20),
            Text(
              localizations.translate('configureWiFi'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              'Enter your WiFi credentials to configure ${widget.device.name}',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 40),
            TextField(
              controller: _ssidController,
              decoration: InputDecoration(
                labelText: localizations.translate('wifiSSID'),
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.wifi),
                hintText: localizations.translate('enterSSID'),
              ),
              enabled: !_isSending,
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _passwordController,
              obscureText: !_passwordVisible,
              decoration: InputDecoration(
                labelText: localizations.translate('wifiPassword'),
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.lock),
                hintText: localizations.translate('enterWifiPassword'),
                suffixIcon: IconButton(
                  icon: Icon(_passwordVisible ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _passwordVisible = !_passwordVisible),
                ),
              ),
              enabled: !_isSending,
            ),
            const SizedBox(height: 30),
            ElevatedButton.icon(
              onPressed: _isSending ? null : _sendWiFiCredentials,
              icon: _isSending 
                ? const SizedBox(
                    width: 20, 
                    height: 20, 
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.send),
              label: Text(_isSending ? localizations.translate('configuring') : localizations.translate('configureWiFi')),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle: const TextStyle(fontSize: 16),
              ),
            ),
            const SizedBox(height: 20),
            if (_statusMessage != null)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _statusMessage!.contains('✓') ? Colors.green[50] : Colors.orange[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _statusMessage!.contains('✓') ? Colors.green : Colors.orange,
                  ),
                ),
                child: Text(
                  _statusMessage!,
                  style: TextStyle(
                    color: _statusMessage!.contains('✓') ? Colors.green[900] : Colors.orange[900],
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            if (_response.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(localizations.translate('piResponse'), style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(_response, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class TextBoxPage extends StatefulWidget {
  const TextBoxPage({super.key});
  @override
  State<TextBoxPage> createState() => _TextBoxPageState();
}

class _TextBoxPageState extends State<TextBoxPage> {
  final _api = ApiService();
  final _foodController = TextEditingController();
  final _allergyController = TextEditingController();

  List<Map<String, dynamic>> _foods = [];
  List<Map<String, dynamic>> _allergies = [];

  bool _loadingFoods = true;
  bool _loadingAllergies = true;
  bool _foodsError = false;
  bool _allergiesError = false;

  bool _addingFood = false;
  bool _addingAllergy = false;

  @override
  void initState() {
    super.initState();
    _loadFoods();
    _loadAllergies();
  }

  @override
  void dispose() {
    _foodController.dispose();
    _allergyController.dispose();
    super.dispose();
  }

  Future<void> _loadFoods() async {
    setState(() { _loadingFoods = true; _foodsError = false; });
    try {
      final data = await _api.getPreferredFoods();
      if (mounted) setState(() { _foods = List<Map<String, dynamic>>.from(data); _loadingFoods = false; });
    } catch (_) {
      if (mounted) setState(() { _loadingFoods = false; _foodsError = true; });
    }
  }

  Future<void> _loadAllergies() async {
    setState(() { _loadingAllergies = true; _allergiesError = false; });
    try {
      final data = await _api.getAllergies();
      if (mounted) setState(() { _allergies = List<Map<String, dynamic>>.from(data); _loadingAllergies = false; });
    } catch (_) {
      if (mounted) setState(() { _loadingAllergies = false; _allergiesError = true; });
    }
  }

  Future<void> _addFood() async {
    final name = _foodController.text.trim();
    if (name.isEmpty || _addingFood) return;
    setState(() => _addingFood = true);
    try {
      final item = await _api.addPreferredFood(name: name);
      if (mounted) {
        setState(() { _foods.add(Map<String, dynamic>.from(item['data'] ?? item)); _addingFood = false; });
        _foodController.clear();
      }
    } catch (_) {
      if (mounted) setState(() => _addingFood = false);
    }
  }

  Future<void> _deleteFood(Map<String, dynamic> food) async {
    final id = (food['id'] ?? food['_id'])?.toString();
    if (id == null) return;
    // Optimistic remove
    setState(() => _foods.removeWhere((f) => (f['id'] ?? f['_id'])?.toString() == id));
    try {
      await _api.deletePreferredFood(id: id);
    } catch (_) {
      // Restore on failure
      if (mounted) setState(() => _foods.add(food));
    }
  }

  Future<void> _addAllergy() async {
    final name = _allergyController.text.trim();
    if (name.isEmpty || _addingAllergy) return;
    setState(() => _addingAllergy = true);
    try {
      final item = await _api.addAllergy(name: name);
      if (mounted) {
        setState(() { _allergies.add(Map<String, dynamic>.from(item['data'] ?? item)); _addingAllergy = false; });
        _allergyController.clear();
      }
    } catch (_) {
      if (mounted) setState(() => _addingAllergy = false);
    }
  }

  Future<void> _deleteAllergy(Map<String, dynamic> allergy) async {
    final id = (allergy['id'] ?? allergy['_id'])?.toString();
    if (id == null) return;
    setState(() => _allergies.removeWhere((a) => (a['id'] ?? a['_id'])?.toString() == id));
    try {
      await _api.deleteAllergy(id: id);
    } catch (_) {
      if (mounted) setState(() => _allergies.add(allergy));
    }
  }

  Widget _buildInputRow({
    required TextEditingController controller,
    required String hint,
    required bool loading,
    required VoidCallback onAdd,
  }) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              hintText: hint,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
            onSubmitted: (_) => onAdd(),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          height: 44,
          child: ElevatedButton(
            onPressed: loading ? null : onAdd,
            child: loading
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Add'),
          ),
        ),
      ],
    );
  }

  Widget _buildBubbles({
    required List<Map<String, dynamic>> items,
    required bool loading,
    required bool hasError,
    required VoidCallback onRetry,
    required Future<void> Function(Map<String, dynamic>) onDelete,
    required String emptyText,
    required Color color,
  }) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (hasError) {
      return GestureDetector(
        onTap: onRetry,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text('Error loading data. Tap to retry.', style: TextStyle(color: Colors.red[700])),
        ),
      );
    }
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(emptyText, style: const TextStyle(color: Colors.grey)),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: items.map((item) {
        final name = (item['name'] ?? '').toString();
        return Chip(
          label: Text(name),
          backgroundColor: color.withValues(alpha: 0.15),
          side: BorderSide(color: color.withValues(alpha: 0.4)),
          deleteIcon: Icon(Icons.close, size: 16, color: color),
          onDeleted: () => onDelete(item),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Preferred Foods', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          _buildInputRow(
            controller: _foodController,
            hint: 'Type a food name and press Add...',
            loading: _addingFood,
            onAdd: _addFood,
          ),
          const SizedBox(height: 12),
          _buildBubbles(
            items: _foods,
            loading: _loadingFoods,
            hasError: _foodsError,
            onRetry: _loadFoods,
            onDelete: _deleteFood,
            emptyText: 'No preferred foods added yet.',
            color: Colors.green,
          ),
          const SizedBox(height: 28),
          const Text('Allergies', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          _buildInputRow(
            controller: _allergyController,
            hint: 'Type an allergy and press Add...',
            loading: _addingAllergy,
            onAdd: _addAllergy,
          ),
          const SizedBox(height: 12),
          _buildBubbles(
            items: _allergies,
            loading: _loadingAllergies,
            hasError: _allergiesError,
            onRetry: _loadAllergies,
            onDelete: _deleteAllergy,
            emptyText: 'No allergies added yet.',
            color: Colors.red,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class EmptyPage extends StatefulWidget {
  const EmptyPage({super.key});
  @override
  State<EmptyPage> createState() => _EmptyPageState();
}

class _EmptyPageState extends State<EmptyPage> {
  final SettingsManager _settings = SettingsManager();
  late String _selectedLanguage;
  late double _ttsSpeed;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  void _loadSettings() {
    _selectedLanguage = _settings.language;
    _ttsSpeed = _settings.ttsSpeed;
    setState(() {});
    debugPrint('📖 Loaded settings page');
  }

  void _saveLanguage(String language) {
    _settings.language = language;
  }

  void _saveTTSSpeed(double speed) {
    // Cancel any existing timer
    _debounceTimer?.cancel();
    
    // Start a new timer - only save after 300ms of no changes
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _settings.ttsSpeed = speed;
      debugPrint('✅ Saved TTS speed: $speed');
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final username = _settings.username ?? 'User';
    
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // User Info Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 30,
                  child: Icon(Icons.person, size: 32),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Logged in as:',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      Text(
                        username,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () {
                    // Show logout confirmation dialog
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Logout'),
                        content: const Text('Are you sure you want to logout?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () {
                              _settings.logout();
                              Navigator.of(context).pushAndRemoveUntil(
                                MaterialPageRoute(builder: (context) => const LoginPage()),
                                (route) => false,
                              );
                            },
                            child: const Text('Logout', style: TextStyle(color: Colors.red)),
                          ),
                        ],
                      ),
                    );
                  },
                  icon: const Icon(Icons.logout, color: Colors.red),
                  tooltip: 'Logout',
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          
          Text(
            localizations.translate('language'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          DropdownButton<String>(
            value: _selectedLanguage,
            isExpanded: true,
            items: [
              DropdownMenuItem(value: 'en', child: Text(localizations.translate('english'))),
              DropdownMenuItem(value: 'bg', child: Text(localizations.translate('bulgarian'))),
            ],
            onChanged: (String? newValue) {
              if (newValue != null) {
                setState(() {
                  _selectedLanguage = newValue;
                });
                _saveLanguage(newValue);
                // Change the app locale
                MyApp.setLocale(context, Locale(newValue));
              }
            },
          ),
          const SizedBox(height: 32),
          Text(
            localizations.translate('ttsSpeed'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: _ttsSpeed,
                  min: 1.0,
                  max: 200.0,
                  divisions: 99,
                  label: '${_ttsSpeed.round()}%',
                  onChanged: (double value) {
                    setState(() {
                      _ttsSpeed = value;
                    });
                    _saveTTSSpeed(value);
                  },
                ),
              ),
              SizedBox(
                width: 60,
                child: Text(
                  '${_ttsSpeed.round()}%',
                  style: const TextStyle(fontSize: 16),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// Login/Register Page
class LoginPage extends StatefulWidget {
  final String? pendingInviteToken;
  
  const LoginPage({super.key, this.pendingInviteToken});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  bool _isLogin = true;
  bool _passwordVisible = false;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // Show message if there's a pending invite
    if (widget.pendingInviteToken != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final localizations = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(localizations.translate('loginToAcceptInvite')),
            backgroundColor: Colors.blue,
            duration: const Duration(seconds: 5),
          ),
        );
      });
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    super.dispose();
  }

  void _handleSubmit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    final localizations = AppLocalizations.of(context);

    setState(() {
      _errorMessage = null;
      _isLoading = true;
    });

    if (email.isEmpty) {
      setState(() {
        _errorMessage = localizations.translate('emailRequired');
        _isLoading = false;
      });
      return;
    }

    if (password.isEmpty) {
      setState(() {
        _errorMessage = localizations.translate('passwordRequired');
        _isLoading = false;
      });
      return;
    }

    if (!_isLogin) {
      // Registration validation
      if (firstName.isEmpty) {
        setState(() {
          _errorMessage = localizations.translate('firstNameRequired');
          _isLoading = false;
        });
        return;
      }
      if (lastName.isEmpty) {
        setState(() {
          _errorMessage = localizations.translate('lastNameRequired');
          _isLoading = false;
        });
        return;
      }
    }

    try {
      final api = ApiService();
      
      if (_isLogin) {
        // Login flow
        final loginResult = await api.login(email: email, password: password);
        final accessToken = loginResult['accessToken'] as String?;
        final refreshToken = loginResult['refreshToken'] as String?;
        
        if (accessToken == null) {
          throw ApiException('Invalid response from server', 500);
        }
        
        // Store tokens temporarily to fetch profile
        SettingsManager().updateTokens(accessToken: accessToken, refreshToken: refreshToken);
        
        // Fetch user profile to get role and other info
        final profile = await api.getMe();
        final role = profile['role'] as String? ?? 'user';
        final profileFirstName = profile['firstName'] as String? ?? '';
        final profileLastName = profile['lastName'] as String? ?? '';
        final userId = profile['id']?.toString();
        
        SettingsManager().login(
          email,
          accessToken: accessToken,
          refreshToken: refreshToken,
          email: email,
          firstName: profileFirstName,
          lastName: profileLastName,
          role: role,
          userId: userId,
        );
      } else {
        // Register flow - creates relative account
        await api.register(
          firstName: firstName,
          lastName: lastName,
          email: email,
          password: password,
        );
        
        // After successful registration, login automatically
        final loginResult = await api.login(email: email, password: password);
        final accessToken = loginResult['accessToken'] as String?;
        final refreshToken = loginResult['refreshToken'] as String?;
        
        if (accessToken == null) {
          throw ApiException('Invalid response from server', 500);
        }
        
        // Store tokens and fetch profile
        SettingsManager().updateTokens(accessToken: accessToken, refreshToken: refreshToken);
        final profile = await api.getMe();
        final userId = profile['id']?.toString();
        
        SettingsManager().login(
          email,
          accessToken: accessToken,
          refreshToken: refreshToken,
          email: email,
          firstName: firstName,
          lastName: lastName,
          role: 'relative', // Register always creates relatives
          userId: userId,
        );
      }
      
      // Navigate to main app (with pending invite if present)
      if (mounted) {
        // Clear the deep link pending token since we're handling it
        DeepLinkService().clearPendingToken();
        
        if (widget.pendingInviteToken != null) {
          // Navigate with pending invite token to accept it
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => MainScreen(
                initialTab: 2, // My Relatives tab
                pendingInviteToken: widget.pendingInviteToken,
              ),
            ),
          );
        } else {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const MainScreen()),
          );
        }
      }
    } on ApiException catch (e) {
      setState(() {
        _errorMessage = e.message;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = localizations.translate('networkError');
        _isLoading = false;
      });
      debugPrint('❌ Auth error: $e');
    }
  }

  void _handleBypass() {
    // Temporary bypass for development - login as relative
    SettingsManager().login(
      'dev_relative',
      email: 'dev@example.com',
      firstName: 'Dev',
      lastName: 'Relative',
      role: 'relative',
    );
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => const MainScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.blue.shade400, Colors.blue.shade800],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // App Logo/Icon
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 20,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.wifi,
                      size: 80,
                      color: Colors.blue,
                    ),
                  ),
                  const SizedBox(height: 30),
                  
                  // Welcome Text
                  Text(
                    localizations.translate('welcome'),
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 40),
                  
                  // Login/Register Card
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Title
                        Text(
                          _isLogin 
                            ? localizations.translate('loginTitle')
                            : localizations.translate('registerTitle'),
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        
                        // First Name Field (only for registration)
                        if (!_isLogin) ...[
                          TextField(
                            controller: _firstNameController,
                            decoration: InputDecoration(
                              labelText: localizations.translate('firstName'),
                              hintText: localizations.translate('enterFirstName'),
                              prefixIcon: const Icon(Icons.person),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              filled: true,
                              fillColor: Colors.grey[50],
                            ),
                          ),
                          const SizedBox(height: 16),
                          
                          // Last Name Field (only for registration)
                          TextField(
                            controller: _lastNameController,
                            decoration: InputDecoration(
                              labelText: localizations.translate('lastName'),
                              hintText: localizations.translate('enterLastName'),
                              prefixIcon: const Icon(Icons.person_outline),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              filled: true,
                              fillColor: Colors.grey[50],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        
                        // Email Field
                        TextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: InputDecoration(
                            labelText: localizations.translate('email'),
                            hintText: localizations.translate('enterEmail'),
                            prefixIcon: const Icon(Icons.email),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                            fillColor: Colors.grey[50],
                          ),
                        ),
                        const SizedBox(height: 16),
                        
                        // Password Field
                        TextField(
                          controller: _passwordController,
                          obscureText: !_passwordVisible,
                          decoration: InputDecoration(
                            labelText: localizations.translate('password'),
                            hintText: localizations.translate('enterPassword'),
                            prefixIcon: const Icon(Icons.lock),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _passwordVisible 
                                  ? Icons.visibility 
                                  : Icons.visibility_off,
                              ),
                              onPressed: () {
                                setState(() {
                                  _passwordVisible = !_passwordVisible;
                                });
                              },
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                            fillColor: Colors.grey[50],
                          ),
                          onSubmitted: (_) => _handleSubmit(),
                        ),
                        
                        // Error Message
                        if (_errorMessage != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red[50],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.red.shade200),
                            ),
                            child: Text(
                              _errorMessage!,
                              style: TextStyle(color: Colors.red[900]),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                        
                        const SizedBox(height: 24),
                        
                        // Submit Button
                        ElevatedButton(
                          onPressed: _isLoading ? null : _handleSubmit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 2,
                          ),
                          child: _isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : Text(
                                _isLogin 
                                  ? localizations.translate('login')
                                  : localizations.translate('registerAsRelative'),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                        ),
                        
                        const SizedBox(height: 16),
                        
                        // Toggle Login/Register
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _isLogin
                                ? localizations.translate('dontHaveAccount')
                                : localizations.translate('alreadyHaveAccount'),
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                            TextButton(
                              onPressed: () {
                                setState(() {
                                  _isLogin = !_isLogin;
                                  _errorMessage = null;
                                });
                              },
                              child: Text(
                                _isLogin
                                  ? localizations.translate('registerHere')
                                  : localizations.translate('loginHere'),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        
                        // Temporary Bypass Button (for development)
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _handleBypass,
                          icon: const Icon(Icons.developer_mode, size: 16),
                          label: Text(localizations.translate('tempBypass')),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.orange,
                            side: const BorderSide(color: Colors.orange),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Manage Users Page (for relatives only)
class ManageUsersPage extends StatefulWidget {
  const ManageUsersPage({super.key});

  @override
  State<ManageUsersPage> createState() => _ManageUsersPageState();
}

class _ManageUsersPageState extends State<ManageUsersPage> {
  final TextEditingController _userEmailController = TextEditingController();
  final TextEditingController _userPasswordController = TextEditingController();
  final TextEditingController _userFirstNameController = TextEditingController();
  final TextEditingController _userLastNameController = TextEditingController();
  final TextEditingController _inviteEmailController = TextEditingController();
  bool _isCreating = false;
  bool _isInviting = false;

  @override
  void dispose() {
    _userEmailController.dispose();
    _userPasswordController.dispose();
    _userFirstNameController.dispose();
    _userLastNameController.dispose();
    _inviteEmailController.dispose();
    super.dispose();
  }

  void _createUser() async {
    final email = _userEmailController.text.trim();
    final password = _userPasswordController.text.trim();
    final firstName = _userFirstNameController.text.trim();
    final lastName = _userLastNameController.text.trim();
    final localizations = AppLocalizations.of(context);

    if (email.isEmpty || password.isEmpty || firstName.isEmpty || lastName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All fields are required')),
      );
      return;
    }

    setState(() => _isCreating = true);

    try {
      final api = ApiService();
      final result = await api.createBlindUser(
        firstName: firstName,
        lastName: lastName,
        email: email,
        password: password,
      );
      
      if (!mounted) return;
      
      // Check if user was created or if invite was sent (user already exists)
      final wasInvited = result['invited'] == true;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            wasInvited 
              ? localizations.translate('inviteAlreadySent')
              : localizations.translate('blindUserCreated'),
          ),
          backgroundColor: Colors.green,
        ),
      );

      // Clear fields
      _userEmailController.clear();
      _userPasswordController.clear();
      _userFirstNameController.clear();
      _userLastNameController.clear();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Colors.red,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(localizations.translate('networkError')),
          backgroundColor: Colors.red,
        ),
      );
      debugPrint('❌ Create user error: $e');
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  void _inviteUser() async {
    final email = _inviteEmailController.text.trim();
    final localizations = AppLocalizations.of(context);

    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Email is required')),
      );
      return;
    }

    setState(() => _isInviting = true);

    try {
      final api = ApiService();
      await api.sendInvite(email: email);
      
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(localizations.translate('inviteSent')),
          backgroundColor: Colors.green,
        ),
      );

      _inviteEmailController.clear();
    } on ApiException catch (e) {
      if (!mounted) return;
      String message = e.message;
      if (e.statusCode == 404) {
        message = localizations.translate('userNotFound');
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(localizations.translate('networkError')),
          backgroundColor: Colors.red,
        ),
      );
      debugPrint('❌ Invite user error: $e');
    } finally {
      if (mounted) setState(() => _isInviting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              localizations.translate('manageUsers'),
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),

            // Create New User Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(Icons.person_add, color: Colors.blue[700]),
                      const SizedBox(width: 8),
                      Text(
                        localizations.translate('createNewUser'),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue[700],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // First Name
                  TextField(
                    controller: _userFirstNameController,
                    decoration: InputDecoration(
                      labelText: localizations.translate('firstName'),
                      hintText: localizations.translate('enterFirstName'),
                      prefixIcon: const Icon(Icons.person),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Last Name
                  TextField(
                    controller: _userLastNameController,
                    decoration: InputDecoration(
                      labelText: localizations.translate('lastName'),
                      hintText: localizations.translate('enterLastName'),
                      prefixIcon: const Icon(Icons.person_outline),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Email
                  TextField(
                    controller: _userEmailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: localizations.translate('email'),
                      hintText: localizations.translate('enterEmail'),
                      prefixIcon: const Icon(Icons.email),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Password
                  TextField(
                    controller: _userPasswordController,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: localizations.translate('password'),
                      hintText: localizations.translate('enterPassword'),
                      prefixIcon: const Icon(Icons.lock),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Create User Button
                  ElevatedButton.icon(
                    onPressed: _isCreating ? null : _createUser,
                    icon: _isCreating
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Icon(Icons.person_add),
                    label: Text(
                      localizations.translate('createUser'),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Or Divider
            Row(
              children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'OR',
                    style: TextStyle(color: Colors.grey[600], fontWeight: FontWeight.bold),
                  ),
                ),
                const Expanded(child: Divider()),
              ],
            ),

            const SizedBox(height: 24),

            // Invite Existing User Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(Icons.mail_outline, color: Colors.green[700]),
                      const SizedBox(width: 8),
                      Text(
                        localizations.translate('inviteExistingUser'),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.green[700],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'If the user already exists, enter their email to send them an invitation.',
                    style: TextStyle(color: Colors.grey[700], fontSize: 12),
                  ),
                  const SizedBox(height: 16),

                  // Email field for invite
                  TextField(
                    controller: _inviteEmailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: localizations.translate('email'),
                      hintText: localizations.translate('enterEmail'),
                      prefixIcon: const Icon(Icons.email),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Invite Button
                  ElevatedButton.icon(
                    onPressed: _isInviting ? null : _inviteUser,
                    icon: _isInviting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Icon(Icons.send),
                    label: const Text(
                      'Send Invitation',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

// Accept Invite Page (for blind users to accept relative invites)
class AcceptInvitePage extends StatefulWidget {
  final String? pendingToken;
  
  const AcceptInvitePage({super.key, this.pendingToken});

  @override
  State<AcceptInvitePage> createState() => _AcceptInvitePageState();
}

class _AcceptInvitePageState extends State<AcceptInvitePage> {
  final TextEditingController _tokenController = TextEditingController();
  bool _isAccepting = false;
  List<dynamic> _relatives = [];
  bool _isLoadingRelatives = true;
  bool _autoProcessed = false;

  @override
  void initState() {
    super.initState();
    _loadRelatives();
    
    // If there's a pending token, auto-fill and process it
    if (widget.pendingToken != null && widget.pendingToken!.isNotEmpty) {
      _tokenController.text = widget.pendingToken!;
      // Auto-accept after the widget is built
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_autoProcessed) {
          _autoProcessed = true;
          _acceptInviteWithToken(widget.pendingToken!);
        }
      });
    }
  }

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _loadRelatives() async {
    setState(() => _isLoadingRelatives = true);
    try {
      final api = ApiService();
      final relatives = await api.getMyRelatives();
      if (mounted) {
        setState(() {
          _relatives = relatives;
          _isLoadingRelatives = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Failed to load relatives: $e');
      if (mounted) setState(() => _isLoadingRelatives = false);
    }
  }

  void _acceptInvite() async {
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      final localizations = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localizations.translate('tokenRequired'))),
      );
      return;
    }
    await _acceptInviteWithToken(token);
  }

  Future<void> _acceptInviteWithToken(String token) async {
    final localizations = AppLocalizations.of(context);

    setState(() => _isAccepting = true);

    try {
      final api = ApiService();
      await api.acceptInvite(token: token);
      
      // Clear the deep link pending token
      DeepLinkService().clearPendingToken();
      
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(localizations.translate('inviteAccepted')),
          backgroundColor: Colors.green,
        ),
      );

      _tokenController.clear();
      _loadRelatives(); // Refresh the list
    } on ApiException catch (e) {
      if (!mounted) return;
      String message = e.message;
      if (e.statusCode == 400) {
        message = localizations.translate('inviteExpired');
      } else if (e.statusCode == 404) {
        message = localizations.translate('inviteNotFound');
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(localizations.translate('networkError')),
          backgroundColor: Colors.red,
        ),
      );
      debugPrint('❌ Accept invite error: $e');
    } finally {
      if (mounted) setState(() => _isAccepting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              localizations.translate('myRelatives'),
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),

            // Accept Invite Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.purple[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.purple.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(Icons.link, color: Colors.purple[700]),
                      const SizedBox(width: 8),
                      Text(
                        localizations.translate('acceptInvite'),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.purple[700],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    localizations.translate('acceptInviteDescription'),
                    style: TextStyle(color: Colors.grey[700], fontSize: 12),
                  ),
                  const SizedBox(height: 16),

                  // Token field
                  TextField(
                    controller: _tokenController,
                    decoration: InputDecoration(
                      labelText: localizations.translate('inviteToken'),
                      hintText: localizations.translate('enterInviteToken'),
                      prefixIcon: const Icon(Icons.vpn_key),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Accept Button
                  ElevatedButton.icon(
                    onPressed: _isAccepting ? null : _acceptInvite,
                    icon: _isAccepting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Icon(Icons.check),
                    label: Text(
                      localizations.translate('acceptInviteButton'),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // My Relatives Section
            Text(
              localizations.translate('linkedRelatives'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            if (_isLoadingRelatives)
              const Center(child: CircularProgressIndicator())
            else if (_relatives.isEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Icon(Icons.people_outline, size: 48, color: Colors.grey[400]),
                    const SizedBox(height: 12),
                    Text(
                      localizations.translate('noRelativesYet'),
                      style: TextStyle(color: Colors.grey[600]),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _relatives.length,
                itemBuilder: (context, index) {
                  final relative = _relatives[index];
                  final name = '${relative['firstName'] ?? ''} ${relative['lastName'] ?? ''}'.trim();
                  final email = relative['email'] ?? '';
                  
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.blue[100],
                        child: Icon(Icons.person, color: Colors.blue[700]),
                      ),
                      title: Text(name.isNotEmpty ? name : email),
                      subtitle: name.isNotEmpty ? Text(email) : null,
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
