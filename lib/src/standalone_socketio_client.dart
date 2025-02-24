import 'dart:async';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:flutter/foundation.dart' as Foundation;
import 'package:flutter_feathersjs/src/config/helper.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:event_bus/event_bus.dart';
import 'config/constants.dart';
import 'config/storage.dart';
import 'featherjs_client_base.dart';

/// @See https://github.com/Dahkenangnon/flutter_feathersjs.dart/issues/28 for the origin of this implementation
///
///
/// [FlutterFeathersjsSocketio] is a standalone socketio client for flutter_feathersjs
///
/// Usage: Fully customize your socketio client, use seperate client
/// and a clean syntax. Customize client means you can set autoConnect, baseUrl, extraHeaders, transports, etc
///
/// If the above usage is not your case, you can use  [FlutterFeathersjs] instead
///
/// You can use it like this:
///
///
/// ```dart
/// import 'package:flutter_feathersjs/flutter_feathersjs.dart';
/// import 'package:socket_io_client/socket_io_client.dart' as IO;
///
/// FlutterFeathersjs client = FlutterFeathersjs();
/// IO.Socket io = IO.io(baseUrl)
///
/// client.configure(FlutterFeathersjs.socketioClient(io));
///
/// client.service('messages').create({
///   text: 'A new message'
/// });
///
/// ```
///
/// {@macro response_format}
///
///--------------------------------------------
class FlutterFeathersjsSocketio extends FlutterFeathersjsClient {
  // Socketio
  late IO.Socket _socket;

  // Current service name
  String? serviceName;

  // Event bus
  EventBus eventBus = EventBus(sync: true);

  var storage = Storage();

  FlutterFeathersjsSocketio(this._socket) {
    // Set headers for socketio authorization
    // Setting on every request the Bearer Token in the header
    () async {
      String? token = await storage.getAccessToken(client: "socketio");
      if (token != null) {
        _socket.io.options!["extraHeaders"] = {
          'Authorization': 'Bearer $token',
        };
      }
    }();

    _socket.on('connect', (_) {
      eventBus.fire(Connected());
    });

    _socket.on('disconnect', (_) {
      eventBus.fire(DisConnected());
    });

    // Only print these when in debug mode, disable in release mode
    if (!Foundation.kReleaseMode) {
      _socket.on('connect', (_) {
        print("Socket connection established");
      });

      _socket.on('connect_error', (e) {
        print("Connection error");
        print(e);
      });

      _socket.on('connect_timeout', (data) {
        print("Timeout error");
        print(data);
      });

      _socket.on('connecting', (_) => print("Connecting..."));
      _socket.on('disconnect', (_) {});

      _socket.on('error', (e) {
        print("____An error occured____");
        print(e);
      });

      _socket.on('reconnect', (_) => print("Reconnected"));
      _socket.on('reconnect_error', (_) => print("Reconnection error..."));
      _socket.on(
          'reconnect_attempt', (_) => print("Attempting a reconnection"));
      _socket.on('reconnect_failed', (_) => print("A reconnection failed"));
      _socket.on('reconnecting', (_) => print("Reconnecting..."));
    }
    Timer.periodic(Duration(seconds: 3600), (Timer timer) {
      if (_socket.connected) {
        checkReAuthentication();
      }
    });
  }

  FlutterFeathersjsSocketio service(String serviceName) {
    this.serviceName = serviceName;
    return this;
  }

  ///
  /// Authenticate the user with realtime connection
  ///
  /// @Warning This function must be call afther auth with rest is OK
  ///
  /// Otherwise, you cannot be able to use socketio client because it won't be authed on the server
  ///
  /// @Warning: You don't need to use this directly in your code,
  /// use instead the global `flutterFeathersjs.authenticate({...})`
  ///
  Future<dynamic> authenticate(
      {String strategy = "local",
      required String? userName,
      required String? password,
      String userNameFieldName = "email"}) async {
    Completer asyncTask = Completer<dynamic>();
    FeatherJsError? featherJsError;

    _socket.emitWithAck('create', [
      'authentication',
      <String, dynamic>{
        "strategy": strategy,
        "$userNameFieldName": userName,
        "password": password
      }
    ], ack: (dataResponse) {
      if (!Foundation.kReleaseMode) {
        print("Receive response from server on socketio auth");
      }
      //Check whether auth is OK response.data["user"]
      if (dataResponse is List) {
        if (!Foundation.kReleaseMode) {
          print("Authentication process is ok in socketio auth");
        }
        //Every emit or on will be authed
        this._socket.io.options!['extraHeaders'] = {
          'Authorization': "Bearer ${dataResponse[1]["accessToken"]}"
        };
        storage.saveAccessToken(dataResponse[1]["accessToken"],
            client: "socketio");
        storage.saveRefreshToken(dataResponse[1]["refreshToken"] ?? '');
      } else {
        // On error
        if (!Foundation.kReleaseMode) {
          print("Authentication process failed in socket io auth");
        }
        featherJsError = new FeatherJsError(
            type: FeatherJsErrorType.IS_JWT_TOKEN_ERROR, error: dataResponse);
      }
      if (featherJsError != null) {
        asyncTask.completeError(featherJsError!); //Complete with error
      } else {
        // Complete with success
        asyncTask.complete(dataResponse[1]["user"]);
      }
    });

    return asyncTask.future;
  }

  bool isTokenExpired(String? token) {
    if (token == null) {
      return true;
    }
    final jwt = JWT.decode(token);
    final exp = jwt.payload['exp'] - 7200;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return now >= exp;
  }

  Future<void> checkReAuthentication() async {
    var oldToken = await storage.getAccessToken();
    var refreshToken = await storage.getRefreshToken();
    if (isTokenExpired(oldToken) && refreshToken != null) {
      await this.reAuthenticate();
    }
  }

  Future<dynamic> refreshAccessToken({String serviceName = "refresh-tokens"}) async {
    Completer asyncTask = Completer<dynamic>();
    FeatherJsError? featherJsError;
    var oldToken = await storage.getAccessToken();
    var refreshToken = await storage.getRefreshToken();
    if (isTokenExpired(oldToken) && refreshToken != null) {
      final jwt = JWT.decode(refreshToken);
      final userId = jwt.payload['sub'];
      _socket.emitWithAck('create', [
        serviceName,
        <String, dynamic>{
          "refreshToken": refreshToken,
          "_id": userId
        }
      ], ack: (dataResponse) async {
        if (dataResponse is List) {
          if (dataResponse[1]['accessToken'] != null) {
            await storage.saveAccessToken(dataResponse[1]['accessToken'], client: "rest");
          } else {
            featherJsError = new FeatherJsError(
                type: FeatherJsErrorType.IS_UNKNOWN_ERROR,
                error: dataResponse[1]["message"]);
          }
        } else {
          featherJsError = new FeatherJsError(
              type: FeatherJsErrorType.IS_UNKNOWN_ERROR,
              error: dataResponse);
        }
        if (featherJsError != null) {
          asyncTask.completeError(featherJsError!);
        } else {
          asyncTask.complete(true);
        }
      });
    } else {
      asyncTask.complete(true);
    }
    return asyncTask.future;
  }

  ///
  /// Authenticate the user with realtime connection
  ///
  /// @Warning This function must be call afther auth with rest is OK
  ///
  /// Otherwise, you cannot be able to use socketio client because it won't be authed on the server
  ///
  /// @Warning: You don't need to use this directly in your code,
  /// use instead the global `flutterFeathersjs.authenticate({...})`
  ///
  Future<dynamic> reAuthenticate() async {
    await refreshAccessToken();
    String? token = await storage.getAccessToken(client: "socketio");
    Completer asyncTask = Completer<dynamic>();
    FeatherJsError? featherJsError;

    _socket.emitWithAck('create', [
      'authentication',
      <String, dynamic>{
        'strategy': 'jwt',
        'accessToken': token,
      }
    ], ack: (dataResponse) {
      if (!Foundation.kReleaseMode) {
        print("Receive response from server on JWT request");
      }

      //Check whether auth is OK
      if (dataResponse is List) {
        if (!Foundation.kReleaseMode) {
          print("Authentication process is ok with JWT");
        }
        //Every emit or on will be authed
        this._socket.io.options!['extraHeaders'] = {
          'Authorization': "Bearer $token"
        };
      } else {
        // On error
        if (!Foundation.kReleaseMode) {
          print("Authentication process failed with JWT");
        }
        featherJsError = new FeatherJsError(
            type: FeatherJsErrorType.IS_JWT_TOKEN_ERROR, error: dataResponse);
      }
      if (featherJsError != null) {
        asyncTask.completeError(featherJsError!); //Complete with error
      } else {
        // Complete with success
        asyncTask.complete(dataResponse[1]["user"]);
      }
    });

    return asyncTask.future;
  }

  /// `EMIT find serviceName`
  ///
  /// Retrieves a list of all matching `query` resources from the service
  ///
  /// If no error is occured, you will get exactly feathersjs's data format
  ///
  /// Otherwise, an exception of type FeatherJsError will be raised
  ///
  /// Use FeatherJsErrorType.{ERROR} to known what happen
  ///
  ///
  Future<dynamic> find(Map<String, dynamic> query) async {
    Completer asyncTask = Completer<dynamic>();
    _socket.emitWithAck("find", [serviceName, query], ack: (response) {
      if (response is List) {
        asyncTask.complete(response[1]);
      } else {
        asyncTask.completeError(errorCode2FeatherJsError(response));
      }
    });
    return asyncTask.future;
  }

  /// `EMIT create serviceName`
  ///
  /// Create new ressource
  ///
  /// If no error is occured, you will get exactly feathersjs's data format
  ///
  /// Otherwise, an exception of type FeatherJsError will be raised
  ///
  /// Use FeatherJsErrorType.{ERROR} to known what happen
  ///
  Future<dynamic> create(Map<String, dynamic> data) {
    Completer asyncTask = Completer<dynamic>();

    _socket.emitWithAck("create", [serviceName, data], ack: (response) {
      if (response is List) {
        asyncTask.complete(response[1]);
      } else {
        asyncTask.completeError(errorCode2FeatherJsError(response));
      }
    });
    return asyncTask.future;
  }

  /// `EMIT update serviceName`
  ///
  /// Update a  ressource
  ///
  ///
  /// If no error is occured, you will get exactly feathersjs's data format
  ///
  /// Otherwise, an exception of type FeatherJsError will be raised
  ///
  /// Use FeatherJsErrorType.{ERROR} to known what happen
  ///
  Future<dynamic> update(String objectId, Map<String, dynamic> data) {
    Completer asyncTask = Completer<dynamic>();
    _socket.emitWithAck("update", [serviceName, objectId, data],
        ack: (response) {
      if (response is List) {
        asyncTask.complete(response[1]);
      } else {
        asyncTask.completeError(errorCode2FeatherJsError(response));
      }
    });
    return asyncTask.future;
  }

  /// `EMIT get serviceName`
  ///
  ///
  /// If no error is occured, you will get exactly feathersjs's data format
  ///
  /// Otherwise, an exception of type FeatherJsError will be raised
  ///
  /// Use FeatherJsErrorType.{ERROR} to known what happen
  ///
  Future<dynamic> get(String objectId) {
    Completer asyncTask = Completer<dynamic>();
    _socket.emitWithAck("get", [serviceName, objectId], ack: (response) {
      if (response is List) {
        asyncTask.complete(response[1]);
      } else {
        asyncTask.completeError(errorCode2FeatherJsError(response));
      }
    });
    return asyncTask.future;
  }

  /// `EMIT patch serviceName`
  ///
  /// Merge the existing data of a single or multiple resources with the new data
  ///
  /// If no error is occured, you will get exactly feathersjs's data format
  ///
  /// Otherwise, an exception of type FeatherJsError will be raised
  ///
  /// Use FeatherJsErrorType.{ERROR} to known what happen
  ///
  Future<dynamic> patch(String objectId, Map<String, dynamic> data, Map<String, dynamic> params) {
    Completer asyncTask = Completer<dynamic>();
    _socket.emitWithAck("patch", [serviceName, objectId, data, params],
        ack: (response) {
      if (response is List) {
        asyncTask.complete(response[1]);
      } else {
        asyncTask.completeError(errorCode2FeatherJsError(response));
      }
    });
    return asyncTask.future;
  }

  /// `EMIT remove serviceName`
  ///
  /// Delete a ressource on the server
  ///
  ///
  /// If no error is occured, you will get exactly feathersjs's data format
  ///
  /// Otherwise, an exception of type FeatherJsError will be raised
  ///
  /// Use FeatherJsErrorType.{ERROR} to known what happen
  ///
  Future<dynamic> remove(String objectId) {
    Completer asyncTask = Completer<dynamic>();
    _socket.emitWithAck("remove", [serviceName, objectId], ack: (response) {
      if (response is List) {
        asyncTask.complete(response[1]);
      } else {
        asyncTask.completeError(errorCode2FeatherJsError(response));
      }
    });
    return asyncTask.future;
  }

  /// Listen to On [` updated | patched | created | removed `] `serviceName`
  ///
  /// If no error is occured, you will get FeathersJsEventData<T>  feathersJsEventData
  ///
  ///     Then to retrieve the data send by feathers, do: feathersJsEventData.data
  ///
  ///     Event type send by feathers: feathersJsEventData.type
  ///
  /// Note: T is class that represent what feather js will send. You have to define it in your code
  ///
  ///
  /// Otherwise, an exception of type FeatherJsError will be raised that can be caught on the stream
  ///
  ///     Use FeatherJsErrorType.{ERROR} to known what happen
  ///
  Stream<FeathersJsEventData<T>> listen<T>(Function fromJson) {
    /// On updated event
    _socket.on('$serviceName updated', (updatedData) {
      try {
        T? object = fromJson(updatedData);
        eventBus.fire(FeathersJsEventData<T>(
            data: object, type: FeathersJsEventType.updated));
      } catch (e) {
        eventBus.fire(new FeatherJsError(
            type: FeatherJsErrorType.IS_DESERIALIZATION_ERROR, error: e));
      }
    });

    /// On patched event
    _socket.on('$serviceName patched', (patchedData) {
      try {
        T? object = fromJson(patchedData);
        eventBus.fire(FeathersJsEventData<T>(
            data: object, type: FeathersJsEventType.patched));
      } catch (e) {
        eventBus.fire(new FeatherJsError(
            type: FeatherJsErrorType.IS_DESERIALIZATION_ERROR, error: e));
      }
    });

    /// On removed event
    _socket.on('$serviceName removed', (removedData) {
      try {
        T? object = fromJson(removedData);
        eventBus.fire(FeathersJsEventData<T>(
            data: object, type: FeathersJsEventType.removed));
      } catch (e) {
        eventBus.fire(new FeatherJsError(
            type: FeatherJsErrorType.IS_DESERIALIZATION_ERROR, error: e));
      }
    });

    /// On created event
    _socket.on('$serviceName created', (createdData) {
      try {
        T? object = fromJson(createdData);
        eventBus.fire(FeathersJsEventData<T>(
            data: object, type: FeathersJsEventType.created));
      } catch (e) {
        eventBus.fire(new FeatherJsError(
            type: FeatherJsErrorType.IS_DESERIALIZATION_ERROR, error: e));
      }
    });
    return eventBus.on<FeathersJsEventData<T>>();
  }
}
