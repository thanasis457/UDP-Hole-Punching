# UDP Hole Punching - POC

A peer-to-peer messaging project that uses a UDP coordination server to help
clients discover one another and establish direct UDP connections through NAT.

![UDP Hole Punching client](https://i.imgur.com/dWXLMad.png)

The repository contains two cooperating applications:

- [`coordination_server/`](./coordination_server): a Dart UDP coordinator and
  Python clients for testing the protocol.
- [`p2p_client/`](./p2p_client): a Flutter client for connecting to the
  coordinator and messaging with a peer.


The coordinator does not relay chat messages. It receives periodic heartbeats,
tracks active clients, advertises available peers, and introduces two selected
clients to one another. The clients then communicate directly over UDP.

UDP hole punching depends on the network's NAT and firewall behavior. A
successful connection to the coordinator does not guarantee that the direct
peer connection will succeed. This will fail under symmetric NAT.

## Requirements

- [Flutter](https://docs.flutter.dev/get-started/install) and Dart SDK
- Python 3 (3.10>= preferred) & required libraries (Tkinter, aiconsole) for the Python test scripts

## Quick start

### 1. Start the coordinator

```bash
cd coordination_server
dart run coordinator.dart
```

The coordinator listens for UDP traffic on port `8080` by default.

### 2. Start a client

#### Flutter client

```bash
cd p2p_client
flutter pub get
flutter run
```

In the application:

1. Set the coordinator address and port, typically `127.0.0.1:8080` locally.
2. Set an available local UDP port.
3. Click **Connect** in the **Server connection** card.
4. Server will notify with all available peers as they become available.
5. Enter the IP address and UDP port of the peer you want to connect to.
6. Click **Connect** in the **Peer connection** card.
7. Send messages after the direct peer connection is established.

## Protocol

Messages are JSON encoded and sent over UDP.

### Client to anyone: heartbeat

```json
{"messageType": 0}
```

### Client to coordinator: request connection to peer

```json
{
  "messageType": 2,
  "peer": {
    "address": "peer-ip-address",
    "port": 54325
  }
}
```

### Coordinator to client: new peer available

```json
{
  "messageType": 2,
  "clients": [
    {"address": "pee-ip-address", "port": 54325}
  ]
}
```

### Coordinator to client: signal to connect to peer

```json
{
  "messageType": 1,
  "peer": {
    "address": "peer-ip-address",
    "port": 54325
  }
}
```

### Client to client: Peer message

```json
{
  "messageType": 1,
  "message": "hello"
}
```

The protocol is a simple JSON-over-UDP protocol. It does not provide
authentication or encryption.

## Network configuration

The coordinator must be reachable over UDP on port `8080` unless the port is
changed in [`coordinator.dart`](./coordination_server/coordinator.dart) and in
the clients. Ideally the coordinator is a third-party server accessible by all clients.