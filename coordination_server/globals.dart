
import 'dart:async';
import 'dart:io';

class Client {
  final String? ip;
  final int? port;
  Timer? aliveTimer;
  
  Client(this.ip, this.port, this.aliveTimer);
  
  Client.persistent(String? ip, int? port): this(ip, port, null);

  @override
  bool operator ==(Object other) => other is Client && other.ip == this.ip && other.port == other.port;

  @override
  int get hashCode => ip.hashCode * port.hashCode;
}

final Set<Client> activeClients = Set();

late final RawDatagramSocket serverSocket;