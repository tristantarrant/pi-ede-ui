import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:pi_ede_ui/hmi_server.dart';
import 'package:pi_ede_ui/pedalboard.dart';

final log = Logger('Pedalboards');

class PedalboardsWidget extends StatefulWidget {
  final HMIServer? hmiServer;

  const PedalboardsWidget({super.key, this.hmiServer});

  @override
  State<PedalboardsWidget> createState() => _PedalboardsWidgetState();
}

class _PedalboardsWidgetState extends State<PedalboardsWidget> {
  var pedalboards = <Pedalboard>[];
  var activePedalboard = -1;
  StreamSubscription<PedalboardChangeEvent>? _changeSubscription;
  StreamSubscription<PedalboardLoadEvent>? _loadSubscription;

  @override
  void initState() {
    super.initState();
    load();
    _subscribeToHmiEvents();
  }

  void _subscribeToHmiEvents() {
    final hmi = widget.hmiServer;
    if (hmi == null) return;

    _changeSubscription = hmi.onPedalboardChange.listen((event) {
      log.info("HMI pedalboard change event: index=${event.index}");
      if (event.index >= 0 && event.index < pedalboards.length) {
        setState(() {
          activePedalboard = event.index;
        });
      } else {
        log.warning("Invalid pedalboard index: ${event.index}");
      }
    });

    _loadSubscription = hmi.onPedalboardLoad.listen((event) {
      log.info("HMI pedalboard load event: index=${event.index}, uri=${event.uri}");
      // Find pedalboard by URI if possible, otherwise use index
      final idx = pedalboards.indexWhere((pb) => pb.path.endsWith(event.uri));
      if (idx >= 0) {
        setState(() {
          activePedalboard = idx;
        });
      } else if (event.index >= 0 && event.index < pedalboards.length) {
        setState(() {
          activePedalboard = event.index;
        });
      }
    });
  }

  @override
  void dispose() {
    _changeSubscription?.cancel();
    _loadSubscription?.cancel();
    super.dispose();
  }

  Future load() async {
    pedalboards.clear();
    var home = Platform.environment['HOME'];
    Directory dir = Directory("$home/.pedalboards");
    log.info("Loading pedalboards $dir");
    var pDirs = dir.listSync(recursive: false).toList();
    // Sort by path to match mod-ui's Lilv enumeration order
    pDirs.sort((a, b) => a.path.compareTo(b.path));
    for (var pDir in pDirs) {
      pedalboards.add(Pedalboard.load(pDir));
    }
    setState(() {
      activePedalboard = 0;
    });
    return pedalboards;
  }

  @override
  String toStringShort() {
    return activePedalboard < 0 ? 'Pedalboard' : pedalboards[activePedalboard].name;
  }

  void _left() {
    if (activePedalboard > 0) {
      final newIndex = activePedalboard - 1;
      setState(() {
        activePedalboard = newIndex;
      });
      widget.hmiServer?.loadPedalboard(newIndex);
    }
  }

  void _right() {
    if (activePedalboard < pedalboards.length - 1) {
      final newIndex = activePedalboard + 1;
      setState(() {
        activePedalboard = newIndex;
      });
      widget.hmiServer?.loadPedalboard(newIndex);
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
                  child: (activePedalboard < 0 ||
                          !File("${pedalboards[activePedalboard].path}/thumbnail.png").existsSync())
                      ? Image.asset(
                          'assets/pedalboard.png',
                          fit: BoxFit.cover,
                        )
                      : Stack(children: [
                          Image.asset(
                            'assets/pedalboard.png',
                          ),
                          Image(image: FileImage(File('${pedalboards[activePedalboard].path}/thumbnail.png'))),
                          Center(
                              child: Text(
                                pedalboards[activePedalboard].name,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 50,
                                  fontWeight: FontWeight.bold,
                                  shadows: [
                                    // A dark shadow for depth
                                    Shadow(
                                      color: Colors.black,
                                      offset: Offset(5.0, 5.0),
                                      blurRadius: 10.0,
                                    ),
                                    // A secondary bright shadow for a neon-like effect
                                    Shadow(
                                      color: Colors.blue.shade200,
                                      offset: Offset(-5.0, -5.0),
                                      blurRadius: 8.0,
                                    ),
                                  ],
                                ),
                              ))
                        ])),
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
