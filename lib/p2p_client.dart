import 'dart:io';

import 'package:logging/logging.dart';
import 'package:tcpteste/rendezvous_server.dart';

import 'message_model.dart';

class P2PClient {
  final String peerId;
  final String rendezvousHost;
  final int rendezvousPort;
  final Logger _logger = Logger('P2PClient');
  late RawDatagramSocket _socket;
  final Map<String, Peer> _peers = {};
  bool _running = false;

  P2PClient({
    required this.peerId,
    this.rendezvousHost = '0.0.0.0',
    this.rendezvousPort = 3000,
  });

  Future<void> start() async {
    try {
      _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      _running = true;
      _logger.info('Cliente iniciado - ID: $peerId, Porta: ${_socket.port}');

      // Iniciar recebimento de mensagens
      _startListening();

      // Registrar com o servidor rendezvous
      await _registerWithRendezvous();
    } catch (e) {
      _logger.severe('Erro ao iniciar cliente: $e');
      rethrow;
    }
  }

  void _startListening() {
    _socket.listen((RawSocketEvent event) {
      if (!_running) return;

      if (event == RawSocketEvent.read) {
        final datagram = _socket.receive();
        if (datagram == null) return;

        try {
          final message = Message.decode(String.fromCharCodes(datagram.data));
          _handleMessage(message, datagram);
        } catch (e) {
          _logger.warning('Erro ao processar mensagem: $e');
        }
      }
    });
  }

  Future<void> _registerWithRendezvous() async {
    final message = Message(
      type: 'register',
      data: {'peer_id': peerId},
    );

    _sendToRendezvous(message);
    _logger.info('Registro enviado para servidor rendezvous');
  }

  void _sendToRendezvous(Message message) {
    try {
      final rendezvousAddress = InternetAddress(rendezvousHost);
      _socket.send(
        message.encode().codeUnits,
        rendezvousAddress,
        rendezvousPort,
      );
    } catch (e) {
      _logger.severe('Erro ao enviar para servidor rendezvous: $e');
    }
  }

  void _handleMessage(Message message, Datagram datagram) {
    switch (message.type) {
      case 'peers_list':
        _handlePeersList(message);
        break;
      case 'connection_request':
        _handleConnectionRequest(message, datagram);
        break;
      case 'connection_accepted':
        _handleConnectionAccepted(message, datagram);
        break;
      case 'direct_message':
        _handleDirectMessage(message, datagram);
        break;
      case 'message_ack':
        _handleMessageAck(message);
        break;
    }
  }

  void _handlePeersList(Message message) {
    final peersData = message.data['peers'] as Map<String, dynamic>;
    _peers.clear();

    for (final entry in peersData.entries) {
      if (entry.key != peerId) {
        // Não adicionar a si mesmo
        final peerData = entry.value as Map<String, dynamic>;
        _peers[entry.key] = Peer(
          id: peerData['id'],
          address: InternetAddress(peerData['address']),
          port: peerData['port'],
        );
      }
    }

    _logger.info('Lista de peers atualizada: ${_peers.length} peers');
  }

  void _handleConnectionRequest(Message message, Datagram datagram) {
    final requesterId = message.data['peer_id'];
    final requesterAddr = message.data['peer_addr'] as Map<String, dynamic>;

    final peer = Peer(
      id: requesterId,
      address: InternetAddress(requesterAddr['address']),
      port: requesterAddr['port'],
    );

    _peers[requesterId] = peer;

    // Enviar aceitação da conexão
    final response = Message(
      type: 'connection_accepted',
      data: {
        'peer_id': peerId,
      },
    );

    _sendToPeer(response, peer);
    _logger.info('Conexão aceita de $requesterId');
  }

  void _handleConnectionAccepted(Message message, Datagram datagram) {
    final accepterId = message.data['peer_id'];
    _logger.info('Conexão estabelecida com $accepterId');
  }

  void _handleDirectMessage(Message message, Datagram datagram) {
    final senderId = message.data['sender_id'];
    final content = message.data['content'];

    print('\nMensagem de $senderId: $content');

    // Enviar confirmação
    final ack = Message(
      type: 'message_ack',
      data: {
        'message_id': message.data['message_id'],
        'receiver_id': peerId,
      },
    );

    _sendToPeer(ack, _peers[senderId]!);
  }

  void _handleMessageAck(Message message) {
    final messageId = message.data['message_id'];
    final receiverId = message.data['receiver_id'];
    _logger.info('Mensagem $messageId confirmada por $receiverId');
  }

  void requestConnection(String targetId) {
    final message = Message(
      type: 'request_connection',
      data: {
        'source_id': peerId,
        'target_id': targetId,
      },
    );

    _sendToRendezvous(message);
    _logger.info('Solicitação de conexão enviada para $targetId');
  }

  void sendMessage(String targetId, String content) {
    if (!_peers.containsKey(targetId)) {
      _logger.warning('Peer $targetId não encontrado');
      return;
    }

    final messageId = DateTime.now().millisecondsSinceEpoch.toString();
    final message = Message(
      type: 'direct_message',
      data: {
        'message_id': messageId,
        'sender_id': peerId,
        'content': content,
      },
    );

    _sendToPeer(message, _peers[targetId]!);
    _logger.info('Mensagem enviada para $targetId');
  }

  void _sendToPeer(Message message, Peer peer) {
    try {
      _socket.send(
        message.encode().codeUnits,
        peer.address,
        peer.port,
      );
    } catch (e) {
      _logger.severe('Erro ao enviar para peer ${peer.id}: $e');
    }
  }

  void listPeers() {
    if (_peers.isEmpty) {
      print('\nNenhum peer conectado');
      return;
    }

    print('\nPeers conectados:');
    for (final peer in _peers.values) {
      print('ID: ${peer.id}, Endereço: ${peer.address.address}:${peer.port}');
    }
  }

  void stop() {
    _running = false;
    _socket.close();
    _logger.info('Cliente finalizado');
  }
}

void main() async {
  // Configurar logging
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    print('${record.level.name}: ${record.time}: ${record.message}');
  });

  // Iniciar cliente
  final client =
      P2PClient(peerId: 'peer_${DateTime.now().millisecondsSinceEpoch}');
  await client.start();

  // Interface de linha de comando
  while (true) {
    print('\nComandos disponíveis:');
    print('1. Conectar com peer');
    print('2. Enviar mensagem');
    print('3. Listar peers');
    print('4. Sair');

    final input = stdin.readLineSync();

    switch (input) {
      case '1':
        print('Digite o ID do peer:');
        final peerId = stdin.readLineSync() ?? '';
        if (peerId.isNotEmpty) {
          client.requestConnection(peerId);
        }
        break;

      case '2':
        print('Digite o ID do peer:');
        final peerId = stdin.readLineSync() ?? '';
        if (peerId.isNotEmpty) {
          print('Digite a mensagem:');
          final message = stdin.readLineSync() ?? '';
          if (message.isNotEmpty) {
            client.sendMessage(peerId, message);
          }
        }
        break;

      case '3':
        client.listPeers();
        break;

      case '4':
        client.stop();
        return;

      default:
        print('Comando inválido');
    }
  }
}
