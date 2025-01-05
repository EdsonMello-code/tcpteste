import 'dart:io';

import 'package:logging/logging.dart';

import 'message_model.dart';

class Peer {
  final String id;
  final InternetAddress address;
  final int port;

  Peer({
    required this.id,
    required this.address,
    required this.port,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'address': address.address,
        'port': port,
      };
}

class RendezvousServer {
  final int port;
  final Logger _logger = Logger('RendezvousServer');
  late RawDatagramSocket _socket;
  final Map<String, Peer> _peers = {};
  bool _running = false;

  RendezvousServer({this.port = 3000});

  Future<void> start() async {
    try {
      _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, port);
      _running = true;
      _logger.info('Servidor iniciado na porta $port');

      await _handleMessages();
    } catch (e) {
      _logger.severe('Erro ao iniciar servidor: $e');
      rethrow;
    }
  }

  Future<void> _handleMessages() async {
    await for (final event in _socket) {
      if (!_running) break;

      if (event == RawSocketEvent.read) {
        try {
          final datagram = _socket.receive();
          if (datagram == null) continue;

          final message = Message.decode(
            String.fromCharCodes(datagram.data),
          );

          await _processMessage(message, datagram);
        } catch (e) {
          _logger.warning('Erro ao processar mensagem: $e');
        }
      }
    }
  }

  Future<void> _processMessage(Message message, Datagram datagram) async {
    switch (message.type) {
      case 'register':
        await _handleRegister(message, datagram);
        break;
      case 'request_connection':
        await _handleConnectionRequest(message, datagram);
        break;
      default:
        _logger.warning('Tipo de mensagem desconhecido: ${message.type}');
    }
  }

  Future<void> _handleRegister(Message message, Datagram datagram) async {
    final peerId = message.data['peer_id'];
    final peer = Peer(
      id: peerId,
      address: datagram.address,
      port: datagram.port,
    );

    _peers[peerId] = peer;
    _logger.info('Peer registrado: $peerId');

    // Enviar lista atualizada de peers
    final peersList = Message(
      type: 'peers_list',
      data: {
        'peers': _peers.map((k, v) => MapEntry(k, v.toJson())),
      },
    );

    for (final peer in _peers.values) {
      _socket.send(
        peersList.encode().codeUnits,
        peer.address,
        peer.port,
      );
    }
  }

  Future<void> _handleConnectionRequest(
      Message message, Datagram datagram) async {
    final sourceId = message.data['source_id'];
    final targetId = message.data['target_id'];

    if (_peers.containsKey(targetId)) {
      final sourcePeer = _peers[sourceId]!;
      final targetPeer = _peers[targetId]!;

      final connectionRequest = Message(
        type: 'connection_request',
        data: {
          'peer_id': sourceId,
          'peer_addr': sourcePeer.toJson(),
        },
      );

      _socket.send(
        connectionRequest.encode().codeUnits,
        targetPeer.address,
        targetPeer.port,
      );

      _logger.info('Solicitação de conexão: $sourceId -> $targetId');
    }
  }

  void stop() {
    _running = false;
    _socket.close();
    _logger.info('Servidor finalizado');
  }
}

void main() async {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    print('${record.level.name}: ${record.time}: ${record.message}');
  });

  final server = RendezvousServer();
  await server.start();
}
