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
  int fileSize = 0;
  int bytesReceived = 0;
  File? receivedFile;
  bool isReceiving = false;

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
      setState(() {
        isReceiving = true;
      });
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
          } else if (message.startsWith('FILE_SIZE:')) {
            // Extract file size
            fileSize = int.parse(message.replaceFirst('FILE_SIZE:', '').trim());
            bytesReceived = 0;
            setState(() {});
          } else {
            // Save the incoming file data
            if (receivedFile == null) {
              Directory downloadsDirectory = (await getDownloadsDirectory())!;
              String speedsharePath = '${downloadsDirectory.path}/speedshare';
              Directory speedshareDirectory = Directory(speedsharePath);

              // Create the speedshare directory if it doesn't exist
              if (!await speedshareDirectory.exists()) {
                await speedshareDirectory.create(recursive: true);
              }

              // Create file to write data
              receivedFile = File('$speedsharePath/$receivedFileName');
              if (await receivedFile!.exists()) {
                await receivedFile!.delete(); // Overwrite existing file
              }
            }

            receivedFile!.writeAsBytesSync(data, mode: FileMode.append);
            bytesReceived += data.length;

            // Update progress
            setState(() {
              progress = bytesReceived / fileSize;
            });

            // File transfer complete
            if (bytesReceived >= fileSize) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('File received: $receivedFileName')),
              );
              receivedFile = null; // Reset for next file
              setState(() {
                isReceiving = false;
              });
            }
          }
        });
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
      setState(() {
        isReceiving = false;
      });
    }
  }

  // Stop receiving files
  void stopReceiving() {
    serverSocket?.close();
    setState(() {
      isReceiving = false;
      progress = 0.0;
      receivedFileName = '';
      fileSize = 0;
      bytesReceived = 0;
      receivedFile = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Stopped receiving files')),
    );
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ElevatedButton(
              onPressed: isReceiving ? null : startReceiving,
              child: Text('Start Receiving'),
            ),
            SizedBox(height: 10),
            ElevatedButton(
              onPressed: isReceiving ? stopReceiving : null,
              child: Text('Stop Receiving'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            ),
            SizedBox(height: 20),
            if (ipAddress.isNotEmpty) Text('IP Address: $ipAddress'),
            SizedBox(height: 20),
            if (receivedFileName.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Receiving File: $receivedFileName'),
                  SizedBox(height: 10),
                  LinearProgressIndicator(value: progress),
                  SizedBox(height: 5),
                  Text('${(progress * 100).toStringAsFixed(1)}%'),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
