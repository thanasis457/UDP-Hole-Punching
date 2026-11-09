import 'dart:io';
import 'globals.dart';
import 'CommunicationProto.dart';

void broadcast([List<WebSocket>? clients]) {
    // Tell client about available clients
    List<ConnectionConfig> _clientIps = [];
    for (final elem in activeClients) {
      _clientIps.add(ConnectionConfig(elem.ip, elem.port));
    }
    DataResponseProto response = DataResponseUpdateProto(_clientIps);

    if (clients != null) {
      for (final client in clients) {
        client.add(response.toString());
      }
    } else {
      for (final client in activeClients) {
        serverSocket.send(response.toBytes(), InternetAddress(client.ip ?? "noipprovided"), client.port ?? 0);
      }
    }
  }