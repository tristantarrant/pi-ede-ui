import 'dart:io';

import 'package:logging/logging.dart';

final log = Logger('HMIServer');

class HMIServer {
  late ServerSocket serverSocket;

  HMIServer.init({int port = 9898}) {
    ServerSocket.bind(InternetAddress.anyIPv4, port).then((value) {
      serverSocket = value;
      log.info("Server is running at <${serverSocket.address.toString()}:${serverSocket.port}>");
      serverSocket.listen(
        (client) {
          handleNewClient(client);
        },
        onDone: () {
          serverSocket.close();
          log.info("Server closed.");
        },
      );
    });
  }

  void handleNewClient(Socket client) {
    log.info("<${client.remoteAddress.toString()}:${client.remotePort}> connected.");

    client.listen(
      (message) {
        String.fromCharCodes(message);
        log.info(String.fromCharCodes(message));
      },
      onDone: () {
        client.close();
        log.info("<${client.remoteAddress.toString()}:${client.remotePort}> disconnected.");
      },
    );
  }
}
