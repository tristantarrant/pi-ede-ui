import 'dart:io';

import 'package:logging/logging.dart';
import 'package:pi_ede_ui/pedalboard.dart';

final log = Logger('Pedalboards');

class Pedalboards {
  var pedalboards = <Pedalboard>[];

  Future load() async {
    pedalboards.clear();
    var home = Platform.environment['HOME'];
    Directory dir = Directory("$home/.pedalboards");
    log.info("Loading pedalboards $dir");
    var pDirs = dir.listSync(recursive: false).toList();
    for (var pDir in pDirs) {
      pedalboards.add(Pedalboard.load(pDir));
    }
    return pedalboards;
  }
}
