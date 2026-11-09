# UDP Coordination Server

A small UDP coordination service and Python client for establishing peer-to-peer communication.

The coordinator tracks active clients, sends peer availability updates, and introduces two clients to each other. The Python client then sends UDP heartbeats and exchanges JSON messages with the selected peer.

## Project Files

- `coordinator.dart`: Dart UDP coordination server.
- `CommunicationProto.dart`: Coordinator request and response formats.
- `globals.dart`: Active-client state and timers.
- `helper.dart`: Peer availability broadcasts.
- `client.py`: Python client and reusable `ClientConnection` class.
- `client_ui.py`: Tkinter UI built around `ClientConnection` from `client.py`.

## Requirements

- Python 3
- The `aioconsole` Python package for the terminal client
- Tkinter for the graphical UI
- Dart SDK for the coordinator

Install the Python dependency in the project environment:

```bash
/Users/thanasis/micromamba/envs/New_env/bin/python -m pip install aioconsole
```

On macOS, Tkinter is normally included with the Python distribution. If the UI cannot import `tkinter`, install a Python distribution that includes Tk support.

## Start the Coordinator

The coordinator listens for UDP traffic on port `8080`:

```bash
dart run coordinator.dart
```

You should see:

```text
LISTENING on :8080
```

The coordinator must be reachable by the clients. If it is behind a router or cloud firewall, allow UDP traffic on port `8080`.

## Start the Graphical Client

Run the UI with the project interpreter:

```bash
/Users/thanasis/micromamba/envs/New_env/bin/python client_ui.py
```

In the window:

1. Enter the coordinator address and port.
2. Enter a local UDP port.
3. Click **Connect**.
4. Enter the target peer address and port shown by the coordinator.
5. Click **Request peer**.
6. After the peer connection is established, use the message field to send JSON chat messages.

The activity log displays coordinator peer updates, connection events, received messages, and errors.

## Start the Terminal Client

```bash
/Users/thanasis/micromamba/envs/New_env/bin/python client.py
```

The default values are defined at the top of `client.py`:

```python
SOURCE_PORT = 54325
DEST_ADDR = "34.173.254.68"
DEST_PORT = 8080
```

The UI imports these defaults from `client.py`, so changing them there changes the UI defaults too.

## Connection Flow

```text
Python client
    |
    | UDP heartbeat and peer request
    v
Coordinator
    |
    | peer update and connection response
    v
Python client A <---- UDP ----> Python client B
```

The client performs these steps:

1. Bind a local UDP port.
2. Connect to the coordinator.
3. Send heartbeat messages with `messageType: 0`.
4. Receive peer availability updates.
5. Request a selected peer with `messageType: 2`.
6. Receive a connection response with `messageType: 1`.
7. Close the coordinator socket.
8. Open a UDP socket to the peer.
9. Exchange heartbeat and message packets.

## Message Types

### Client to coordinator: heartbeat

```json
{"messageType": 0}
```

### Client to coordinator: request a peer

```json
{
  "messageType": 2,
  "peer": {
    "ip": "peer-address",
    "port": 54325
  }
}
```

### Coordinator to client: peer update

```json
{
  "messageType": 2,
  "clients": [
    {"address": "peer-address", "port": 54325}
  ]
}
```

### Coordinator to client: connection response

```json
{
  "messageType": 1,
  "peer": {
    "address": "peer-address",
    "port": 54325
  },
  "role": 0
}
```

A role of `0` listens for peer messages. A role of `1` sends messages through the client/UI.

### Peer message

```json
{
  "messageType": 1,
  "message": "hello"
}
```

## Networking Notes

This project uses UDP hole punching. The coordinator records the public address and source port from incoming packets and advertises those values to peers.

If both clients are on the same local network, connecting through the router's public IP requires NAT loopback or hairpin NAT support. If the router does not support it:

- Test with each client on a different network, such as a phone hotspot.
- Use private LAN addresses for peers on the same network.
- Confirm UDP port forwarding and firewall rules.
- Keep the heartbeat interval active so NAT mappings do not expire.

A successful coordinator connection does not guarantee that the direct peer connection will succeed.

## Development Checks

Compile the Python files with the project interpreter:

```bash
python -m py_compile client.py client2.py client_ui.py
```

Import the UI without launching it:

```bash
python -c "import client_ui; print('UI import ok')"
```
