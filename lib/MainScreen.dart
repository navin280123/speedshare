import 'dart:io';

import 'package:flutter/material.dart';
import 'package:speedshare/FileSenderScreen.dart';
import 'package:speedshare/ReceiveScreen.dart';
import 'package:speedshare/SettingScreen.dart';
import 'package:animate_do/animate_do.dart';
import 'package:lottie/lottie.dart';
import 'package:intl/intl.dart';
import 'package:speedshare/SyncScreen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with SingleTickerProviderStateMixin {
  int _selectedIndex = -1;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  String computerName = '';

  final List<Map<String, dynamic>> _sidebarOptions = [
    {
      'title': 'Send',
      'icon': Icons.send_rounded,
      'description': 'Send Files',
      'color': const Color(0xFF4E6AF3)
    },
    {
      'title': 'Receive',
      'icon': Icons.download_rounded,
      'description': 'Receive Files',
      'color': const Color(0xFF2AB673)
    },
    {
      'title': 'Sync',
      'icon': Icons.sync_rounded,
      'description': 'Sync Files',
      'color': const Color(0xFF4E6AF3)
    },
    {
      'title': 'Settings',
      'icon': Icons.settings_rounded,
      'description': 'Configure preferences',
      'color': const Color(0xFF8B54D3)
    },
  ];

  @override
  void initState() {
    super.initState();
    _getComputerName();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOut,
      ),
    );

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }
 void _getComputerName() async {
    try {
      // For simplicity, using hostname as computer name
      final hostname = Platform.localHostname;
      setState(() {
        computerName = hostname;
      });
    } catch (e) {
      setState(() {
        computerName = 'Unknown Device';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // Left sidebar with fixed width - narrower to prevent overflow
          Container(
            width: 180, // Reduced from 200px
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                ),
              ],
            ),
            child: Column(
                children: [
                // Logo/Title section
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 16), // Reduced padding
                  child: Column(
                  children: [
                    Container(
                    padding: const EdgeInsets.all(10), // Reduced padding
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                      colors: [Color(0xFF4E6AF3), Color(0xFF2AB673)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF4E6AF3).withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                      ],
                    ),
                    child: const Icon(
                      Icons.swap_horiz_rounded,
                      size: 28, // Reduced size
                      color: Colors.white,
                    ),
                    ),
                    const SizedBox(height: 10),
                    ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [Color(0xFF4E6AF3), Color(0xFF2AB673)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ).createShader(bounds),
                    child: const Text(
                      'SpeedShare',
                      style: TextStyle(
                      fontSize: 20, // Reduced font size
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      ),
                    ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                    'Fast File Transfers',
                    style: TextStyle(
                      fontSize: 11, // Reduced font size
                      color: Theme.of(context).brightness == Brightness.dark 
                        ? Colors.grey[400] 
                        : Colors.grey[600],
                    ),
                    overflow: TextOverflow.ellipsis, // Handle text overflow
                    ),
                  ],
                  ),
                ),
                
                const Divider(height: 1),

                // Menu options
                Expanded(
                  child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8), // Reduced padding
                  itemCount: _sidebarOptions.length,
                  itemBuilder: (context, index) {
                    final option = _sidebarOptions[index];
                    final isSelected = _selectedIndex == index;

                    return Container(
                    margin: const EdgeInsets.only(bottom: 6), // Reduced margin
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8), // Reduced radius
                      color: isSelected 
                        ? option['color'].withOpacity(0.1)
                        : Colors.transparent,
                    ),
                    child: ListTile(
                      dense: true, // More compact list tile
                      visualDensity: VisualDensity.compact, // Compact visual style
                      contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8, 
                      vertical: 2
                      ), // Reduced padding
                      leading: Container(
                      padding: const EdgeInsets.all(6), // Reduced padding
                      decoration: BoxDecoration(
                        color: isSelected 
                          ? option['color'].withOpacity(0.2)
                          : Theme.of(context).brightness == Brightness.dark
                            ? Colors.grey[800]
                            : Colors.grey[200],
                        borderRadius: BorderRadius.circular(6), // Reduced radius
                      ),
                      child: Icon(
                        option['icon'],
                        color: isSelected ? option['color'] : Colors.grey[600],
                        size: 16, // Reduced size
                      ),
                      ),
                      title: Text(
                      option['title'],
                      style: TextStyle(
                        fontSize: 13, // Reduced font size
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected ? option['color'] : null,
                      ),
                      overflow: TextOverflow.ellipsis, // Handle text overflow
                      ),
                      subtitle: Text(
                      option['description'],
                      style: TextStyle(
                        fontSize: 11, // Reduced font size
                        color: Theme.of(context).brightness == Brightness.dark 
                          ? Colors.grey[400] 
                          : Colors.grey[600],
                      ),
                      overflow: TextOverflow.ellipsis, // Handle text overflow
                      ),
                      trailing: isSelected 
                        ? Icon(Icons.arrow_forward_ios, size: 12, color: option['color']) 
                        : null,
                      shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      ),
                      onTap: () {
                      setState(() {
                        _selectedIndex = index;
                        _animationController.reset();
                        _animationController.forward();
                      });
                      },
                    ),
                    );
                  },
                  ),
                ),

                // Device info and current time at bottom
                Container(
                  padding: const EdgeInsets.all(12), // Reduced padding
                  child: Column(
                  children: [
                    const Divider(),
                    const SizedBox(height: 6),
                    Row(
                    children: [
                      Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF4E6AF3).withOpacity(0.2),
                          blurRadius: 4, // Reduced blur
                          offset: const Offset(0, 1), // Reduced offset
                        ),
                        ],
                      ),
                      child: const CircleAvatar(
                        radius: 14, // Reduced radius
                        backgroundColor: Color(0xFF4E6AF3),
                        child: Icon(
                        Icons.devices,
                        color: Colors.white,
                        size: 14,
                        ),
                      ),
                      ),
                      const SizedBox(width: 8), // Reduced spacing
                      Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                        Text(
                           computerName,
                          style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12, // Reduced font size
                          ),
                          overflow: TextOverflow.ellipsis, // Handle text overflow
                        ),
                        StreamBuilder<String>(
                          stream: Stream.periodic(
                          const Duration(seconds: 1),
                          (_) => DateFormat('MMM dd, HH:mm:ss').format(DateTime.now()),
                          ),
                          initialData: DateFormat('MMM dd, HH:mm:ss').format(DateTime.now()),
                          builder: (context, snapshot) {
                          return Text(
                            snapshot.data!,
                            style: TextStyle(
                            fontSize: 10, // Reduced font size
                            color: Theme.of(context).brightness == Brightness.dark 
                              ? Colors.grey[400] 
                              : Colors.grey[600],
                            ),
                            overflow: TextOverflow.ellipsis, // Handle text overflow
                          );
                          },
                        ),
                        ],
                      ),
                      ),
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
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: _buildRightPanel(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRightPanel() {
    // If no option is selected, show the welcome screen
    if (_selectedIndex == -1) {
      return FadeTransition(
        opacity: _fadeAnimation,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16), // Reduced padding
          child: Center(
            child: SingleChildScrollView( // Add scrolling capability
              child: FadeIn(
                child: Card(
                  elevation: 3,
                  shadowColor: Colors.black.withOpacity(0.3),
                  child: Padding(
                    padding: const EdgeInsets.all(24.0), // Reduced padding
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 500), // Constrain width
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Lottie.asset(
                            'assets/logo.json',
                            height: 120, // Reduced height
                            fit: BoxFit.contain,
                          ),
                          const SizedBox(height: 20), // Reduced spacing
                          ShaderMask(
                            shaderCallback: (bounds) => const LinearGradient(
                              colors: [Color(0xFF4E6AF3), Color(0xFF2AB673)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ).createShader(bounds),
                            child: const Text(
                              'Welcome to SpeedShare',
                              style: TextStyle(
                                fontSize: 24, // Reduced font size
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis, // Handle text overflow
                            ),
                          ),
                          const SizedBox(height: 12), // Reduced spacing
                          const Text(
                            'Share files between devices quickly and easily.\nNo internet required - just connect to the same network.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13, // Reduced font size
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 24), // Reduced spacing
                          
                          // Wrap for responsive feature items
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 20, // Horizontal spacing
                            runSpacing: 16, // Vertical spacing
                            children: [
                              _buildFeatureItem(
                                Icons.wifi_off_rounded, 
                                'No Internet'
                              ),
                              _buildFeatureItem(
                                Icons.speed_rounded, 
                                'Fast Transfers'
                              ),
                              _buildFeatureItem(
                                Icons.security_rounded, 
                                'Secure'
                              ),
                            ],
                          ),
                          
                          const SizedBox(height: 24), // Reduced spacing
                          
                          // Wrap for responsive buttons
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 12, // Horizontal spacing
                            runSpacing: 12, // Vertical spacing
                            children: [
                              _buildActionButton(
                                'Send Files',
                                Icons.send_rounded,
                                const Color(0xFF4E6AF3),
                                () {
                                  setState(() {
                                    _selectedIndex = 0;
                                    _animationController.reset();
                                    _animationController.forward();
                                  });
                                },
                              ),
                              _buildActionButton(
                                'Receive Files',
                                Icons.download_rounded,
                                const Color(0xFF2AB673),
                                () {
                                  setState(() {
                                    _selectedIndex = 1;
                                    _animationController.reset();
                                    _animationController.forward();
                                  });
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
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
      case 2 :
        return SyncScreen();
      case 3:
        return SettingsScreen();
      default:
        return Container(); // Fallback, should never happen
    }
  }

  Widget _buildFeatureItem(IconData icon, String text) {
    return SizedBox(
      width: 90, // Fixed width for consistent layout
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(10), // Reduced padding
            decoration: BoxDecoration(
              color: const Color(0xFF4E6AF3).withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: const Color(0xFF4E6AF3),
              size: 18, // Reduced size
            ),
          ),
          const SizedBox(height: 6), // Reduced spacing
          Text(
            text,
            style: TextStyle(
              fontSize: 12, // Reduced font size
              color: Theme.of(context).brightness == Brightness.dark 
                  ? Colors.grey[300] 
                  : Colors.grey[700],
            ),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis, // Handle text overflow
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(
      String text, IconData icon, Color color, VoidCallback onTap) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16), // Reduced icon size
      label: Text(
        text,
        style: const TextStyle(fontSize: 13), // Reduced font size
      ),
      style: ElevatedButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), // Reduced padding
        elevation: 2,
        shadowColor: color.withOpacity(0.4),
        minimumSize: const Size(120, 0), // Minimum width to maintain consistent sizing
      ),
    );
  }
}