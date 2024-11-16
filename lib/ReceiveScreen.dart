import 'package:flutter/material.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:network_info_plus/network_info_plus.dart';

class ReceiveScreen extends StatefulWidget {
  const ReceiveScreen({Key? key}) : super(key: key);

  @override
  State<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends State<ReceiveScreen> {
  String ipAddress = 'Loading...';
  bool isReceiving = false;
  ServerSocket? server;

  @override
  void initState() {
    super.initState();
    _getIpAddress();
  }

  Future<void> _getIpAddress() async {
    try {
      final info = NetworkInfo();
      final ip = await info.getWifiIP();
      setState(() {
        ipAddress = ip ?? 'Not found';
      });
    } catch (e) {
      setState(() {
        ipAddress = 'Error getting IP';
      });
    }
  }

  Future<void> _startReceiving() async {
    if (isReceiving) return;

    try {
      setState(() {
        isReceiving = true;
      });

      server = await ServerSocket.bind(InternetAddress.anyIPv4, 4040);
      debugPrint('Listening on port 4040');

      server!.listen((Socket client) async {
        debugPrint('Connection from ${client.remoteAddress.address}');
        
        final documentsDir = await getApplicationDocumentsDirectory();
        final saveDir = Directory('${documentsDir.path}/speedshare');
        if (!await saveDir.exists()) {
          await saveDir.create();
        }

        final fileName = DateTime.now().millisecondsSinceEpoch.toString();
        final file = File('${saveDir.path}/$fileName');
        final sink = file.openWrite();

        await client.cast<List<int>>().pipe(sink);
        debugPrint('File saved to: ${file.path}');
      });

    } catch (e) {
      debugPrint('Error: $e');
      setState(() {
        isReceiving = false;
      });
    }
  }

  @override
  void dispose() {
    server?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Your IP: $ipAddress'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: _startReceiving,
              child: Text(isReceiving ? 'Receiving...' : 'Start Receiving'),
            ),
            if (isReceiving)
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text('Waiting for files...'),
              ),
          ],
        ),
      ),
    );
  }
}
