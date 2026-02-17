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
  StreamSubscription<FileParamEvent>? _fileParamSubscription;
  PageController? _pageController;

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
        _pageController?.animateToPage(
          event.index,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      } else {
        log.warning("Invalid pedalboard index: ${event.index}");
      }
    });

    _loadSubscription = hmi.onPedalboardLoad.listen((event) {
      log.info("HMI pedalboard load event: index=${event.index}, uri=${event.uri}");
      // Find pedalboard by URI if possible, otherwise use index
      final idx = pedalboards.indexWhere((pb) => pb.path.endsWith(event.uri));
      int? targetIndex;
      if (idx >= 0) {
        targetIndex = idx;
      } else if (event.index >= 0 && event.index < pedalboards.length) {
        targetIndex = event.index;
      }
      if (targetIndex != null) {
        setState(() {
          activePedalboard = targetIndex!;
          _editMode = false;
          _pedals = null;
          _selectedPedal = null;
        });
        _pageController?.animateToPage(
          targetIndex,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    });

    _fileParamSubscription = hmi.onFileParam.listen((event) {
      log.info("HMI file param event: instance=${event.instance}, uri=${event.paramUri}, path=${event.path}");
      // Update the file parameter value for the matching pedal
      if (_pedals != null) {
        for (final pedal in _pedals!) {
          // Check if this event is for this pedal (match instance name)
          var instanceName = pedal.instanceName;
          if (instanceName.startsWith('<')) {
            instanceName = instanceName.substring(1);
          }
          if (instanceName.endsWith('>')) {
            instanceName = instanceName.substring(0, instanceName.length - 1);
          }
          if (instanceName == event.instance) {
            // Update the file parameter
            if (pedal.fileParameters != null) {
              for (final param in pedal.fileParameters!) {
                if (param.uri == event.paramUri) {
                  setState(() {
                    param.currentPath = event.path;
                  });
                  log.info("Updated file param ${param.label} to ${event.path}");
                  break;
                }
              }
            }
            break;
          }
        }
      }
    });
  }

  @override
  void dispose() {
    _changeSubscription?.cancel();
    _loadSubscription?.cancel();
    _fileParamSubscription?.cancel();
    _pageController?.dispose();
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
    _pageController?.dispose();
    _pageController = PageController(initialPage: 0);
    setState(() {
      activePedalboard = 0;
    });
    return pedalboards;
  }

  @override
  String toStringShort() {
    return activePedalboard < 0 ? 'Pedalboard' : pedalboards[activePedalboard].name;
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

  Widget _buildPedalboardPage(int index) {
    final pedalboard = pedalboards[index];
    final thumbnailFile = File("${pedalboard.path}/thumbnail.png");
    final hasThumbnail = thumbnailFile.existsSync();

    return hasThumbnail
        ? Stack(children: [
            Image.asset(
              'assets/pedalboard.png',
              width: double.infinity,
              height: double.infinity,
              fit: BoxFit.cover,
            ),
            Image(image: FileImage(thumbnailFile)),
            Center(
                child: Text(
                  pedalboard.name,
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
          ])
        : Image.asset(
            'assets/pedalboard.png',
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
          );
  }

  Widget _buildPedalboardView() {
    if (pedalboards.isEmpty || _pageController == null) {
      return Image.asset(
        'assets/pedalboard.png',
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
      );
    }

    return Stack(
      children: [
        PageView.builder(
          controller: _pageController,
          itemCount: pedalboards.length,
          onPageChanged: (index) {
            if (index != activePedalboard) {
              setState(() {
                activePedalboard = index;
                _pedals = null;
                _selectedPedal = null;
              });
              widget.hmiServer?.loadPedalboard(index);
            }
          },
          itemBuilder: (context, index) => _buildPedalboardPage(index),
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
