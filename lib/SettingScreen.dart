import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:animate_do/animate_do.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';

class SettingsScreen extends StatefulWidget {
  @override
  _SettingsScreenState createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // User settings
  DateTime expiryDate = DateTime(2029, 5, 15);
  
  // App settings
  String downloadPath = '';
  bool darkMode = false;
  bool autoStart = false;
  bool minimizeToTray = true;
  bool showNotifications = true;
  int port = 8080;
  String deviceName = '';
  bool loading = true;
  bool saveHistory = true;
  
  // Current date/time for display
  final String currentDateTime = '2025-05-16 16:41:48';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() {
      loading = true;
    });
    
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Get download path
      Directory? downloadsDirectory = await getDownloadsDirectory();
      String speedsharePath = '${downloadsDirectory!.path}/speedshare';
      
      setState(() {
        deviceName = prefs.getString('deviceName') ?? Platform.localHostname;
        darkMode = prefs.getBool('darkMode') ?? false;
        autoStart = prefs.getBool('autoStart') ?? false;
        minimizeToTray = prefs.getBool('minimizeToTray') ?? true;
        showNotifications = prefs.getBool('showNotifications') ?? true;
        port = prefs.getInt('port') ?? 8080;
        downloadPath = prefs.getString('downloadPath') ?? speedsharePath;
        saveHistory = prefs.getBool('saveHistory') ?? true;
        loading = false;
      });
    } catch (e) {
      print('Error loading settings: $e');
      setState(() {
        loading = false;
      });
    }
  }

  Future<void> _saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      await prefs.setString('deviceName', deviceName);
      await prefs.setBool('darkMode', darkMode);
      await prefs.setBool('autoStart', autoStart);
      await prefs.setBool('minimizeToTray', minimizeToTray);
      await prefs.setBool('showNotifications', showNotifications);
      await prefs.setInt('port', port);
      await prefs.setString('downloadPath', downloadPath);
      await prefs.setBool('saveHistory', saveHistory);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle_rounded, color: Colors.white),
              SizedBox(width: 10),
              Text('Settings saved successfully'),
            ],
          ),
          backgroundColor: Color(0xFF2AB673),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: EdgeInsets.all(20),
        ),
      );
    } catch (e) {
      print('Error saving settings: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.error_rounded, color: Colors.white),
              SizedBox(width: 10),
              Text('Error saving settings'),
            ],
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: EdgeInsets.all(20),
        ),
      );
    }
  }

  Future<void> _selectDownloadFolder() async {
    try {
      String? path = await FilePicker.platform.getDirectoryPath();
      
      if (path != null) {
        setState(() {
          downloadPath = path;
        });
      }
    } catch (e) {
      print('Error selecting folder: $e');
    }
  }

  Future<void> _resetSettings() async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Reset Settings',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'This will reset all settings to default values. Are you sure you want to continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: Colors.grey[700],
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              final prefs = await SharedPreferences.getInstance();
              await prefs.clear();
              await _loadSettings();
              
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Row(
                    children: [
                      Icon(Icons.refresh_rounded, color: Colors.white),
                      SizedBox(width: 10),
                      Text('Settings reset to defaults'),
                    ],
                  ),
                  backgroundColor: Color(0xFF4E6AF3),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  margin: EdgeInsets.all(20),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text(
              'Reset',
              style: TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with title
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4E6AF3).withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.settings_rounded,
                    size: 24,
                    color: Color(0xFF4E6AF3),
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Settings',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF4E6AF3),
                      ),
                    ),
                    Text(
                      'Configure your preferences',
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).brightness == Brightness.dark 
                            ? Colors.grey[400] 
                            : Colors.grey[600],
                      ),
                    ),
                  ],
                ),
               
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Main content
            Expanded(
              child: loading
                  ? const Center(
                      child: CircularProgressIndicator(),
                    )
                  : _buildSettingsContent(),
            ),
            
            // Bottom save/reset buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _saveSettings,
                    icon: const Icon(Icons.save_rounded),
                    label: const Text('Save Settings'),
                    style: ElevatedButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: const Color(0xFF2AB673),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _resetSettings,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Reset'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildSettingsContent() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Account section
          _buildAccountSection(),
          const SizedBox(height: 16),
          
          // General settings
          _buildSettingsCard(
            title: 'General Settings',
            icon: Icons.tune_rounded,
            children: [
              _buildSwitchSetting(
                title: 'Auto-start with system',
                subtitle: 'SpeedShare will start when your system boots',
                value: autoStart,
                onChanged: (value) {
                  setState(() {
                    autoStart = value;
                  });
                },
                icon: Icons.play_circle_outline_rounded,
              ),
              const Divider(),
              _buildSwitchSetting(
                title: 'Minimize to system tray',
                subtitle: 'Keep SpeedShare running in the background',
                value: minimizeToTray,
                onChanged: (value) {
                  setState(() {
                    minimizeToTray = value;
                  });
                },
                icon: Icons.minimize_rounded,
              ),
              const Divider(),
              _buildSwitchSetting(
                title: 'Show notifications',
                subtitle: 'Display notifications for file transfers',
                value: showNotifications,
                onChanged: (value) {
                  setState(() {
                    showNotifications = value;
                  });
                },
                icon: Icons.notifications_rounded,
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Network settings
          _buildSettingsCard(
            title: 'Network Settings',
            icon: Icons.wifi_rounded,
            children: [
              _buildPortSetting(),
            ],
          ),
          const SizedBox(height: 16),
          
          // File settings
          _buildSettingsCard(
            title: 'File Settings',
            icon: Icons.folder_rounded,
            children: [
              _buildDownloadPathSetting(),
              const Divider(),
              _buildSwitchSetting(
                title: 'Save transfer history',
                subtitle: 'Keep a record of sent and received files',
                value: saveHistory,
                onChanged: (value) {
                  setState(() {
                    saveHistory = value;
                  });
                },
                icon: Icons.history_rounded,
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Appearance settings
          _buildSettingsCard(
            title: 'Appearance',
            icon: Icons.palette_rounded,
            children: [
              _buildSwitchSetting(
                title: 'Dark mode',
                subtitle: 'Use dark theme throughout the app',
                value: darkMode,
                onChanged: (value) {
                  setState(() {
                    darkMode = value;
                  });
                },
                icon: Icons.dark_mode_rounded,
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // About section
          _buildAboutSection(context),
        ],
      ),
    );
  }
  
  Widget _buildAccountSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4E6AF3).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.person_rounded,
                    size: 18,
                    color: Color(0xFF4E6AF3),
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Account',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // User info card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.grey[850]
                    : Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFF4E6AF3).withOpacity(0.2),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: const BoxDecoration(
                      color: Color(0xFF4E6AF3),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        deviceName.isNotEmpty ? deviceName.substring(0, 1).toUpperCase() : 'D',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          deviceName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF2AB673),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                'Active',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
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
            
            const SizedBox(height: 16),
            
            // Device name display (non-editable)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.withOpacity(0.5)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.computer_rounded,
                    size: 20,
                    color: Colors.grey,
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Device Name',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                      Text(
                        deviceName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
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
    );
  }
  
  Widget _buildSettingsCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4E6AF3).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    icon,
                    size: 18,
                    color: const Color(0xFF4E6AF3),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }
  
  Widget _buildSwitchSetting({
    required String title,
    required String subtitle,
    required bool value,
    required Function(bool) onChanged,
    required IconData icon,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.grey[800]
                  : Colors.grey[200],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 16,
              color: value ? const Color(0xFF4E6AF3) : Colors.grey,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.grey[400]
                        : Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: const Color(0xFF2AB673),
          ),
        ],
      ),
    );
  }
  
  Widget _buildPortSetting() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.grey[800]
                  : Colors.grey[200],
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.router_rounded,
              size: 16,
              color: Color(0xFF4E6AF3),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Port',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Text(
                  'Set the port number for receiving files',
                  style: TextStyle(
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: 120,
                  child: TextField(
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    keyboardType: TextInputType.number,
                    controller: TextEditingController(text: port.toString()),
                    onChanged: (value) {
                      try {
                        port = int.parse(value);
                      } catch (_) {}
                    },
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Requires app restart',
                  style: TextStyle(
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                    color: Colors.orange,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildDownloadPathSetting() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.grey[800]
                  : Colors.grey[200],
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.download_rounded,
              size: 16,
              color: Color(0xFF4E6AF3),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Download Location',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Text(
                  'Set where received files are saved',
                  style: TextStyle(
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Colors.grey.withOpacity(0.5),
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          downloadPath,
                          style: const TextStyle(fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      TextButton(
                        onPressed: _selectDownloadFolder,
                        child: const Text('Browse'),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildAboutSection(BuildContext context) {
  // Helper to show dialogs for Privacy Policy and Terms
  void _showInfoDialog(String title, String content) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(content)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  // Helper to launch external URLs
  void _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  return Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF4E6AF3).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.info_outline_rounded,
                  size: 18,
                  color: Color(0xFF4E6AF3),
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'About',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // App logo and info
          Column(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF4E6AF3), Color(0xFF2AB673)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.swap_horiz_rounded,
                  size: 32,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'SpeedShare',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF4E6AF3),
                ),
              ),
              Text(
                'Version 1.0.0',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.grey[400]
                      : Colors.grey[600],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '© 2025 SpeedShare. All rights reserved.',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.grey[500]
                      : Colors.grey[600],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    onPressed: () {
                      _showInfoDialog(
                        'Privacy Policy',
                        'Privacy Policy\n\n'
                        'Last updated: May 19, 2025\n\n'
                        'SpeedShare we values your privacy. This Privacy Policy explains how SpeedShare handles your information when you use our application to share files between two computers over the same WiFi network.\n\n'
                        '1. Information Collection\n'
                        'SpeedShare does not collect, store, or transmit any personal information or files to any server. All file transfers occur directly between devices on your local WiFi network.\n\n'
                        '2. How We Use Your Information\n'
                        'Since we do not collect any personal data, we do not use or share your information in any way.\n\n'
                        '3. File Transfers\n'
                        'All files shared using SpeedShare remain within your local network and are not uploaded to any external servers. You are responsible for ensuring that you trust the devices you are connecting to.\n\n'
                        '4. Security\n'
                        'We implement reasonable security measures to protect connections between devices; however, please ensure your WiFi network is secure and only connect to trusted devices.\n\n'
                        '5. Changes to This Policy\n'
                        'We may update our Privacy Policy from time to time. Any changes will be reflected within the application.\n\n'
                        '6. Contact Us\n'
                        'If you have any questions about this Privacy Policy, please contact us at kumarnavinverma7@gmail.com.',
                      );
                    },
                    child: const Text(
                      'Privacy Policy',
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
                  Text('•', style: TextStyle(color: Colors.grey)),
                  TextButton(
                    onPressed: () {
                      _showInfoDialog(
                        'Terms of Service',
                        'Terms of Service\n\n'
                        'Last updated: May 19, 2025\n\n'
                        'Please read these Terms of Service ("Terms") before using SpeedShare ("the App"). By using the App, you agree to be bound by these Terms.\n\n'
                        '1. Use of the App\n'
                        'SpeedShare is intended for sharing files between two computers over the same WiFi network. You are responsible for using the App in compliance with all applicable laws and regulations.\n\n'
                        '2. User Responsibility\n'
                        'You are solely responsible for the files you choose to share and receive. Do not use SpeedShare to transfer illegal, harmful, or infringing content.\n\n'
                        '3. No Warranty\n'
                        'SpeedShare is provided "as is" without any warranties. We do not guarantee that the App will be error-free or uninterrupted.\n\n'
                        '4. Limitation of Liability\n'
                        'We are not liable for any damages or losses resulting from the use of SpeedShare, including but not limited to data loss, unauthorized access, or network issues.\n\n'
                        '5. Modifications\n'
                        'We reserve the right to modify these Terms at any time. Continued use of the App after changes means you accept the new Terms.\n\n'
                        '6. Contact Us\n'
                        'If you have questions about these Terms, contact us at kumarnavinverma7@gmail.com.',
                      );
                    },
                    child: const Text(
                      'Terms of Service',
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Navin Kumar's details and socials
              Column(
                children: [
                  const CircleAvatar(
                    radius: 28,
                    backgroundImage: NetworkImage(
                      'https://avatars.githubusercontent.com/u/103583078?s=400&u=80572f8430b374171aaa46ee2d9c67c3b62c3b65&v=4', // Change to your GitHub avatar if needed
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Navin Kumar',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const Text(
                    'Flutter Developer',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: () => _launchUrl('mailto:kumarnavinverma7@gmail.com'),
                    child: const Text(
                      'kumarnavinverma7@gmail.com',
                      style: TextStyle(
                        fontSize: 13,
                        color: Color(0xFF4E6AF3),
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.code),
                        tooltip: 'GitHub',
                        onPressed: () => _launchUrl('https://github.com/navin280123'),
                      ),
                      IconButton(
                        icon: const Icon(Icons.business),
                        tooltip: 'LinkedIn',
                        onPressed: () => _launchUrl('https://www.linkedin.com/in/navin-kumar-verma/'),
                      ),
                      IconButton(
                        icon: const Icon(Icons.alternate_email),
                        tooltip: 'Instagram',
                        onPressed: () => _launchUrl('https://www.instagram.com/navin.2801/'),
                      ),
                      // Add more socials if desired
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
}