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

  Future<void> start() async {
    print('Game server started');

    socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 3000);
    socket.broadcastEnabled = true;

    socket.listen((event) {
      final datagram = socket.receive();
      if (datagram != null) {
        final action = String.fromCharCodes(datagram.data).trim();
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
        for (final playerItem in players.values) {
          socket.send(
            utf8.encode(player.toString()),
            InternetAddress.anyIPv4,
            playerItem.port,
          );
        }

        print('${player.port}---${player.position}');

        // print('Received message: $action');
      }
    });
  }
}

void main(List<String> args) async {
  final server = GameServer();

  await server.start();
}

class GamerClient {
  final int port;

  RawDatagramSocket? _socket;

  GamerClient({this.port = 0}) {
    _start();
  }

  Future<void> _start() async {
    await Future.delayed(Duration(seconds: 1));
    _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, port);
    _socket?.broadcastEnabled = true;

    // _socket?.listen((event) {
    //   final datagram = _socket?.receive();
    //   if (datagram != null) {
    //     final action = String.fromCharCodes(datagram.data).trim();
    //     // print('Received message: $action');
    //   }
    // });
  }

  Future<void> sendPlayer(Player player) async {
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
  }

  void close() {
    _socket?.close();
  }
}
