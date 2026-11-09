import 'dart:convert';
import 'dart:io';

class DataProto {
  late final int messageType;
  String? message = null;
  static const int ERROR_PARSING = -1;
  static const int PING = 0;
  static const int SEND = 1;
  static const int CONNECT = 2;
  (String?, int?) peer = (null, null);

  DataProto.fromJson(String jsonString) {
    try {
      final Map<String, Object?> jsonMap =
          jsonDecode(jsonString) as Map<String, Object?>;
      this.messageType = jsonMap['messageType'] as int;
      if (this.messageType == SEND) {
        this.message = jsonMap['message'] as String;
      } else if (this.messageType == CONNECT) {
        this.peer = (
          (jsonMap['peer'] as Map<String, dynamic>)['address'],
          (jsonMap['peer'] as Map<String, dynamic>)['port'],
        );
      }
    } catch (e) {
      this.messageType = ERROR_PARSING;
      print(e);
    }
  }
  DataProto.fromDatagram(Datagram datagram)
    : this.fromJson(utf8.decode(datagram.data));
}

sealed class DataResponseProto {
  late final int messageType;
  static const int ERROR = -1;
  static const int CONNECT = 1;
  static const int UPDATE_CLIENTS = 2;

  DataResponseProto(this.messageType);

  Map<String, dynamic> toJson();

  @override
  String toString() {
    return jsonEncode(this.toJson());
  }

  List<int> toBytes() {
    return utf8.encode(this.toString());
  }
}

class DataResponseErrorProto extends DataResponseProto {
  String error;

  DataResponseErrorProto(this.error) : super(DataResponseProto.ERROR);

  Map<String, dynamic> toJson() {
    return {"messageType": this.messageType, "error": this.error};
  }
}

class DataResponseConnectProto extends DataResponseProto {
  DateTime beginPing;
  DateTime endPing;
  ConnectionConfig peer;
  int role;
  static const int SERVER = 0;
  static const int CLIENT = 1;

  DataResponseConnectProto(this.beginPing, this.endPing, this.peer, this.role)
    : super(DataResponseProto.CONNECT);

  Map<String, dynamic> toJson() {
    return {
      "messageType": this.messageType,
      "peer": peer,
      "interval": {
        "begin": beginPing.toIso8601String(),
        "end": endPing.toIso8601String(),
      },
      "role": role,
    };
  }
}

class ConnectionConfig {
  String? address;
  int? port;
  ConnectionConfig(this.address, this.port);

  Map<String, dynamic> toJson() {
    return {"address": this.address, "port": this.port};
  }
}

class DataResponseUpdateProto extends DataResponseProto {
  List<ConnectionConfig> newClients = [];

  DataResponseUpdateProto(this.newClients)
    : super(DataResponseProto.UPDATE_CLIENTS);

  Map<String, dynamic> toJson() {
    return {"messageType": this.messageType, "clients": this.newClients};
  }
}
