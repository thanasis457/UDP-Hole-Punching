import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:core';

import 'communication_proto.dart';

import 'package:flutter/foundation.dart';

class ServerConnection {
  RawDatagramSocket? _serverSocket;
  String _remoteIp = '';
  int _remotePort = 8000;
  int localPort = 8000;

  void Function(String) _sendUpdate = (_) => '';
  void Function(ConnectionConfig) _onPeerRequest = (_) => '';
  final void Function(bool active) _setConnectionStatus;

  ServerConnection(void Function(bool active) onConnectionChange)
    : _setConnectionStatus = onConnectionChange;

  Timer? _pingTimer;

  Future<bool> connectToServer(
    String remoteIp,
    int remotePort,
    int localPort,
    void Function(String) sendUpdate,
    void Function(ConnectionConfig) onPeerRequest,
  ) async {
    try {
      disconnectFromServer();

      _sendUpdate = sendUpdate;
      _onPeerRequest = onPeerRequest;
      _serverSocket =
          await RawDatagramSocket.bind(
              "0.0.0.0",
              localPort,
              reuseAddress: true,
              reusePort: true,
            )
            ..writeEventsEnabled = false;

      _remoteIp = remoteIp;
      _remotePort = remotePort;
      this.localPort = localPort;
      if (_listen() && _startPinging()) {
        _setConnectionStatus(true);
      } else {
        throw "Listening or pinging failed";
      }
    } catch (e) {
      disconnectFromServer();
      sendUpdate("Could not connect to server: $e");
      return false;
    }
    return true;
  }

  bool connectToPeer(String remoteIp, int remotePort) {
    try {
      final payload = DataProtoClientToServer(
        DataProtoClientToServer.CONNECT,
        ConnectionConfig(remoteIp, remotePort),
      );
      int? bytes = _serverSocket?.send(
        payload.toBytes(),
        InternetAddress(_remoteIp),
        _remotePort,
      );

      if ((bytes ?? 0) <= 0) {
        throw "Could not send peer request";
      }
    } catch (e) {
      _sendUpdate("Could not connect to server: $e");
      return false;
    }
    return true;
  }

  bool disconnectFromServer() {
    try {
      if (_serverSocket == null) {
        _pingTimer?.cancel();
        return true;
      }
      _pingTimer?.cancel();
      _serverSocket?.close();
      _remoteIp = '';
      _remotePort = 8000;
      _serverSocket = null;
    } catch (e) {
      _sendUpdate("Could not disconnect from server: $e");
      if (_pingTimer?.isActive ?? false == false) {
        _setConnectionStatus(false);
      }
      return false;
    }
    _setConnectionStatus(false);
    _sendUpdate("Diconnected from server");
    return true;
  }

  bool _startPinging() {
    final payload = DataProtoClientToServer(DataProtoClientToServer.PING);

    void ping(Timer timer) {
      if (_serverSocket == null) {
        return;
      }
      try {
        int? bytes = _serverSocket?.send(
          payload.toBytes(),
          InternetAddress(_remoteIp),
          _remotePort,
        );

        if ((bytes ?? 0) <= 0) {
          throw "Could not ping";
        }
      } catch (e) {
        _sendUpdate("Could not ping");
        disconnectFromServer();
      }
    }

    if (_serverSocket == null) {
      return false;
    }

    int? bytes = _serverSocket?.send(
      payload.toBytes(),
      InternetAddress(_remoteIp),
      _remotePort,
    );

    if ((bytes ?? 0) <= 0) {
      throw "Could not ping";
    }
    _pingTimer = Timer.periodic(Duration(seconds: 5), ping);
    return true;
  }

  bool _listen() {
    try {
      if (_serverSocket == null) {
        return false;
      }

      _serverSocket?.listen((event) {
        if (_serverSocket == null) return;
        switch (event) {
          case RawSocketEvent.read:
            final datagram = _serverSocket?.receive();
            if (datagram == null) break;
            final request = DataProtoServerToClient.fromDatagram(datagram);
            if (request is DataErrorProtoServerToClient) {
              _sendUpdate("Server errored: ${request.error}");
            }

            if (request is DataUpdateProtoServerToClient) {
              _sendUpdate("Server gave new clients: ${request.newClients}");
            }

            if (request is DataConnectProtoServerToClient) {
              _sendUpdate(
                "Server is trying to connect us to peer: ${request.peer}",
              );
              _onPeerRequest(request.peer);
            }

            break;
          case RawSocketEvent.write:
            // clientSocket.send(ntpQuery, serverAddress, 123) > 0;
            break;
          case RawSocketEvent.closed:
            if (kDebugMode) {
              print("STOPPING LISTENING TO SERVER");
            }
            break;
          default:
            throw "Unexpected event $event";
        }
      });
    } catch (e) {
      return false;
    }
    return true;
  }
}

class ClientConnection {
  RawDatagramSocket? _clientSocket;
  String _remoteIp = '';
  int _remotePort = 8000;
  final void Function(bool active) _setConnectionStatus;
  ClientConnection(void Function(bool active) onConnectionChange)
    : _setConnectionStatus = onConnectionChange;
  void Function(String) _sendUpdate = (_) => '';

  Timer? _pingTimer;

  Future<bool> connectToClient(
    String remoteIp,
    int remotePort,
    int localPort,
    void Function(String) sendUpdate,
  ) async {
    try {
      disconnectFromClient();

      _sendUpdate = sendUpdate;
      _clientSocket =
          await RawDatagramSocket.bind(
              InternetAddress.anyIPv4,
              localPort,
              reuseAddress: true,
              reusePort: true,
            )
            ..writeEventsEnabled = false;

      _remoteIp = remoteIp;
      _remotePort = remotePort;
      if (_listen() && _startPinging()) {
        _setConnectionStatus(true);
      } else {
        throw "Listening or pinging failed";
      }
    } catch (e) {
      disconnectFromClient();
      sendUpdate("Could not connect to client: $e");
      return false;
    }
    return true;
  }

  bool disconnectFromClient() {
    try {
      if (_clientSocket == null) {
        _pingTimer?.cancel();
        return true;
      }
      _pingTimer?.cancel();
      _clientSocket?.close();
      _remoteIp = '';
      _remotePort = 8000;
      _clientSocket = null;
    } catch (e) {
      _sendUpdate("Could not disconnect from client: $e");
      if (_pingTimer?.isActive ?? false == false) {
        _setConnectionStatus(false);
      }
      return false;
    }
    _sendUpdate("Diconnected from client");
    _setConnectionStatus(false);
    return true;
  }

  bool sendMessage(String message) {
    try {
      int? bytes = _clientSocket?.send(
        DataProtoClientToClient.message(message).toBytes(),
        InternetAddress(_remoteIp),
        _remotePort,
      );

      if ((bytes ?? 0) <= 0) {
        throw "Could not send message";
      }
    } catch (e) {
      return false;
    }
    return true;
  }

  bool _startPinging() {
    final payload = DataProtoClientToClient.ping();

    void ping(Timer timer) {
      if (_clientSocket == null) {
        return;
      }
      try {
        int? bytes = _clientSocket?.send(
          payload.toBytes(),
          InternetAddress(_remoteIp),
          _remotePort,
        );

        if ((bytes ?? 0) <= 0) {
          throw "Could not ping";
        }
      } catch (e) {
        _sendUpdate("Could not ping");
        disconnectFromClient();
      }
    }

    if (_clientSocket == null) {
      return false;
    }

    // Hole punch
    try {
      _clientSocket?.send(
        payload.toBytes(),
        InternetAddress(_remoteIp),
        _remotePort,
      );
    } catch (e) {
      if (kDebugMode) {
        print("UDP packet dropped. Expected for hole punching");
      }
    }
    _pingTimer = Timer.periodic(Duration(seconds: 5), ping);
    return true;
  }

  bool _listen() {
    try {
      if (_clientSocket == null) {
        return false;
      }

      _clientSocket?.listen((event) {
        if (_clientSocket == null) return;
        switch (event) {
          case RawSocketEvent.read:
            final datagram = _clientSocket?.receive();
            if (datagram == null) break;
            final request = DataProtoClientToClient.fromDatagram(datagram);
            if (request.messageType == DataProtoClientToClient.PING) {
              // _sendUpdate("Peer pinged");
            }

            if (request.messageType == DataProtoClientToClient.MESSAGE) {
              _sendUpdate("Peer texted: ${request.message}");
            }

            break;
          case RawSocketEvent.write:
            // clientSocket.send(ntpQuery, serverAddress, 123) > 0;
            break;
          case RawSocketEvent.closed:
            if (kDebugMode) {
              print("STOPPING LISTENING TO PEER");
            }
            break;
          default:
            throw "Unexpected event $event";
        }
      });
    } catch (e) {
      return false;
    }
    return true;
  }
}
