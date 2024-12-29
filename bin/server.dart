import 'dart:async';
import 'dart:convert';
import 'dart:io';

// class Player {
//   final String name;
//   final InternetAddress address;
//   final int port;
//   final Map<String, dynamic> position;
//   final String color;

//   String get key => '${address.address}:$port';

//   const Player._({
//     required this.name,
//     required this.position,
//     required this.address,
//     required this.port,
//     required this.color,
//   });

//   factory Player({
//     required String name,
//     required Map<String, dynamic> position,
//     String color = '#000000',
//   }) {
//     return Player._(
//       name: name,
//       address: InternetAddress.anyIPv4,
//       port: 0,
//       position: position,
//       color: color,
//     );
//   }

//   Map<String, dynamic> toMap() {
//     return {
//       'name': name,
//       'address': address.address,
//       'port': port,
//       'position': position,
//       'color': color,
//     };
//   }

//   Player copyWith({
//     String? name,
//     InternetAddress? address,
//     int? port,
//     Map<String, dynamic>? position,
//     String? color,
//   }) {
//     return Player._(
//       name: name ?? this.name,
//       address: address ?? this.address,
//       port: port ?? this.port,
//       position: position ?? this.position,
//       color: color ?? this.color,
//     );
//   }

//   @override
//   String toString() {
//     return jsonEncode(toMap());
//   }
// }

class GameServer {
  late RawDatagramSocket socket;
  final Map<String, Player> players = {};

  // Adicione configuração de porta
  final int port;

  GameServer({this.port = 3000});

  Future<void> start() async {
    try {
      // Pegar porta do ambiente do Render
      final port = int.parse(Platform.environment['PORT'] ?? '3000');

      print('\n=== Servidor UDP ===');
      print('Iniciando servidor na porta: $port');

      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, port,
          reuseAddress: true);

      socket.broadcastEnabled = true;

      print('''
\n🎮 Servidor rodando!
📡 Endereço: ${socket.address.address}
🔌 Porta: ${socket.port}
''');

      // Logging para debug no Render
      print('Variáveis de ambiente:');
      Platform.environment.forEach((key, value) {
        if (!key.toLowerCase().contains('secret')) {
          print('$key: $value');
        }
      });

      print('Servidor iniciado com sucesso!');

      // Adicione tratamento de erros
      socket.handleError((error) {
        print('Erro no socket: $error');
      });

      socket.listen(_handleMessage, onError: (error) {
        print('Erro ao receber mensagem: $error');
      }, cancelOnError: false);
    } catch (e) {
      print('Erro ao iniciar servidor: $e');
      rethrow;
    }
  }

  void _handleMessage(RawSocketEvent event) {
    try {
      final datagram = socket.receive();
      if (datagram == null) return;

      final action = utf8.decode(datagram.data).trim();
      final json = jsonDecode(action);

      final player = Player(
        name: json['name'],
        position: json['position'],
      ).copyWith(
        address: datagram.address,
        port: datagram.port,
        color: json['color'],
      );

      players[player.key] = player;

      // Broadcast para todos os jogadores
      _broadcastPlayerState(player);
    } catch (e) {
      print('Erro ao processar mensagem: $e');
    }
  }

  void _broadcastPlayerState(Player player) {
    try {
      for (final playerItem in players.values) {
        socket.send(
          utf8.encode(player.toString()),
          InternetAddress.anyIPv4,
          playerItem.port!,
        );
      }
    } catch (e) {
      print('Erro ao fazer broadcast: $e');
    }
  }

  void stop() {
    try {
      socket.close();
      print('Servidor encerrado');
    } catch (e) {
      print('Erro ao encerrar servidor: $e');
    }
  }
}

void main(List<String> args) async {
  final server = GameServer();

  await server.start();
  teste();
}

// Exemplo de uso:
void teste() async {
  final client = GameClient(
    serverHost: 'seu-servidor.onrender.com', // Substitua pelo seu servidor
    serverPort: 10000, // Substitua pela sua porta
    playerName: 'EdsonMello-${DateTime.now().millisecondsSinceEpoch}',
    onPositionUpdate: (position) {
      print('📍 Posição atualizada: $position');
    },
    onPlayerJoined: (name) {
      print('👋 Jogador entrou: $name');
    },
    onPlayerLeft: (name) {
      print('👋 Jogador saiu: $name');
    },
    onConnectionStatus: (status) {
      print('🔌 Status: $status');
    },
    onError: (error) {
      print('❌ Erro: $error');
    },
    initialPosition: Position(x: 0, y: 0),
  );

  try {
    print('\n=== Iniciando Cliente de Jogo ===');
    print('Data: ${DateTime.now().toUtc()}');
    print('Player: ${client.playerName}');

    await client.connect();

    // Exemplo de atualização de posição
    await Future.delayed(Duration(seconds: 2));
    client.updatePosition(Position(x: 10, y: 20));

    // Manter o programa rodando
    print('\nCliente rodando. Pressione Ctrl+C para sair...');
    await Future.delayed(Duration(days: 1));
  } catch (e) {
    print('❌ Erro fatal: $e');
  }
}

class Position {
  final double x;
  final double y;

  Position({required this.x, required this.y});

  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
      };

  factory Position.fromJson(Map<String, dynamic> json) {
    return Position(
      x: json['x']?.toDouble() ?? 0.0,
      y: json['y']?.toDouble() ?? 0.0,
    );
  }

  @override
  String toString() => '(x: $x, y: $y)';
}

class Player {
  final String name;
  Position position;
  final String color;
  InternetAddress? address;
  int? port;

  Player({
    required this.name,
    required this.position,
    this.color = '#ffffff',
    this.address,
    this.port,
  });

  // Getter para criar uma chave única para o player
  String get key => '${address?.address}:$port';

  // Método para criar uma cópia do player com novos valores
  Player copyWith({
    String? name,
    Position? position,
    String? color,
    InternetAddress? address,
    int? port,
  }) {
    return Player(
      name: name ?? this.name,
      position: position ?? this.position,
      color: color ?? this.color,
      address: address ?? this.address,
      port: port ?? this.port,
    );
  }

  // Converter para JSON
  Map<String, dynamic> toJson() => {
        'name': name,
        'position': position.toJson(),
        'color': color,
        'address': address?.address,
        'port': port,
      };

  // Criar a partir de JSON
  factory Player.fromJson(Map<String, dynamic> json) {
    return Player(
      name: json['name'] as String,
      position: Position.fromJson(json['position'] as Map<String, dynamic>),
      color: json['color'] as String? ?? '#ffffff',
      port: json['port'] as int?,
      address: json['address'] != null
          ? InternetAddress(json['address'] as String)
          : null,
    );
  }

  // Representação em string
  @override
  String toString() {
    return jsonEncode(toJson());
  }
}

enum ConnectionStatus { disconnected, connecting, connected, error }

class GameClient {
  final String serverHost;
  final int serverPort;
  final String playerName;
  Position _position;
  RawDatagramSocket? _socket;
  Timer? _pingTimer;
  Timer? _reconnectionTimer;
  ConnectionStatus _status = ConnectionStatus.disconnected;
  final _reconnectInterval = Duration(seconds: 5);
  final _pingInterval = Duration(seconds: 3);

  // Callbacks
  final void Function(Position)? onPositionUpdate;
  final void Function(String)? onPlayerJoined;
  final void Function(String)? onPlayerLeft;
  final void Function(String)? onConnectionStatus;
  final void Function(String)? onError;

  GameClient({
    required this.serverHost,
    required this.serverPort,
    required this.playerName,
    this.onPositionUpdate,
    this.onPlayerJoined,
    this.onPlayerLeft,
    this.onConnectionStatus,
    this.onError,
    Position? initialPosition,
  }) : _position = initialPosition ?? Position(x: 0, y: 0);

  bool get isConnected => _status == ConnectionStatus.connected;
  Position get position => _position;

  Future<void> connect() async {
    if (_status == ConnectionStatus.connected) {
      _log('Já está conectado ao servidor');
      return;
    }

    try {
      _status = ConnectionStatus.connecting;
      _log('Iniciando conexão com $serverHost:$serverPort');
      onConnectionStatus?.call('Conectando...');

      // Resolver endereço do servidor
      final serverAddresses = await InternetAddress.lookup(serverHost)
          .timeout(Duration(seconds: 5));

      if (serverAddresses.isEmpty) {
        throw Exception('Não foi possível resolver o endereço $serverHost');
      }

      _log('Endereço resolvido: ${serverAddresses.first.address}');

      // Criar socket
      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        0,
        reuseAddress: true,
      );

      _log('Socket local criado na porta ${_socket!.port}');

      // Configurar listeners
      _socket!.listen(
        _handleSocketEvent,
        onError: _handleSocketError,
        onDone: _handleSocketDone,
        cancelOnError: false,
      );

      // Enviar mensagem de conexão
      _sendToServer({
        'type': 'connect',
        'name': playerName,
        'position': _position.toJson(),
        'timestamp': DateTime.now().toIso8601String(),
      });

      _status = ConnectionStatus.connected;
      onConnectionStatus?.call('Conectado');

      // Iniciar ping
      _startPingTimer();
    } catch (e, stack) {
      _log('Erro ao conectar: $e\n$stack');
      onError?.call('Erro ao conectar: $e');
      _handleDisconnect();
      rethrow;
    }
  }

  void _handleSocketEvent(RawSocketEvent event) {
    switch (event) {
      case RawSocketEvent.read:
        if (_socket != null) {
          final datagram = _socket!.receive();
          if (datagram != null) {
            _handleServerMessage(datagram);
          }
        }
        break;
      case RawSocketEvent.closed:
        _handleDisconnect();
        break;
      default:
        break;
    }
  }

  void _handleServerMessage(Datagram datagram) {
    try {
      final message = utf8.decode(datagram.data);
      final data = jsonDecode(message);

      switch (data['type']) {
        case 'position_update':
          if (data['position'] != null) {
            final newPosition = Position.fromJson(data['position']);
            _position = newPosition;
            onPositionUpdate?.call(newPosition);
          }
          break;
        case 'player_joined':
          if (data['name'] != null) {
            onPlayerJoined?.call(data['name']);
          }
          break;
        case 'player_left':
          if (data['name'] != null) {
            onPlayerLeft?.call(data['name']);
          }
          break;
        case 'pong':
          // Servidor respondeu ao ping
          break;
        default:
          _log('Mensagem desconhecida: $message');
      }
    } catch (e) {
      _log('Erro ao processar mensagem: $e');
    }
  }

  void _handleSocketError(error) {
    _log('Erro no socket: $error');
    onError?.call('Erro na conexão: $error');
    _handleDisconnect();
  }

  void _handleSocketDone() {
    _log('Conexão finalizada pelo servidor');
    _handleDisconnect();
  }

  void _handleDisconnect() {
    _status = ConnectionStatus.disconnected;
    onConnectionStatus?.call('Desconectado');
    _stopPingTimer();
    _socket?.close();
    _socket = null;
    _startReconnectionTimer();
  }

  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(_pingInterval, (timer) {
      if (isConnected) {
        _sendToServer({
          'type': 'ping',
          'name': playerName,
          'timestamp': DateTime.now().toIso8601String(),
        });
      }
    });
  }

  void _stopPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = null;
  }

  void _startReconnectionTimer() {
    _reconnectionTimer?.cancel();
    _reconnectionTimer = Timer.periodic(_reconnectInterval, (timer) {
      if (!isConnected) {
        _log('Tentando reconectar...');
        connect().catchError((e) {
          _log('Falha na reconexão: $e');
        });
      } else {
        _reconnectionTimer?.cancel();
        _reconnectionTimer = null;
      }
    });
  }

  void updatePosition(Position newPosition) {
    _position = newPosition;
    if (isConnected) {
      _sendToServer({
        'type': 'position_update',
        'name': playerName,
        'position': newPosition.toJson(),
        'timestamp': DateTime.now().toIso8601String(),
      });
    }
  }

  void _sendToServer(Map<String, dynamic> data) {
    if (_socket == null || !isConnected) {
      _log('Não está conectado ao servidor');
      return;
    }

    try {
      InternetAddress.lookup(serverHost).then((addresses) {
        if (addresses.isEmpty) return;

        final message = utf8.encode(jsonEncode(data));
        final result = _socket!.send(message, addresses.first, serverPort);
        _log('Enviado: $result bytes');
      });
    } catch (e) {
      _log('Erro ao enviar mensagem: $e');
      _handleDisconnect();
    }
  }

  Future<void> disconnect() async {
    if (isConnected) {
      _sendToServer({
        'type': 'disconnect',
        'name': playerName,
        'timestamp': DateTime.now().toIso8601String(),
      });
    }

    _status = ConnectionStatus.disconnected;
    _stopPingTimer();
    _reconnectionTimer?.cancel();
    _reconnectionTimer = null;
    _socket?.close();
    _socket = null;
    onConnectionStatus?.call('Desconectado');
  }

  void _log(String message) {
    print('🎮 [GameClient] $message');
  }
}
