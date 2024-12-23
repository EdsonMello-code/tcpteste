import 'dart:io';

void main() async {
  int i = 1;

  final file = File('video.mp4');

  // <Server-side> Create server in the local network at port <any available port>.
  final ServerSocket server =
      await ServerSocket.bind(InternetAddress.anyIPv4, 3001);
  server.listen((Socket client) {
    print('Got a new message (${i++}):');
    print('Got a new message (${i++}):');

    client.listen(
      (message) {
        final fileStream = file.openRead();

        fileStream.listen((data) {
          client.add(data);
        });
      },
      onDone: () {
        print('Client disconnected.');
        client.destroy();
      },
    );
  });
  // <Client-side> Connects to the server.
}
