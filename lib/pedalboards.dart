import 'dart:io';

import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:pi_ede_ui/pedalboard.dart';

final log = Logger('Pedalboards');

class PedalboardsWidget extends StatefulWidget {
  const PedalboardsWidget({super.key});

  @override
  State<PedalboardsWidget> createState() => _PedalboardsWidgetState();
}

class _PedalboardsWidgetState extends State<PedalboardsWidget> {
  var pedalboards = <Pedalboard>[];
  var activePedalboard = -1;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future load() async {
    pedalboards.clear();
    var home = Platform.environment['HOME'];
    Directory dir = Directory("$home/.pedalboards");
    log.info("Loading pedalboards $dir");
    var pDirs = dir.listSync(recursive: false).toList();
    for (var pDir in pDirs) {
      pedalboards.add(Pedalboard.load(pDir));
    }
    setState(() {
      activePedalboard = 0;
    });
    return pedalboards;
  }

  String selectedName() {
    return activePedalboard < 0 ? 'Pedalboard' : pedalboards[activePedalboard].name;
  }

  void _left() {
    if (activePedalboard > 0) {
      setState(() {
        activePedalboard--;
      });
    }
  }

  void _right() {
    if (activePedalboard < pedalboards.length - 1) {
      setState(() {
        activePedalboard++;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
        width: double.infinity,
        child: Column(children: [
          Row(
            children: [
              IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: activePedalboard > 0
                      ? () {
                          _left();
                        }
                      : null),
              Expanded(
                  child: (activePedalboard < 0 || !File("${pedalboards[activePedalboard].path}/thumbnail.png").existsSync())
                      ? Image.asset(
                          'assets/pedalboard.png',
                          fit: BoxFit.cover,
                        )
                      : Image(image: FileImage(File("${pedalboards[activePedalboard].path}/thumbnail.png")))),
              IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: activePedalboard >= 0
                      ? () {
                          _right();
                        }
                      : null),
            ],
          )
        ]));
  }
}
