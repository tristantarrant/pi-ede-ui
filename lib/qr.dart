import 'package:flutter/material.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';

class LocalAddressQRWidget extends StatefulWidget {
  const LocalAddressQRWidget({super.key});

  @override
  State<LocalAddressQRWidget> createState() => _LocalAddressQRWidgetState();
}

class _LocalAddressQRWidgetState extends State<LocalAddressQRWidget> {
  String _localIpAddress = 'Fetching IP...';
  String _qrData = 'http://127.0.0.1:8888'; // Fallback URL

  @override
  void initState() {
    super.initState();
    _getNetworkInfo();
  }

  Future<void> _getNetworkInfo() async {
    final info = NetworkInfo();
    String? wifiIP = await info.getWifiIP();

    String dynamicUrl = 'http://$wifiIP:8888';

    setState(() {
      _localIpAddress = wifiIP ?? 'IP Not Available';
      _qrData = dynamicUrl;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        QrImageView(
          data: _qrData,
          version: QrVersions.auto,
          size: 200.0,
        ),
        const SizedBox(height: 20),
        Text('Local IP: $_localIpAddress'),
        Text('QR Code Data: $_qrData', textAlign: TextAlign.center)
      ],
    );
  }
}
