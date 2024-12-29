import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'client.dart';

class Player {
  final String name;
  final InternetAddress address;
  final int port;
  final Map<String, dynamic> position;
  final String color;

  String get key => '${address.address}:$port';

  const Player._({
    required this.name,
    required this.position,
    required this.address,
    required this.port,
    required this.color,
  });

  factory Player({
    required String name,
    required Map<String, dynamic> position,
    String color = '#000000',
  }) {
    return Player._(
      name: name,
      address: InternetAddress.anyIPv4,
      port: 0,
      position: position,
      color: color,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'address': address.address,
      'port': port,
      'position': position,
      'color': color,
    };
  }

  Player copyWith({
    String? name,
    InternetAddress? address,
    int? port,
    Map<String, dynamic>? position,
    String? color,
  }) {
    return Player._(
      name: name ?? this.name,
      address: address ?? this.address,
      port: port ?? this.port,
      position: position ?? this.position,
      color: color ?? this.color,
    );
  }

  @override
  String toString() {
    return jsonEncode(toMap());
  }
}

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
          playerItem.port,
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
    serverHost: 'https://tcpteste.onrender.com', // Substitua pelo seu endereço
    serverPort: 10000, // Substitua pela sua porta
    playerName: 'Player${DateTime.now().millisecondsSinceEpoch}',
    onPositionUpdate: (position) {
      print('📍 Nova posição: (${position.x}, ${position.y})');
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
    initialPosition: Position(x: 0, y: 0),
  );

  try {
    await client.connect();

    // Exemplo de atualização de posição
    await Future.delayed(Duration(seconds: 2));
    client.updatePosition(Position(x: 10, y: 20));

    // Mantenha o programa rodando
    await Future.delayed(Duration(seconds: 30));

    // Desconectar
    await client.disconnect();
  } catch (e) {
    print('❌ Erro: $e');
  }
}
