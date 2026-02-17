import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:pi_ede_ui/bank.dart';
import 'package:pi_ede_ui/banks.dart';
import 'package:pi_ede_ui/bypass.dart';
import 'package:pi_ede_ui/gpio_client.dart';
import 'package:pi_ede_ui/hmi_server.dart';
import 'package:pi_ede_ui/midi_settings.dart';
import 'package:pi_ede_ui/pedalboards.dart';
import 'package:pi_ede_ui/profiles.dart';
import 'package:pi_ede_ui/qr.dart';
import 'package:pi_ede_ui/snapshots.dart';
import 'package:pi_ede_ui/transport.dart';
import 'package:pi_ede_ui/tuner.dart';


// C header typedef:
typedef SystemC = ffi.Int32 Function(ffi.Pointer<Utf8> command);

// Dart header typedef
typedef SystemDart = int Function(ffi.Pointer<Utf8> command);

const appName = 'Pi-EDE';
const accentColor = Colors.orange;
final log = Logger(appName);

void main() {
  Logger.root.level = Level.INFO; // defaults to Level.INFO
  Logger.root.onRecord.listen((record) {
    if (record.loggerName != "term") {
      print('${record.time} ${record.level.name} [${record.loggerName}] ${record.message}');
    }
  });
  runApp(const UI());
}

class UI extends StatelessWidget {
  const UI({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: appName,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: accentColor),
        useMaterial3: true,
      ),
      home: const PiEdeUI(title: appName),
    );
  }
}

class PiEdeUI extends StatefulWidget {
  const PiEdeUI({super.key, required this.title});

  final String title;

  @override
  State<PiEdeUI> createState() => _PiEdeUIState();
}

class _PiEdeUIState extends State<PiEdeUI> {
  final HMIServer hmiServer = HMIServer.init();
  final GPIOClient gpioClient = GPIOClient.init();
  final Widget qrWidget = Center(child: LocalAddressQRWidget());
  int _selectedWidget = 0;
  String _title = appName;

  // Bank state
  int _currentBankId = 1;
  String _currentBankName = 'All Pedalboards';

  @override
  void initState() {
    super.initState();
  }

  void _onBankSelected(Bank bank) {
    setState(() {
      _currentBankId = bank.id;
      _currentBankName = bank.title;
      _selectedWidget = 0; // Switch back to pedalboards view
      _title = 'Pedalboards';
    });
    hmiServer.setCurrentBank(_currentBankId);
    Navigator.pop(context); // Close drawer
  }

  void _onPedalboard() {
    setState(() {
      _selectedWidget = 0;
      _title = 'Pedalboards';
    });
  }

  void _onBanks() {
    setState(() {
      _selectedWidget = 1;
      _title = 'Banks';
    });
  }

  void _onWiFi() {
    setState(() {
      _selectedWidget = 2;
      _title = 'Wi-Fi';
    });
  }

  void _onTuner() {
    setState(() {
      _selectedWidget = 3;
      _title = 'Tuner';
    });
  }

  void _onSnapshots() {
    setState(() {
      _selectedWidget = 4;
      _title = 'Snapshots';
    });
  }

  void _onTransport() {
    setState(() {
      _selectedWidget = 5;
      _title = 'Transport';
    });
  }

  void _onBypass() {
    setState(() {
      _selectedWidget = 6;
      _title = 'Bypass';
    });
  }

  void _onMIDI() {
    setState(() {
      _selectedWidget = 7;
      _title = 'MIDI';
    });
  }

  void _onProfiles() {
    setState(() {
      _selectedWidget = 8;
      _title = 'Profiles';
    });
  }

  void _onPowerOff(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Shutdown'),
          content: const Text('Shut down the device?'),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(dialogContext).pop(); // Dismiss dialog
              },
            ),
            TextButton(
              child: const Text('Shutdown'),
              onPressed: () {
                Navigator.of(dialogContext).pop(); // Dismiss dialog
                _shutDownDevice(); // Proceed to shut down
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _shutDownDevice() async {
    log.info("shutdown");
    var libc = ffi.DynamicLibrary.open('libc.so.6');
    final systemP = libc.lookupFunction<SystemC, SystemDart>('system');
    final cmdP = 'sudo shutdown now'.toNativeUtf8();
    systemP(cmdP);
    calloc.free(cmdP);
  }

  Widget _buildBody() {
    switch (_selectedWidget) {
      case 0:
        return PedalboardsWidget(hmiServer: hmiServer, bankId: _currentBankId);
      case 1:
        return BanksWidget(
          selectedBankId: _currentBankId,
          onBankSelected: _onBankSelected,
        );
      case 2:
        return qrWidget;
      case 3:
        return TunerWidget(hmiServer: hmiServer);
      case 4:
        return SnapshotsWidget(hmiServer: hmiServer);
      case 5:
        return TransportWidget(hmiServer: hmiServer);
      case 6:
        return BypassWidget(hmiServer: hmiServer);
      case 7:
        return MIDISettingsWidget(hmiServer: hmiServer);
      case 8:
        return ProfilesWidget(hmiServer: hmiServer);
      default:
        return const Center(child: Text('Unknown view'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: accentColor,
        toolbarHeight: 34,
        title: Text(_title),
        leading: Builder(
          builder: (context) {
            return IconButton(
              icon: const Icon(Icons.menu),
              onPressed: () {
                Scaffold.of(context).openDrawer();
              },
            );
          },
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: Center(
              child: Text(
                _currentBankName,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
        ],
      ),
      body: _buildBody(),
      drawer: Drawer(
        width: 64,
        child: ListView(
          // Remove any padding from the ListView.
          padding: EdgeInsets.zero,
          children: [
            IconButton(
              icon: const Icon(Icons.music_note),
              onPressed: () {
                _onPedalboard();
                Navigator.pop(context);
              },
              tooltip: 'Pedalboards',
            ),
            IconButton(
              icon: const Icon(Icons.folder),
              onPressed: () {
                _onBanks();
                Navigator.pop(context);
              },
              tooltip: 'Banks',
            ),
            IconButton(
              icon: const Icon(Icons.camera),
              onPressed: () {
                _onSnapshots();
                Navigator.pop(context);
              },
              tooltip: 'Snapshots',
            ),
            const Divider(),
            IconButton(
              icon: const Icon(Icons.tune),
              onPressed: () {
                _onTuner();
                Navigator.pop(context);
              },
              tooltip: 'Tuner',
            ),
            IconButton(
              icon: const Icon(Icons.speed),
              onPressed: () {
                _onTransport();
                Navigator.pop(context);
              },
              tooltip: 'Transport',
            ),
            IconButton(
              icon: const Icon(Icons.volume_off),
              onPressed: () {
                _onBypass();
                Navigator.pop(context);
              },
              tooltip: 'Bypass',
            ),
            const Divider(),
            IconButton(
              icon: const Icon(Icons.piano),
              onPressed: () {
                _onMIDI();
                Navigator.pop(context);
              },
              tooltip: 'MIDI Settings',
            ),
            IconButton(
              icon: const Icon(Icons.person),
              onPressed: () {
                _onProfiles();
                Navigator.pop(context);
              },
              tooltip: 'Profiles',
            ),
            IconButton(
              icon: const Icon(Icons.wifi),
              onPressed: () {
                _onWiFi();
                Navigator.pop(context);
              },
              tooltip: 'Wi-Fi',
            ),
            const Divider(),
            IconButton(
              icon: const Icon(Icons.power_off),
              onPressed: () {
                Navigator.pop(context);
                _onPowerOff(context);
              },
              tooltip: 'Shutdown',
            ),
          ],
        ),
      ),
    );
  }
}
