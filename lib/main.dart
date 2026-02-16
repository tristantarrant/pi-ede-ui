import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:pi_ede_ui/gpio_client.dart';
import 'package:pi_ede_ui/hmi_server.dart';
import 'package:pi_ede_ui/pedalboards.dart';
import 'package:pi_ede_ui/qr.dart';


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
  late final Widget pedalBoardsWidget = PedalboardsWidget(hmiServer: hmiServer);
  final Widget qrWidget = Center(child: LocalAddressQRWidget());
  late final List<Widget> bodyWidgets = [pedalBoardsWidget, qrWidget];
  int _selectedWidget = 0;
  String _title = appName;

  @override
  void initState() {
    super.initState();
  }

  void _onPedalboard() {
    setState(() {
      _selectedWidget = 0;
      _title = bodyWidgets[0].toStringShort();
    });
  }

  void _onWiFi() {
    setState(() {
      _selectedWidget = 1;
      _title = 'Wi-Fi';
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
      ),
      body: bodyWidgets[_selectedWidget],
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
            ),
            IconButton(
                icon: const Icon(Icons.wifi),
                onPressed: () {
                  _onWiFi();
                  Navigator.pop(context);
                }),
            Divider(),
            IconButton(
                icon: const Icon(Icons.power_off),
                onPressed: () {
                  Navigator.pop(context);
                  _onPowerOff(context);
                })
          ],
        ),
      ),
    );
  }
}
