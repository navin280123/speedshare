import 'package:flutter/material.dart';
import 'package:speedshare/FileSenderScreen.dart';
import 'package:speedshare/ReceiveScreen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = -1;
  final List<Map<String, dynamic>> _sidebarOptions = [
    {
      'title': 'Send',
      'icon': Icons.send,
      'description': 'Send files to another device',
      'color': Colors.blue
    },
    {
      'title': 'Receive',
      'icon': Icons.download,
      'description': 'Receive files from another device',
      'color': Colors.green
    },
    // Add more options here in the future
    // {
    //   'title': 'History',
    //   'icon': Icons.history,
    //   'description': 'View your file transfer history',
    //   'color': Colors.purple
    // },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // Left sidebar
          Container(
            width: 250,
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: Offset(0, 0),
                ),
              ],
            ),
            child: Column(
              children: [
                // Logo/Title section
                Container(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Column(
                    children: [
                      Container(
                        padding: EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.indigo.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.swap_horiz,
                          size: 40,
                          color: Colors.indigo,
                        ),
                      ),
                      SizedBox(height: 12),
                      Text(
                        'SpeedShare',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.indigo,
                        ),
                      ),
                      Text(
                        'Fast File Transfers',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1),
                
                // Menu options
                Expanded(
                  child: ListView.builder(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    itemCount: _sidebarOptions.length,
                    itemBuilder: (context, index) {
                      final option = _sidebarOptions[index];
                      final isSelected = _selectedIndex == index;
                      
                      return Container(
                        margin: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: isSelected 
                              ? option['color'].withOpacity(0.15)
                              : Colors.transparent,
                        ),
                        child: ListTile(
                          leading: Icon(
                            option['icon'],
                            color: isSelected ? option['color'] : Colors.grey[700],
                          ),
                          title: Text(
                            option['title'],
                            style: TextStyle(
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              color: isSelected ? option['color'] : Colors.grey[800],
                            ),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          onTap: () {
                            setState(() {
                              _selectedIndex = index;
                            });
                          },
                        ),
                      );
                    },
                  ),
                ),
                
                // Version/User info at bottom
                Container(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Divider(),
                      SizedBox(height: 8),
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: Colors.indigo.withOpacity(0.2),
                            child: Text(
                              'N',
                              style: TextStyle(
                                color: Colors.indigo,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'navin280123',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                '2025-05-15',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          )
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          // Right content area
          Expanded(
            child: _buildRightPanel(),
          ),
        ],
      ),
    );
  }
  
  Widget _buildRightPanel() {
    // If no option is selected, show the welcome screen
    if (_selectedIndex == -1) {
      return Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/bg.jpg'),
            fit: BoxFit.cover,
            colorFilter: ColorFilter.mode(
              Colors.black.withOpacity(0.4),
              BlendMode.darken,
            ),
          ),
        ),
        child: Center(
          child: Container(
            width: 500,
            padding: EdgeInsets.all(40),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.9),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 20,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.speed,
                  size: 64,
                  color: Colors.indigo,
                ),
                SizedBox(height: 24),
                Text(
                  'Welcome to SpeedShare',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo,
                  ),
                ),
                SizedBox(height: 16),
                Text(
                  'Share files between devices quickly and easily. '
                  'No internet required - just connect to the same network.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[700],
                    height: 1.5,
                  ),
                ),
                SizedBox(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _featureItem(Icons.wifi_off, 'No Internet Needed'),
                    SizedBox(width: 40),
                    _featureItem(Icons.speed, 'Fast Transfers'),
                    SizedBox(width: 40),
                    _featureItem(Icons.security, 'Secure'),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }
    
    // Show the selected screen
    switch (_selectedIndex) {
      case 0:
        return FileSenderScreen();
      case 1:
        return ReceiveScreen();
      default:
        return Container(); // Fallback, should never happen
    }
  }
  
  Widget _featureItem(IconData icon, String text) {
    return Column(
      children: [
        Container(
          padding: EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.indigo.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            color: Colors.indigo,
          ),
        ),
        SizedBox(height: 8),
        Text(
          text,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[800],
          ),
        ),
      ],
    );
  }
}