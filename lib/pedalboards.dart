import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:pi_ede_ui/hmi_server.dart';
import 'package:pi_ede_ui/pedalboard.dart';
import 'package:pi_ede_ui/pedal.dart';
import 'package:pi_ede_ui/pedal_editor.dart';

final log = Logger('Pedalboards');

class PedalboardsWidget extends StatefulWidget {
  final HMIServer? hmiServer;
  final int bankId;

  const PedalboardsWidget({super.key, this.hmiServer, this.bankId = 1});

  @override
  State<PedalboardsWidget> createState() => _PedalboardsWidgetState();
}

class _PedalboardsWidgetState extends State<PedalboardsWidget> {
  var pedalboards = <Pedalboard>[];
  var activePedalboard = -1;
  var _editMode = false;
  List<Pedal>? _pedals;
  bool _loadingPedals = false;
  Pedal? _selectedPedal;
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
          _editMode = false;
          _pedals = null;
          _selectedPedal = null;
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
          _editMode = false;
          _pedals = null;
          _selectedPedal = null;
        });
      } else if (event.index >= 0 && event.index < pedalboards.length) {
        setState(() {
          activePedalboard = event.index;
          _editMode = false;
          _pedals = null;
          _selectedPedal = null;
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
        _pedals = null;
        _selectedPedal = null;
      });
      widget.hmiServer?.loadPedalboard(newIndex);
    }
  }

  void _right() {
    if (activePedalboard < pedalboards.length - 1) {
      final newIndex = activePedalboard + 1;
      setState(() {
        activePedalboard = newIndex;
        _pedals = null;
        _selectedPedal = null;
      });
      widget.hmiServer?.loadPedalboard(newIndex);
    }
  }

  void _toggleEditMode() async {
    if (_editMode) {
      setState(() {
        _editMode = false;
      });
    } else {
      setState(() {
        _editMode = true;
        _loadingPedals = true;
      });

      // Load pedals for the current pedalboard
      if (activePedalboard >= 0 && activePedalboard < pedalboards.length) {
        final pedals = await pedalboards[activePedalboard].getPedals();
        setState(() {
          _pedals = pedals;
          _loadingPedals = false;
        });
      } else {
        setState(() {
          _loadingPedals = false;
        });
      }
    }
  }

  Widget _buildPedalboardView() {
    return Stack(
      children: [
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
                                  Shadow(
                                    color: Colors.black,
                                    offset: Offset(5.0, 5.0),
                                    blurRadius: 10.0,
                                  ),
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
        ),
        // Edit button overlay
        Positioned(
          bottom: 8,
          right: 8,
          child: FloatingActionButton.small(
            onPressed: _toggleEditMode,
            child: const Icon(Icons.edit),
          ),
        ),
      ],
    );
  }

  Widget _buildPedalListView() {
    if (_loadingPedals) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_pedals == null || _pedals!.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('No pedals found'),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _toggleEditMode,
              icon: const Icon(Icons.arrow_back),
              label: const Text('Back'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Header with back button
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _toggleEditMode,
              ),
              Expanded(
                child: Text(
                  pedalboards[activePedalboard].name,
                  style: Theme.of(context).textTheme.titleMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text('${_pedals!.length} pedals'),
            ],
          ),
        ),
        const Divider(height: 1),
        // Pedal list
        Expanded(
          child: ListView.builder(
            itemCount: _pedals!.length,
            itemBuilder: (context, index) {
              final pedal = _pedals![index];
              return _buildPedalTile(pedal);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPedalTile(Pedal pedal) {
    Widget thumbnail;
    if (pedal.thumbnailPath != null && File(pedal.thumbnailPath!).existsSync()) {
      thumbnail = Image.file(
        File(pedal.thumbnailPath!),
        width: 64,
        height: 64,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return _buildDefaultThumbnail();
        },
      );
    } else {
      thumbnail = _buildDefaultThumbnail();
    }

    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: thumbnail,
      ),
      title: Text(pedal.label ?? pedal.instanceName),
      subtitle: pedal.brand != null ? Text(pedal.brand!) : null,
      trailing: Icon(
        pedal.enabled ? Icons.power : Icons.power_off,
        color: pedal.enabled ? Colors.green : Colors.grey,
      ),
      onTap: () {
        log.info('Opening editor for pedal: ${pedal.label}');
        setState(() {
          _selectedPedal = pedal;
        });
      },
    );
  }

  Widget _buildDefaultThumbnail() {
    return Container(
      width: 64,
      height: 64,
      color: Colors.grey.shade300,
      child: const Icon(Icons.extension, size: 32),
    );
  }

  Widget _buildPedalEditorView() {
    return PedalEditorWidget(
      pedal: _selectedPedal!,
      hmiServer: widget.hmiServer,
      onBack: () {
        setState(() {
          _selectedPedal = null;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget child;
    if (_selectedPedal != null) {
      child = _buildPedalEditorView();
    } else if (_editMode) {
      child = _buildPedalListView();
    } else {
      child = _buildPedalboardView();
    }

    return SizedBox(
      width: double.infinity,
      height: double.infinity,
      child: child,
    );
  }
}
