import 'package:flutter/material.dart';
import 'package:speedshare/ReceiveScreen.dart';
import 'package:speedshare/SendScreen.dart';

class MainScreen extends StatelessWidget {
  const MainScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/bg.jpg',
            fit: BoxFit.cover,
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                onPressed: () {
                  // Handle send button press
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => SendScreen()),
                  );
                },
                style: ElevatedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                  textStyle: const TextStyle(fontSize: 18),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Text('Send'),
                    SizedBox(width: 10),
                    Icon(Icons.send),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  // Handle receive button press
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => ReceiveScreen()),
                  );
                },
                style: ElevatedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                  textStyle: const TextStyle(fontSize: 18),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Text('Receive'),
                    SizedBox(width: 10),
                    Icon(Icons.download),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
