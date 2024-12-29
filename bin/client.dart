import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
}

class GameClient {
  final String serverHost;
  final int serverPort;
  RawDatagramSocket? _socket;
  Timer? _pingTimer;
  Timer? _reconnectionTimer;
  bool _isConnected = false;
  final String playerName;
  Position _position;

  // Callbacks para eventos do jogo
  final void Function(Position)? onPositionUpdate;
  final void Function(String)? onPlayerJoined;
  final void Function(String)? onPlayerLeft;
  final void Function(String)? onConnectionStatus;

  GameClient({
    required this.serverHost,
    required this.serverPort,
    required this.playerName,
    this.onPositionUpdate,
    this.onPlayerJoined,
    this.onPlayerLeft,
    this.onConnectionStatus,
    Position? initialPosition,
  }) : _position = initialPosition ?? Position(x: 0, y: 0);

  bool get isConnected => _isConnected;
  Position get position => _position;

  Future<void> connect() async {
    if (_isConnected) {
      print('🔄 Já está conectado ao servidor');
      return;
    }

    try {
      print('🎮 Conectando ao servidor: $serverHost:$serverPort');

      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        0,
      );

      final serverAddresses = await InternetAddress.lookup(serverHost);
      if (serverAddresses.isEmpty) {
        throw Exception('❌ Não foi possível resolver o endereço do servidor');
      }

      final serverAddress = serverAddresses.first;
      print('📡 Endereço do servidor resolvido: ${serverAddress.address}');

      // Configurar listener para mensagens do servidor
      _socket!.listen(
        _handleSocketEvent,
        onError: _handleSocketError,
        onDone: _handleSocketDone,
        cancelOnError: false,
      );

      // Enviar mensagem inicial de conexão
      _sendToServer({
        'type': 'connect',
        'name': playerName,
        'position': _position.toJson(),
        'timestamp': DateTime.now().toIso8601String(),
      });

      // Iniciar ping periódico
      _startPingTimer();

      _isConnected = true;
      onConnectionStatus?.call('Conectado ao servidor');
    } catch (e) {
      print('❌ Erro ao conectar: $e');
      onConnectionStatus?.call('Erro ao conectar: $e');
      _startReconnectionTimer();
      rethrow;
    }
  }

  void _handleSocketEvent(RawSocketEvent event) {
    if (event == RawSocketEvent.read && _socket != null) {
      final datagram = _socket!.receive();
      if (datagram != null) {
        _handleServerMessage(datagram);
      }
    }
  }

  void _handleSocketError(error) {
    print('❌ Erro no socket: $error');
    onConnectionStatus?.call('Erro na conexão: $error');
    _handleDisconnect();
  }

  void _handleSocketDone() {
    print('📡 Conexão encerrada pelo servidor');
    onConnectionStatus?.call('Conexão encerrada pelo servidor');
    _handleDisconnect();
  }

  void _handleDisconnect() {
    _isConnected = false;
    _stopPingTimer();
    _socket?.close();
    _socket = null;
    _startReconnectionTimer();
  }

  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(Duration(seconds: 5), (timer) {
      if (_isConnected) {
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
    _reconnectionTimer = Timer.periodic(Duration(seconds: 5), (timer) {
      if (!_isConnected) {
        print('🔄 Tentando reconectar...');
        connect().catchError((e) {
          print('❌ Falha na reconexão: $e');
        });
      } else {
        _reconnectionTimer?.cancel();
        _reconnectionTimer = null;
      }
    });
  }

  void _handleServerMessage(Datagram datagram) {
    try {
      final String message = utf8.decode(datagram.data);
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
          final playerName = data['name'];
          if (playerName != null) {
            onPlayerJoined?.call(playerName);
          }
          break;

        case 'player_left':
          final playerName = data['name'];
          if (playerName != null) {
            onPlayerLeft?.call(playerName);
          }
          break;

        case 'pong':
          // Servidor respondeu ao ping
          break;

        default:
          print('📨 Mensagem desconhecida do servidor: $message');
      }
    } catch (e) {
      print('❌ Erro ao processar mensagem do servidor: $e');
    }
  }

  void updatePosition(Position newPosition) {
    _position = newPosition;
    if (_isConnected) {
      _sendToServer({
        'type': 'position_update',
        'name': playerName,
        'position': newPosition.toJson(),
        'timestamp': DateTime.now().toIso8601String(),
      });
    }
  }

  void _sendToServer(Map<String, dynamic> data) {
    try {
      if (_socket == null || !_isConnected) {
        print('❌ Não está conectado ao servidor');
        return;
      }

      final message = utf8.encode(jsonEncode(data));
      _socket!.send(message, InternetAddress(serverHost), serverPort);
    } catch (e) {
      print('❌ Erro ao enviar mensagem: $e');
      _handleDisconnect();
    }
  }

  Future<void> disconnect() async {
    if (_isConnected) {
      _sendToServer({
        'type': 'disconnect',
        'name': playerName,
        'timestamp': DateTime.now().toIso8601String(),
      });
    }

    _isConnected = false;
    _stopPingTimer();
    _reconnectionTimer?.cancel();
    _reconnectionTimer = null;
    _socket?.close();
    _socket = null;
    onConnectionStatus?.call('Desconectado do servidor');
  }
}
