import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

class VideoStreamConfig {
  static const int PORT = 5000;
  static const String ADDRESS = '127.0.0.1';
  static const int CHUNK_SIZE = 65507;
  static const int DELAY = 1;
}

class VideoSender {
  RawDatagramSocket? socket;
  bool isRunning = true;

  Future<void> initialize() async {
    socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    print('Sender iniciado');
  }

  Future<void> sendVideo(String videoPath) async {
    if (socket == null) {
      throw Exception('Socket não inicializado');
    }

    final file = File(videoPath);
    if (!await file.exists()) {
      throw Exception('Arquivo de vídeo não encontrado: $videoPath');
    }

    final videoStream = file.openRead();
    final targetAddress = InternetAddress(VideoStreamConfig.ADDRESS);
    int sequenceNumber = 0;

    try {
      await for (List<int> chunk in videoStream) {
        if (!isRunning) break;

        for (var i = 0; i < chunk.length; i += VideoStreamConfig.CHUNK_SIZE) {
          if (!isRunning) break;

          final end = (i + VideoStreamConfig.CHUNK_SIZE < chunk.length)
              ? i + VideoStreamConfig.CHUNK_SIZE
              : chunk.length;
          final subChunk = chunk.sublist(i, end);

          final header = ByteData(4)..setInt32(0, sequenceNumber);
          final headerList = header.buffer.asUint8List();

          final dataToSend = Uint8List(headerList.length + subChunk.length);
          dataToSend.setAll(0, headerList);
          dataToSend.setAll(headerList.length, subChunk);

          socket!.send(dataToSend, targetAddress, VideoStreamConfig.PORT);

          await Future.delayed(Duration(milliseconds: VideoStreamConfig.DELAY));
          sequenceNumber++;
        }
      }
    } catch (e) {
      print('Erro ao enviar vídeo: $e');
    }

    print('Transmissão finalizada');
  }

  void stop() {
    isRunning = false;
    socket?.close();
  }
}

class VideoReceiver {
  RawDatagramSocket? socket;
  bool isRunning = true;
  final Map<int, List<int>> receivedChunks = {};
  int expectedSequence = 0;
  final String outputPath;

  VideoReceiver(this.outputPath);

  Future<void> initialize() async {
    socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4, VideoStreamConfig.PORT);
    print('Receiver iniciado na porta ${VideoStreamConfig.PORT}');
  }

  Future<void> startReceiving() async {
    if (socket == null) {
      throw Exception('Socket não inicializado');
    }

    final outputFile = File(outputPath);
    final outputStream = outputFile.openWrite();

    try {
      await for (RawSocketEvent event in socket!) {
        if (!isRunning) break;

        if (event == RawSocketEvent.read) {
          final datagram = socket!.receive();
          if (datagram != null) {
            // Extrai o número de sequência e os dados
            final header = datagram.data.sublist(0, 4);
            final sequenceNumber =
                ByteData.view(Uint8List.fromList(header).buffer).getInt32(0);
            final videoData = datagram.data.sublist(4);

            // Armazena o chunk no buffer
            receivedChunks[sequenceNumber] = videoData;

            // Processa chunks em ordem
            while (receivedChunks.containsKey(expectedSequence)) {
              outputStream.add(receivedChunks[expectedSequence]!);
              receivedChunks.remove(expectedSequence);
              expectedSequence++;
            }
          }
        }
      }
    } catch (e) {
      print('Erro ao receber vídeo: $e');
    } finally {
      await outputStream.close();
    }
  }

  void stop() {
    isRunning = false;
    socket?.close();
  }
}

// Função principal que permite escolher entre sender e receiver
void main(List<String> args) async {
  final videoPath = args[1];
  final sender = VideoSender();
  await sender.initialize();

  try {
    await sender.sendVideo(videoPath);
  } catch (e) {
    print('Erro: $e');
  } finally {
    sender.stop();
  }

  final outputPath = args.length > 1 ? args[1] : 'received_video.mp4';
  final receiver = VideoReceiver(outputPath);
  await receiver.initialize();

  try {
    print('Aguardando stream de vídeo...');
    await receiver.startReceiving();
  } catch (e) {
    print('Erro: $e');
  } finally {
    receiver.stop();
  }
}
