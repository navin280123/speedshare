
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

class SendScreen extends StatefulWidget {
  const SendScreen({Key? key}) : super(key: key);

  @override
  _SendScreenState createState() => _SendScreenState();
}

class _SendScreenState extends State<SendScreen> {
  final TextEditingController _ipController = TextEditingController();
  final List<String> _ips = [];
  String? _selectedFile;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Send Screen'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _ipController,
              decoration: const InputDecoration(
                labelText: 'Enter IP:Port',
              ),
              onSubmitted: (value) {
                if (value.isNotEmpty) {
                  setState(() {
                    _ips.add(value);
                    _ipController.clear();
                  });
                }
              },
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: () {
                if (_ipController.text.isNotEmpty) {
                  setState(() {
                    _ips.add(_ipController.text);
                    _ipController.clear();
                  });
                }
              },
              child: const Text('Add IP'),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: ListView.builder(
                itemCount: _ips.length,
                itemBuilder: (context, index) {
                  return ListTile(
                    title: Text(_ips[index]),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete),
                      onPressed: () {
                        setState(() {
                          _ips.removeAt(index);
                        });
                      },
                    ),
                  );
                },
              ),
            ),
            ElevatedButton(
              onPressed: _selectFile,
              child: const Text('Select File'),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: _sendFile,
              child: const Text('Send File'),
            ),
          ],
        ),
      ),
    );
  }

  void _selectFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();
    if (result != null) {
      setState(() {
        _selectedFile = result.files.single.path;
      });
    }
  }

  void _sendFile() async {
    if (_selectedFile == null || _ips.isEmpty) {
      debugPrint('Please select a file and add at least one IP.');
      return;
    }
    for (var ip in _ips) {
      final file = File(_selectedFile!);
      final parts = ip.split(':');
      if (parts.length != 2) {
        debugPrint('Invalid IP:Port format');
        continue;
      }
      try {
        final socket = await Socket.connect(parts[0], int.parse(parts[1]));
        await socket.addStream(file.openRead());
        await socket.close();
      } catch (e) {
        debugPrint('Error sending to $ip: $e');
      }
      debugPrint('Sending $_selectedFile to $ip');
    }
  }
}