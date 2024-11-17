import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

class FileSenderScreen extends StatefulWidget {
  final Socket socket;

  FileSenderScreen(this.socket);

  @override
  _FileSenderScreenState createState() => _FileSenderScreenState();
}

class _FileSenderScreenState extends State<FileSenderScreen> {
  bool _isSending = false;

  void sendFile(BuildContext context) async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();
    if (result != null) {
      setState(() {
        _isSending = true;
      });

      File file = File(result.files.single.path!);
      String fileName = file.path.split('/').last;

      // Send file metadata
      widget.socket.add('FILE_NAME:$fileName\n'.codeUnits);
      List<int> fileBytes = await file.readAsBytes();
      String fileSize = fileBytes.length.toString();
      widget.socket.add('FILE_SIZE:$fileSize\n'.codeUnits);

      // Send file data
      widget.socket.add(fileBytes);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('File sent successfully!')),
      );

      setState(() {
        _isSending = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('File Sender'),
        centerTitle: true,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.cloud_upload,
                size: 100,
                color: Colors.blue,
              ),
              SizedBox(height: 20),
              Text(
                'Drop Here to Send Files',
                style: TextStyle(fontSize: 18),
              ),
              SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _isSending ? null : () => sendFile(context),
                icon: Icon(Icons.send),
                label: Text('Send File'),
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
              if (_isSending) ...[
                SizedBox(height: 20),
                CircularProgressIndicator(),
                SizedBox(height: 10),
                Text('Sending file...'),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
