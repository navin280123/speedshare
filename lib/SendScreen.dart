import 'dart:io';
import 'package:flutter/material.dart';
import 'package:speedshare/FileSender.dart';

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
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              image: DecorationImage(
                image: AssetImage('assets/bg.jpg'), // Add your background image here
                fit: BoxFit.cover,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextField(
                  controller: ipController,
                  decoration: InputDecoration(
                    labelText: 'Receiver IP Address',
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  keyboardType: TextInputType.number,
                ),
                SizedBox(height: 20),
                ElevatedButton(
                  onPressed: connectToReceiver,
                  style: ElevatedButton.styleFrom(
                    iconColor: Colors.blueAccent,
                    padding: EdgeInsets.symmetric(horizontal: 50, vertical: 15),
                    textStyle: TextStyle(fontSize: 18),
                  ),
                  child: Text('Connect'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
