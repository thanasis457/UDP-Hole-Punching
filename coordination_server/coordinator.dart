import 'dart:async';
import 'dart:io';
import 'dart:core';

import 'globals.dart';
import 'CommunicationProto.dart';
import 'helper.dart';

void main() async {
  // Read the current time from an NTP server.
  serverSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 8080)
    ..writeEventsEnabled = false;

  print("LISTENING on :8080");
  serverSocket.listen((event) {
    switch (event) {
      case RawSocketEvent.read:
        final datagram = serverSocket.receive();
        handleNewClient(datagram);

        if (datagram == null) break;
        final DataProto request = DataProto.fromDatagram(datagram);

        if (request.messageType == DataProto.PING) {}
        if (request.messageType == DataProto.CONNECT) {
          Client? dest = null;
          for (final d in activeClients) {
            if (d.ip == request.peer.$1 &&
                d.ip != null &&
                d.port == request.peer.$2 &&
                d.port != null) {
              dest = d;
              break;
            }
          }
          if (dest == null) {
            serverSocket.send(
              DataResponseErrorProto("Could not find peer").toBytes(),
              datagram.address,
              datagram.port,
            );
            break;
          }
          final DataResponseProto pingIntervalDest = DataResponseConnectProto(
            DateTime.now().add(Duration(seconds: 1)),
            DateTime.now().add(Duration(seconds: 5)),
            ConnectionConfig(dest.ip, dest.port),
            DataResponseConnectProto.SERVER,
          );
          final DataResponseProto pingIntervalSource = DataResponseConnectProto(
            DateTime.now().add(Duration(seconds: 1)),
            DateTime.now().add(Duration(seconds: 5)),
            ConnectionConfig(datagram.address.address, datagram.port),
            DataResponseConnectProto.CLIENT,
          );

          // Clients might disconnect now
          serverSocket.send(
            pingIntervalDest.toBytes(),
            datagram.address,
            datagram.port,
          );
          serverSocket.send(
            pingIntervalSource.toBytes(),
            InternetAddress(dest.ip ?? "noipprovided"),
            dest.port ?? 0,
          );
        }

        break;
      case RawSocketEvent.write:
        // clientSocket.send(ntpQuery, serverAddress, 123) > 0;
        break;
      case RawSocketEvent.closed:
        print("STOPPING LISTENING");
        break;
      default:
        throw "Unexpected event $event";
    }
  });
}

/// Stores the new client or updates old client's alive timer.
void handleNewClient(Datagram? datagram) {
  // Find existing client and reset timer
  final Client newClient = Client.persistent(
    datagram?.address.address,
    datagram?.port,
  );
  Client? found = activeClients.lookup(newClient);

  if (found != null) {
    print("Renewing timer");
    final timer = Timer(const Duration(seconds: 10), () {
      activeClients.remove(found);
      broadcast();
      print("Removing client");
    });
    if (found.aliveTimer == null) {
      print("Possible problem. Alive Timer should never be null");
    }
    found.aliveTimer?.cancel();
    found.aliveTimer = timer;
  }
  // Add new client
  else if (found == null) {
    final timer = Timer(const Duration(seconds: 10), () {
      activeClients.remove(newClient);
      broadcast();
      print("Removing client");
    });
    newClient.aliveTimer = timer;
    activeClients.add(newClient);
    broadcast();
    print("Adding new client");
    print(newClient.ip);
  }
}

// TODO: Sever sent events need to go through the write event cycle
