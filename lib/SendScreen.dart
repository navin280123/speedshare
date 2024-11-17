import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

class SendScreen extends StatefulWidget {
  @override
  _SendScreenState createState() => _SendScreenState();
}

class _SendScreenState extends State<SendScreen> {
  final TextEditingController ipController = TextEditingController();
  late Socket? socket;

  void connectToReceiver() async {
    try {
      final ip = ipController.text;
      const port = 8080; // Fixed port

      socket = await Socket.connect(ip, port);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Connected to $ip:$port')),
      );

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => FileSenderScreen(socket!),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to connect: $e')),
      );
    }
  }

  @override
  void dispose() {
    socket?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Sender')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: ipController,
              decoration: InputDecoration(labelText: 'Receiver IP Address'),
              keyboardType: TextInputType.number,
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: connectToReceiver,
              child: Text('Connect'),
            ),
          ],
        ),
      ),
    );
  }
}

class FileSenderScreen extends StatelessWidget {
  final Socket socket;

  FileSenderScreen(this.socket);

  void sendFile(BuildContext context) async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();
    if (result != null) {
      File file = File(result.files.single.path!);
      String fileName = file.path.split('/').last;
      socket.add('FILE_NAME:$fileName\n'.codeUnits);

      List<int> fileBytes = await file.readAsBytes();
      socket.add(fileBytes);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('File sent successfully!')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('File Sender')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Drop Here to Send Files'),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => sendFile(context),
              child: Text('Send File'),
            ),
          ],
        ),
      ),
    );
  }
}
