import 'package:flutter/material.dart';
import 'package:p2p_client/communication_proto.dart';
import 'package:p2p_client/connection.dart';

import 'utils/validators.dart';

void main() {
  runApp(const P2PClientApp());
}

class P2PClientApp extends StatelessWidget {
  const P2PClientApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'P2P Client',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const ClientScreen(),
    );
  }
}

class ClientScreen extends StatefulWidget {
  const ClientScreen({super.key});

  @override
  State<ClientScreen> createState() => _ClientScreenState();
}

class _ClientScreenState extends State<ClientScreen> {
  final _serverIpController = TextEditingController(text: '127.0.0.1');
  final _serverPortController = TextEditingController(text: '8080');
  final _localPortController = TextEditingController(text: '8081');
  final _remoteIpController = TextEditingController(text: '127.0.0.1');
  final _remotePortController = TextEditingController(text: '8081');
  final _messageController = TextEditingController();
  bool _serverIsPinging = false;
  bool _clientIsPinging = false;
  ClientConnection client = ClientConnection((_) {});
  ServerConnection server = ServerConnection((_) {});

  _ClientScreenState() {
    server = ServerConnection((bool status) {
      setState(() {
        _serverIsPinging = status;
      });
    });
    client = ClientConnection((bool status) {
      setState(() {
        _clientIsPinging = status;
      });
    });
  }
  bool _allowConnection = true;
  bool _allowMessage = false;
  final _formKey = GlobalKey<FormState>();
  final _updatesScrollController = ScrollController();
  final List<String> _updates = ['Ready to connect.'];

  void setConnectionState(bool status) {
    _serverIsPinging = status;
  }

  @override
  void dispose() {
    _serverIpController.dispose();
    _serverPortController.dispose();
    _localPortController.dispose();
    _remoteIpController.dispose();
    _remotePortController.dispose();
    _messageController.dispose();
    _updatesScrollController.dispose();
    super.dispose();
  }

  void _addUpdate(String message) {
    setState(() {
      _updates.add('${TimeOfDay.now().format(context)}  $message');
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_updatesScrollController.hasClients) {
        return;
      }

      _updatesScrollController.jumpTo(
        _updatesScrollController.position.maxScrollExtent,
      );
    });
  }

  Widget _pingIndicator({required String label, required bool active}) {
    final color = active ? Colors.green : Colors.grey;
    return Chip(
      avatar: Icon(Icons.wifi, size: 16, color: color),
      label: Text(active ? 'Pinging $label' : '$label idle'),
      backgroundColor: color.withValues(alpha: active ? 0.15 : 0.08),
      side: BorderSide(color: color.withValues(alpha: 0.35)),
      visualDensity: VisualDensity.compact,
    );
  }

  void _connectToServer() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    setState(() {
      _allowConnection = false;
      _allowMessage = false;
    });
    client.disconnectFromClient();

    _addUpdate(
      'Connecting to ${_serverIpController.text}:${_serverPortController.text} '
      '(local port ${_localPortController.text})...',
    );

    final localPort = int.tryParse(_localPortController.text) ?? 8000;

    server
        .connectToServer(
          _serverIpController.text,
          int.tryParse(_serverPortController.text) ?? 8000,
          localPort,
          _addUpdate,
          (ConnectionConfig peer) {
            setState(() {
              _allowConnection = false;
              _allowMessage = false;
            });
            server.disconnectFromServer();
            client
                .connectToClient(
                  peer.address ?? '',
                  peer.port ?? 8000,
                  localPort,
                  _addUpdate,
                )
                .then((success) {
                  if (success) {
                    _addUpdate('Connected to ${peer.address}:${peer.port}');
                    setState(() {
                      _allowConnection = true;
                      _allowMessage = true;
                    });
                  } else {
                    _addUpdate(
                      'Could not connect to ${peer.address}:${peer.port}. Please reconnect to server.',
                    );
                    setState(() {
                      _allowConnection = true;
                    });
                  }
                });
          },
        )
        .then((success) {
          if (success) {
            _addUpdate(
              'Connected to ${_serverIpController.text}:${_serverPortController.text} ',
            );
            setState(() {
              _allowConnection = true;
            });
          } else {
            server.disconnectFromServer();
            _addUpdate(
              'Could not connect to ${_serverIpController.text}:${_serverPortController.text} ',
            );
            setState(() {
              _allowConnection = true;
            });
          }
        });
  }

  void _connectToPeer() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final remoteIp = _remoteIpController.text.trim();
    final remotePort = _remotePortController.text.trim();

    _addUpdate(
      'Requesting peer connection from server: $remoteIp:${int.tryParse(remotePort) ?? 8000}...',
    );
    server.connectToPeer(remoteIp, int.tryParse(remotePort) ?? 8000);

  }

  void _disconnect() {
    server.disconnectFromServer();
    client.disconnectFromClient();
    setState(() {
      _allowConnection = true;
      _allowMessage = false;
    });
    _addUpdate('Disconnected.');
  }

  void _sendMessage() {
    final message = _messageController.text.trim();
    if (message.isEmpty) {
      return;
    }

    _messageController.clear();
    bool success = client.sendMessage(message);
    if (success) {
      _addUpdate("Sent: $message");
    } else {
      _addUpdate("Failed to sende: $message");
    }
  }

  InputDecoration _inputDecoration(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      border: const OutlineInputBorder(),
      isDense: true,
    );
  }

  Widget _connectionCard({
    required String title,
    required String description,
    required List<Widget> fields,
    required VoidCallback onConnect,
    bool allowConnection = true,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(description),
            const SizedBox(height: 16),
            ...fields,
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: allowConnection ? onConnect : null,
              icon: const Icon(Icons.link),
              label: const Text('Connect'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('P2P Client'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 800;
              final connectionCards = [
                _connectionCard(
                  title: 'Server connection',
                  description: 'Configure the server and local listening port.',
                  fields: [
                    TextFormField(
                      controller: _serverIpController,
                      decoration: _inputDecoration('Server IP address'),
                      validator: required_validator,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _serverPortController,
                            decoration: _inputDecoration('Server port'),
                            keyboardType: TextInputType.number,
                            validator: port_validator,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _localPortController,
                            decoration: _inputDecoration('Local port'),
                            keyboardType: TextInputType.number,
                            validator: port_validator,
                          ),
                        ),
                      ],
                    ),
                  ],
                  onConnect: _connectToServer,
                  allowConnection: _allowConnection,
                ),
                _connectionCard(
                  title: 'Peer connection',
                  description: 'Connect directly to another peer.',
                  fields: [
                    TextFormField(
                      controller: _remoteIpController,
                      decoration: _inputDecoration('Remote IP address'),
                      validator: required_validator,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _remotePortController,
                      decoration: _inputDecoration('Remote port'),
                      keyboardType: TextInputType.number,
                      validator: port_validator,
                    ),
                  ],
                  onConnect: _connectToPeer,
                  allowConnection: _allowConnection,
                ),
              ];

              return SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1100),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Align(
                          alignment: Alignment.topRight,
                          child: Wrap(
                            spacing: 8,
                            children: [
                              _pingIndicator(
                                label: 'Server',
                                active: _serverIsPinging,
                              ),
                              _pingIndicator(
                                label: 'Client',
                                active: _clientIsPinging,
                              ),
                              OutlinedButton.icon(
                                onPressed: _disconnect,
                                icon: const Icon(Icons.link_off),
                                label: const Text('Disconnect'),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (isWide)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: connectionCards[0]),
                              const SizedBox(width: 16),
                              Expanded(child: connectionCards[1]),
                            ],
                          )
                        else
                          ...connectionCards,
                        const SizedBox(height: 8),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Connection updates',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                                const SizedBox(height: 12),
                                Container(
                                  height: 220,
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: ListView.builder(
                                    controller: _updatesScrollController,
                                    itemCount: _updates.length,
                                    itemBuilder: (context, index) => Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: SelectableText(_updates[index]),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: _messageController,
                                        decoration: _inputDecoration(
                                          'Message',
                                          hint: 'Type a message to send',
                                        ),
                                        onSubmitted: (_) => _sendMessage(),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    FilledButton.icon(
                                      onPressed: _allowMessage
                                          ? _sendMessage
                                          : null,
                                      icon: const Icon(Icons.send),
                                      label: const Text('Send'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
