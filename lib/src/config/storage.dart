import 'constants.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Storage bridge for FlutterFeathersjs
///
/// Used to store access token and user data
///
/// Be aware that this is not secure storage, use any thing else more secure storage instead
class Storage {
  final storage = new FlutterSecureStorage();

  /// Save the JWT token for reAuth() purpose
  ///
  /// [accessToken] is the JWT token
  ///
  /// [client] is the standalone client name, if null, the accessToken will be saved in the default key
  ///
  Future<void> saveAccessToken(String accessToken, {String? client}) async {
    await storage.write(key: FEATHERSJS_ACCESS_TOKEN, value: accessToken);
  }
  Future<void> saveRefreshToken(String accessToken, {String? client}) async {
    await storage.write(key: FEATHERSJS_REFRESH_TOKEN, value: accessToken);
  }

  /// Get the early stored JWT for reAuth() purpose
  ///
  /// [client] is optional, if you are using standalone clients, you can specify the client name
  ///
  ///
  Future<String?> getAccessToken({String? client}) async {
    return await storage.read(key: FEATHERSJS_ACCESS_TOKEN);
  }
  Future<String?> getRefreshToken({String? client}) async {
    return await storage.read(key: FEATHERSJS_REFRESH_TOKEN);
  }

  /// Delete the early stored JWT for reAuth() purpose
  ///
  /// [client] is optional, if you are using standalone clients, you can specify the client name
  Future<void> deleteAccessToken({String? client}) async {
    await storage.delete(key: FEATHERSJS_ACCESS_TOKEN);
  }
  Future<void> deleteRefreshToken({String? client}) async {
    await storage.delete(key: FEATHERSJS_REFRESH_TOKEN);
  }
  Future<void> deleteTokens() async {
    await storage.delete(key: FEATHERSJS_ACCESS_TOKEN);
    await storage.delete(key: FEATHERSJS_REFRESH_TOKEN);
  }
}
