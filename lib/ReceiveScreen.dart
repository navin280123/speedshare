import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class ReceiveScreen extends StatefulWidget {
  @override
  _ReceiveScreenState createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends State<ReceiveScreen> {
  ServerSocket? serverSocket;
  String receivedFileName = '';
  double progress = 0.0;
  String ipAddress = '';

  @override
  void initState() {
    super.initState();
    _getIpAddress();
  }

  // Get the device's IP Address
  void _getIpAddress() async {
    for (var interface in await NetworkInterface.list()) {
      for (var addr in interface.addresses) {
        if (addr.type == InternetAddressType.IPv4) {
          setState(() {
            ipAddress = addr.address;
          });
          return;
        }
      }
    }
  }

  // Start receiving files
  void startReceiving() async {
    try {
      serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, 8080);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Listening on port 8080')),
      );

      serverSocket!.listen((client) {
        client.listen((data) async {
          final message = String.fromCharCodes(data);
          if (message.startsWith('FILE_NAME:')) {
            // Extract and sanitize the file name
            receivedFileName = sanitizeFileName(p.basename(
              message.replaceFirst('FILE_NAME:', '').trim(),
            ));
            setState(() {});
          } else {
            // Get the downloads directory
            Directory downloadsDirectory = (await getDownloadsDirectory())!;
            String speedsharePath = '${downloadsDirectory.path}/speedshare';
            Directory speedshareDirectory = Directory(speedsharePath);

            // Create the speedshare directory if it doesn't exist
            if (!await speedshareDirectory.exists()) {
              await speedshareDirectory.create(recursive: true);
            }

            // Save the file in the speedshare directory
            File file = File('$speedsharePath/$receivedFileName');
            file.writeAsBytesSync(data, mode: FileMode.append);
          }
        });
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  // Sanitize file names to remove invalid characters
  String sanitizeFileName(String fileName) {
    return fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  }

  @override
  void dispose() {
    serverSocket?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Receiver')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            ElevatedButton(
              onPressed: startReceiving,
              child: Text('Start Receiving'),
            ),
            SizedBox(height: 20),
            if (ipAddress.isNotEmpty) Text('IP Address: $ipAddress'),
            SizedBox(height: 20),
            if (receivedFileName.isNotEmpty)
              Column(
                children: [
                  Text('Receiving File: $receivedFileName'),
                  SizedBox(height: 10),
                  LinearProgressIndicator(value: progress),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
