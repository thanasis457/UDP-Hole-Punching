// ignore_for_file: constant_identifier_names

import 'dart:convert';
import 'dart:io';

/// Messages sent from a client to the server.
class DataProtoClientToServer {
  final int messageType;
  ConnectionConfig? peer;

  static const int PING = 0;
  static const int SEND = 1;
  static const int CONNECT = 2;

  DataProtoClientToServer(this.messageType, [this.peer]);

  Map<String, dynamic> toJson() {
    return {
      'messageType': messageType,
      if (peer != null) 'peer': peer!.toJson(),
    };
  }

  String toJsonString() => jsonEncode(toJson());

  List<int> toBytes() => utf8.encode(toJsonString());

  @override
  String toString() => toJsonString();
}

/// Base type for every message received from the server.
///
/// Use [DataProtoServerToClient.fromJson] or [fromDatagram] to get the
/// appropriate typed response. For example:
///
/// ```dart
/// final response = DataProtoServerToClient.fromJson(text);
/// if (response is DataUpdateProtoServerToClient) {
///   print(response.newClients);
/// }
/// ```
class DataProtoServerToClient {
  final int messageType;

  static const int ERROR = -1;
  static const int CONNECT = 1;
  static const int UPDATE_CLIENTS = 2;

  const DataProtoServerToClient(this.messageType);

  factory DataProtoServerToClient.fromJson(String jsonString) {
    final json = _decodeObject(jsonString);
    final messageType = _requiredInt(json, 'messageType');

    switch (messageType) {
      case ERROR:
        return DataErrorProtoServerToClient(_requiredString(json, 'error'));
      case CONNECT:
        return DataConnectProtoServerToClient.fromJsonMap(json);
      case UPDATE_CLIENTS:
        return DataUpdateProtoServerToClient.fromJsonMap(json);
      default:
        return DataProtoServerToClient(messageType);
    }
  }

  factory DataProtoServerToClient.fromDatagram(Datagram datagram) {
    return DataProtoServerToClient.fromJson(utf8.decode(datagram.data));
  }

  Map<String, dynamic> toJson() => {'messageType': messageType};

  String toJsonString() => jsonEncode(toJson());

  List<int> toBytes() => utf8.encode(toJsonString());

  @override
  String toString() => toJsonString();
}

class DataErrorProtoServerToClient extends DataProtoServerToClient {
  final String error;

  DataErrorProtoServerToClient(this.error)
    : super(DataProtoServerToClient.ERROR);

  factory DataErrorProtoServerToClient.fromJson(String jsonString) {
    final json = _decodeObject(jsonString);
    return DataErrorProtoServerToClient(_requiredString(json, 'error'));
  }

  @override
  Map<String, dynamic> toJson() {
    return {'messageType': messageType, 'error': error};
  }
}

class DataConnectProtoServerToClient extends DataProtoServerToClient {
  final DateTime beginPing;
  final DateTime endPing;
  final ConnectionConfig peer;
  final int role;

  static const int SERVER = 0;
  static const int CLIENT = 1;

  DataConnectProtoServerToClient(
    this.beginPing,
    this.endPing,
    this.peer,
    this.role,
  ) : super(DataProtoServerToClient.CONNECT);

  factory DataConnectProtoServerToClient.fromJson(String jsonString) {
    return DataConnectProtoServerToClient.fromJsonMap(
      _decodeObject(jsonString),
    );
  }

  factory DataConnectProtoServerToClient.fromJsonMap(
    Map<String, dynamic> json,
  ) {
    final interval = _requiredObject(json, 'interval');
    return DataConnectProtoServerToClient(
      DateTime.parse(_requiredString(interval, 'begin')),
      DateTime.parse(_requiredString(interval, 'end')),
      ConnectionConfig.fromJson(_requiredObject(json, 'peer')),
      _requiredInt(json, 'role'),
    );
  }

  Duration get pingDuration => endPing.difference(beginPing);

  @override
  Map<String, dynamic> toJson() {
    return {
      'messageType': messageType,
      'peer': peer.toJson(),
      'interval': {
        'begin': beginPing.toIso8601String(),
        'end': endPing.toIso8601String(),
      },
      'role': role,
    };
  }
}

class ConnectionConfig {
  final String? address;
  final int? port;

  const ConnectionConfig(this.address, this.port);

  factory ConnectionConfig.fromJson(Map<String, dynamic> json) {
    final address = json['address'];
    final port = json['port'];
    if (address != null && address is! String) {
      throw const FormatException('Connection address must be a string');
    }
    if (port != null && port is! int) {
      throw const FormatException('Connection port must be an integer');
    }
    return ConnectionConfig(address as String?, port as int?);
  }

  Map<String, dynamic> toJson() {
    return {'address': address, 'port': port};
  }

  @override
  String toString() => '${address ?? '<unknown>'}:${port ?? '<unknown>'}';
}

class DataUpdateProtoServerToClient extends DataProtoServerToClient {
  final List<ConnectionConfig> newClients;

  DataUpdateProtoServerToClient(List<ConnectionConfig> newClients)
    : newClients = List.unmodifiable(newClients),
      super(DataProtoServerToClient.UPDATE_CLIENTS);

  factory DataUpdateProtoServerToClient.fromJson(String jsonString) {
    return DataUpdateProtoServerToClient.fromJsonMap(_decodeObject(jsonString));
  }

  factory DataUpdateProtoServerToClient.fromJsonMap(Map<String, dynamic> json) {
    final clients = json['clients'];
    if (clients is! List) {
      print(json);
      throw const FormatException('Expected clients to be a list');
    }
    return DataUpdateProtoServerToClient(
      clients.map((client) {
        if (client is! Map) {
          throw const FormatException('Each client must be an object');
        }
        return ConnectionConfig.fromJson(Map<String, dynamic>.from(client));
      }).toList(),
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'messageType': messageType,
      'clients': newClients.map((client) => client.toJson()).toList(),
    };
  }
}

Map<String, dynamic> _decodeObject(String jsonString) {
  final decoded = jsonDecode(jsonString);
  if (decoded is! Map) {
    throw const FormatException('Protocol message must be a JSON object');
  }
  return Map<String, dynamic>.from(decoded);
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String) {
    throw FormatException('Protocol field "$key" must be a string');
  }
  return value;
}

int _requiredInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! int) {
    throw FormatException('Protocol field "$key" must be an integer');
  }
  return value;
}

Map<String, dynamic> _requiredObject(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! Map) {
    throw FormatException('Protocol field "$key" must be an object');
  }
  return Map<String, dynamic>.from(value);
}

class DataProtoClientToClient {
  int messageType = 0;

  static final int PING = 0;
  static final int MESSAGE = 1;
  String? message;

  DataProtoClientToClient.ping() : messageType = PING, message = null;
  DataProtoClientToClient.message(this.message) : messageType = MESSAGE;
  Map<String, dynamic> toJson() => {
    'messageType': messageType,
    'message': message,
  };
  String toJsonString() => jsonEncode(toJson());

  List<int> toBytes() => utf8.encode(toJsonString());

  DataProtoClientToClient.fromJson(String jsonString) {
    Map<String, dynamic> json = _decodeObject(jsonString);
    message = json['message'] as String?;
    messageType = json['messageType'] as int;
  }
  DataProtoClientToClient.fromDatagram(Datagram datagram)
    : this.fromJson(utf8.decode(datagram.data));
}
