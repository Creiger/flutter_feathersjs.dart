import 'constants.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Storage bridge for FlutterFeathersjs
///
/// Used to store access token and user data
///
/// Uses SharedPreferences for web compatibility
class Storage {
  /// Save the JWT token for reAuth() purpose
  ///
  /// [accessToken] is the JWT token
  ///
  /// [client] is the standalone client name, if null, the accessToken will be saved in the default key
  ///
  Future<void> saveAccessToken(String accessToken, {String? client}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(FEATHERSJS_ACCESS_TOKEN, accessToken ?? '');
  }

  Future<void> saveRefreshToken(String accessToken, {String? client}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(FEATHERSJS_REFRESH_TOKEN, accessToken ?? '');
  }

  /// Get the early stored JWT for reAuth() purpose
  ///
  /// [client] is optional, if you are using standalone clients, you can specify the client name
  ///
  ///
  Future<String?> getAccessToken({String? client}) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(FEATHERSJS_ACCESS_TOKEN);
  }

  Future<String?> getRefreshToken({String? client}) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(FEATHERSJS_REFRESH_TOKEN);
  }

  /// Delete the early stored JWT for reAuth() purpose
  ///
  /// [client] is optional, if you are using standalone clients, you can specify the client name
  Future<void> deleteAccessToken({String? client}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(FEATHERSJS_ACCESS_TOKEN);
  }

  Future<void> deleteRefreshToken({String? client}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(FEATHERSJS_REFRESH_TOKEN);
  }

  Future<void> deleteTokens() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(FEATHERSJS_ACCESS_TOKEN);
    await prefs.remove(FEATHERSJS_REFRESH_TOKEN);
  }
}
