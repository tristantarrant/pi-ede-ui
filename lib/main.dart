import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:pi_ede_ui/hmi_server.dart';
import 'package:pi_ede_ui/pedalboards.dart';
import 'package:pi_ede_ui/qr.dart';

const appName = 'Pi-EDE';
const accentColor = Colors.orange;
final log = Logger(appName);

void main() {
  Logger.root.level = Level.ALL; // defaults to Level.INFO
  Logger.root.onRecord.listen((record) {
    print('${record.level.name}: ${record.time}: ${record.message}');
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
  late final Future myFuture;
  final HMIServer hmiServer = HMIServer.init();
  final pedalboards = Pedalboards();
  int _selectedWidget = 0;

  final Widget nameWidget = const Center(child: Text("Ready"));

  final Widget qrWidget = Center(child: LocalAddressQRWidget());

  late final List<Widget> bodyWidgets = [nameWidget, qrWidget];

  @override
  void initState() {
    myFuture = pedalboards.load();
    super.initState();
  }

  void _onWiFi() {
    setState(() {
      _selectedWidget = 1;
    });
  }

  void _onPowerOff(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Confirm Shutdown'),
          content: const Text('Are you sure you want to shut down the device?'),
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
                //_shutDownDevice(); // Proceed to shut down
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: accentColor,
        title: Text(widget.title),
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
        child: ListView(
          // Remove any padding from the ListView.
          padding: EdgeInsets.zero,
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(color: accentColor),
              child: Text(appName),
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
