import 'dart:async';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:pi_ede_ui/hmi_protocol.dart';

final log = Logger('HMIServer');

/// Event emitted when a pedalboard change command is received
class PedalboardChangeEvent {
  final int index;
  PedalboardChangeEvent(this.index);
}

/// Event emitted when a pedalboard load command is received
class PedalboardLoadEvent {
  final int index;
  final String uri;
  PedalboardLoadEvent(this.index, this.uri);
}

class HMIServer {
  late ServerSocket serverSocket;
  final List<Socket> _clients = [];
  final Map<Socket, List<int>> _buffers = {};

  // Stream controllers for events
  final _pedalboardChangeController = StreamController<PedalboardChangeEvent>.broadcast();
  final _pedalboardLoadController = StreamController<PedalboardLoadEvent>.broadcast();

  /// Stream of pedalboard change events
  Stream<PedalboardChangeEvent> get onPedalboardChange => _pedalboardChangeController.stream;

  /// Stream of pedalboard load events
  Stream<PedalboardLoadEvent> get onPedalboardLoad => _pedalboardLoadController.stream;

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
    _clients.add(client);
    _buffers[client] = [];

    client.listen(
      (data) {
        _buffers[client]!.addAll(data);
        _processBuffer(client);
      },
      onDone: () {
        _clients.remove(client);
        _buffers.remove(client);
        client.close();
        log.info("<${client.remoteAddress.toString()}:${client.remotePort}> disconnected.");
      },
      onError: (error) {
        log.warning("Client error: $error");
        _clients.remove(client);
        _buffers.remove(client);
        client.close();
      },
    );
  }

  void _processBuffer(Socket client) {
    final buffer = _buffers[client]!;

    // Process all complete messages (null-terminated)
    while (true) {
      final nullIndex = buffer.indexOf(0);
      if (nullIndex == -1) break;

      // Extract the message
      final messageBytes = buffer.sublist(0, nullIndex);
      buffer.removeRange(0, nullIndex + 1);

      final message = String.fromCharCodes(messageBytes).trim();
      if (message.isNotEmpty) {
        _handleMessage(client, message);
      }
    }
  }

  void _handleMessage(Socket client, String message) {
    log.info("Received: $message");

    final parts = message.split(' ');
    if (parts.isEmpty) return;

    final command = parts[0];
    final args = parts.sublist(1);

    switch (command) {
      case HMIProtocol.CMD_PING:
        _sendResponse(client, 0);
        break;

      case HMIProtocol.CMD_GUI_CONNECTED:
        log.info("GUI connected notification received");
        _sendResponse(client, 0);
        break;

      case HMIProtocol.CMD_GUI_DISCONNECTED:
        log.info("GUI disconnected notification received");
        _sendResponse(client, 0);
        break;

      case HMIProtocol.CMD_PEDALBOARD_CHANGE:
        _handlePedalboardChange(client, args);
        break;

      case HMIProtocol.CMD_PEDALBOARD_LOAD:
        _handlePedalboardLoad(client, args);
        break;

      case HMIProtocol.CMD_PEDALBOARD_NAME_SET:
        _handlePedalboardNameSet(client, args);
        break;

      default:
        log.warning("Unknown command: $command");
        _sendResponse(client, -1);
    }
  }

  void _handlePedalboardChange(Socket client, List<String> args) {
    if (args.isEmpty) {
      log.warning("Pedalboard change: missing index argument");
      _sendResponse(client, -1);
      return;
    }

    final index = int.tryParse(args[0]);
    if (index == null) {
      log.warning("Pedalboard change: invalid index '${args[0]}'");
      _sendResponse(client, -1);
      return;
    }

    log.info("Pedalboard change to index: $index");
    _pedalboardChangeController.add(PedalboardChangeEvent(index));
    _sendResponse(client, 0);
  }

  void _handlePedalboardLoad(Socket client, List<String> args) {
    if (args.length < 2) {
      log.warning("Pedalboard load: missing arguments");
      _sendResponse(client, -1);
      return;
    }

    final index = int.tryParse(args[0]);
    if (index == null) {
      log.warning("Pedalboard load: invalid index '${args[0]}'");
      _sendResponse(client, -1);
      return;
    }

    final uri = args[1];
    log.info("Pedalboard load: index=$index, uri=$uri");
    _pedalboardLoadController.add(PedalboardLoadEvent(index, uri));
    _sendResponse(client, 0);
  }

  void _handlePedalboardNameSet(Socket client, List<String> args) {
    if (args.isEmpty) {
      log.warning("Pedalboard name set: missing name argument");
      _sendResponse(client, -1);
      return;
    }

    final name = args.join(' ');
    log.info("Pedalboard name set: $name");
    // Could emit an event here if needed
    _sendResponse(client, 0);
  }

  void _sendResponse(Socket client, int status, [String? data]) {
    final response = data != null
        ? "${HMIProtocol.CMD_RESPONSE} $status $data\x00"
        : "${HMIProtocol.CMD_RESPONSE} $status\x00";
    client.add(response.codeUnits);
    log.fine("Sent: $response");
  }

  /// Send a command to all connected clients
  void broadcast(String command) {
    final message = "$command\x00";
    for (final client in _clients) {
      client.add(message.codeUnits);
    }
    log.fine("Broadcast: $command");
  }

  /// Request mod-ui to load a pedalboard
  void loadPedalboard(int pedalboardIndex, {int bankId = 1}) {
    final command = '${HMIProtocol.CMD_PEDALBOARD_LOAD} $bankId $pedalboardIndex';
    log.info("Requesting pedalboard load: bankId=$bankId, index=$pedalboardIndex");
    broadcast(command);
  }

  void dispose() {
    _pedalboardChangeController.close();
    _pedalboardLoadController.close();
    for (final client in _clients) {
      client.close();
    }
    serverSocket.close();
  }
}
