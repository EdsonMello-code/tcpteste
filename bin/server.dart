import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
      print('Iniciando servidor de jogo na porta $port...');

      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, port,
          reuseAddress: true // Permite reutilização da porta
          );

      socket.broadcastEnabled = true;

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
}

class GameClient {
  final int port;
  final Duration reconnectDelay;
  final Duration pingInterval;

  RawDatagramSocket? _socket;
  Timer? _pingTimer;

  GameClient({
    this.port = 0,
    this.reconnectDelay = const Duration(seconds: 5),
    this.pingInterval = const Duration(seconds: 30),
  });

  Future<void> connect() async {
    try {
      await _start();
      _startPingTimer();
    } catch (e) {
      print('Erro ao conectar: $e');
      _scheduleReconnect();
    }
  }

  Future<void> _start() async {
    _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, port,
        reuseAddress: true);
    _socket?.broadcastEnabled = true;
    print('Cliente conectado na porta ${_socket?.port}');
  }

  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(pingInterval, (timer) {
      _sendPing();
    });
  }

  void _sendPing() {
    try {
      final ping = Player(
        name: 'ping',
        position: {'x': 0, 'y': 0},
      );
      sendPlayer(ping);
    } catch (e) {
      print('Erro ao enviar ping: $e');
    }
  }

  void _scheduleReconnect() {
    Future.delayed(reconnectDelay, () {
      connect();
    });
  }

  Future<void> sendPlayer(Player player) async {
    try {
      _socket?.send(
        utf8.encode(player
            .copyWith(
              port: _socket?.port,
              address: _socket?.address,
            )
            .toString()),
        InternetAddress.anyIPv4,
        3000,
      );
    } catch (e) {
      print('Erro ao enviar dados do jogador: $e');
    }
  }

  void close() {
    _pingTimer?.cancel();
    _socket?.close();
    print('Cliente desconectado');
  }
}
