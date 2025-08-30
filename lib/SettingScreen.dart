import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:animate_do/animate_do.dart';
import 'package:speedshare/main.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';

class SettingsScreen extends StatefulWidget {
  @override
  _SettingsScreenState createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Constants
  static const int MIN_PORT = 1024;
  static const int MAX_PORT = 65535;
  static const int DEFAULT_PORT = 8080;
  
  // User settings
  DateTime expiryDate = DateTime(2029, 5, 15);
  
  // App settings
  String downloadPath = '';
  bool darkMode = false;
  bool autoStart = false;
  bool minimizeToTray = true;
  bool showNotifications = true;
  int port = DEFAULT_PORT;
  String deviceName = '';
  bool loading = true;
  bool saveHistory = true;
  bool isPortValid = true;
  String? portError;
  
  // Controllers
  final TextEditingController _portController = TextEditingController();
  final TextEditingController _deviceNameController = TextEditingController();
  
  // Dynamic values instead of hardcoded
  String get currentDateTime => DateTime.now().toString();
  String get userLogin => Platform.localHostname;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _portController.dispose();
    _deviceNameController.dispose();
    super.dispose();
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
      
      final loadedDeviceName = prefs.getString('deviceName') ?? Platform.localHostname;
      final loadedPort = prefs.getInt('port') ?? DEFAULT_PORT;
      
      setState(() {
        deviceName = loadedDeviceName;
        darkMode = prefs.getBool('darkMode') ?? false;
        autoStart = prefs.getBool('autoStart') ?? false;
        minimizeToTray = prefs.getBool('minimizeToTray') ?? true;
        showNotifications = prefs.getBool('showNotifications') ?? true;
        port = loadedPort;
        downloadPath = prefs.getString('downloadPath') ?? speedsharePath;
        saveHistory = prefs.getBool('saveHistory') ?? true;
        loading = false;
      });
      
      // Update controllers
      _deviceNameController.text = deviceName;
      _portController.text = port.toString();
      _validatePort(port.toString());
    } catch (e) {
      print('Error loading settings: $e');
      _showSnackBar(
        'Error loading settings: $e',
        Icons.error_rounded,
        Colors.red,
      );
      setState(() {
        loading = false;
      });
    }
  }

  Future<void> _saveSettings() async {
    // Validate all settings before saving
    if (!_validateAllSettings()) {
      return;
    }
    
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
      
      _showSnackBar(
        'Settings saved successfully',
        Icons.check_circle_rounded,
        Color(0xFF2AB673),
      );
      
      // Show restart notification if port changed
      final currentPort = prefs.getInt('port') ?? DEFAULT_PORT;
      if (currentPort != port) {
        _showSnackBar(
          'Port change requires app restart to take effect',
          Icons.restart_alt_rounded,
          Colors.orange,
        );
      }
    } catch (e) {
      print('Error saving settings: $e');
      _showSnackBar(
        'Error saving settings: $e',
        Icons.error_rounded,
        Colors.red,
      );
    }
  }

  bool _validateAllSettings() {
    // Validate port
    if (!isPortValid) {
      _showSnackBar(
        'Please fix the port error before saving',
        Icons.error_rounded,
        Colors.red,
      );
      return false;
    }
    
    // Validate device name
    if (deviceName.trim().isEmpty) {
      _showSnackBar(
        'Device name cannot be empty',
        Icons.error_rounded,
        Colors.red,
      );
      return false;
    }
    
    // Validate download path
    if (downloadPath.trim().isEmpty) {
      _showSnackBar(
        'Download path cannot be empty',
        Icons.error_rounded,
        Colors.red,
      );
      return false;
    }
    
    return true;
  }

  void _validatePort(String value) {
    setState(() {
      if (value.isEmpty) {
        isPortValid = false;
        portError = 'Port cannot be empty';
        return;
      }
      
      try {
        final newPort = int.parse(value);
        if (newPort < MIN_PORT || newPort > MAX_PORT) {
          isPortValid = false;
          portError = 'Port must be between $MIN_PORT and $MAX_PORT';
        } else {
          isPortValid = true;
          portError = null;
          port = newPort;
        }
      } catch (e) {
        isPortValid = false;
        portError = 'Port must be a valid number';
      }
    });
  }

  Future<void> _selectDownloadFolder() async {
    try {
      String? path = await FilePicker.platform.getDirectoryPath();
      
      if (path != null) {
        // Validate that the path is accessible
        final directory = Directory(path);
        if (await directory.exists()) {
          setState(() {
            downloadPath = path;
          });
          _showSnackBar(
            'Download folder updated',
            Icons.check_circle_rounded,
            Color(0xFF2AB673),
          );
        } else {
          _showSnackBar(
            'Selected folder is not accessible',
            Icons.error_rounded,
            Colors.red,
          );
        }
      }
    } catch (e) {
      print('Error selecting folder: $e');
      _showSnackBar(
        'Error selecting folder: $e',
        Icons.error_rounded,
        Colors.red,
      );
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
            fontSize: (context.isMobile ? 16 : 18) * context.fontSizeMultiplier,
          ),
        ),
        content: Text(
          'This will reset all settings to default values. Are you sure you want to continue?',
          style: TextStyle(
            fontSize: (context.isMobile ? 12 : 14) * context.fontSizeMultiplier,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: Colors.grey[700],
                fontSize: (context.isMobile ? 12 : 14) * context.fontSizeMultiplier,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              try {
                final prefs = await SharedPreferences.getInstance();
                await prefs.clear();
                await _loadSettings();
                
                _showSnackBar(
                  'Settings reset to defaults',
                  Icons.refresh_rounded,
                  Color(0xFF4E6AF3),
                );
              } catch (e) {
                _showSnackBar(
                  'Error resetting settings: $e',
                  Icons.error_rounded,
                  Colors.red,
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text(
              'Reset',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: (context.isMobile ? 12 : 14) * context.fontSizeMultiplier,
              ),
            ),
          ),
        ],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  Future<void> _openDownloadsFolder() async {
    try {
      if (Platform.isWindows) {
        await Process.run('explorer', [downloadPath]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [downloadPath]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [downloadPath]);
      } else {
        _showSnackBar(
          'Cannot open folder on this platform',
          Icons.error_rounded,
          Colors.orange,
        );
      }
    } catch (e) {
      _showSnackBar(
        'Could not open folder: $e',
        Icons.error_rounded,
        Colors.red,
      );
    }
  }

  void _showSnackBar(String message, IconData icon, Color color, {SnackBarAction? action}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: Colors.white),
            SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: EdgeInsets.all(20),
        action: action,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        padding: context.responsivePadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with title - Responsive
            _buildHeader(),
            
            SizedBox(height: context.isMobile ? 12 : 16),
            
            // Main content - Responsive
            Expanded(
              child: loading
                  ? const Center(
                      child: CircularProgressIndicator(),
                    )
                  : _buildSettingsContent(),
            ),
            
            // Bottom save/reset buttons - Responsive
            _buildBottomButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(context.isMobile ? 6 : 8),
          decoration: BoxDecoration(
            color: const Color(0xFF4E6AF3).withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.settings_rounded,
            size: context.isMobile ? 20 : 24,
            color: Color(0xFF4E6AF3),
          ),
        ),
        SizedBox(width: context.isMobile ? 8 : 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Settings',
                style: TextStyle(
                  fontSize: (context.isMobile ? 18 : 20) * context.fontSizeMultiplier,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF4E6AF3),
                ),
              ),
              Text(
                'Configure your preferences',
                style: TextStyle(
                  fontSize: (context.isMobile ? 11 : 13) * context.fontSizeMultiplier,
                  color: Theme.of(context).brightness == Brightness.dark 
                      ? Colors.grey[400] 
                      : Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBottomButtons() {
    if (context.isMobile) {
      return Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _saveSettings,
              icon: const Icon(Icons.save_rounded),
              label: const Text('Save Settings'),
              style: ElevatedButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: const Color(0xFF2AB673),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _resetSettings,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Reset Settings'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
        ],
      );
    }

    return Row(
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
    );
  }
  
  Widget _buildSettingsContent() {
    return SingleChildScrollView(
      child: _buildResponsiveLayout(),
    );
  }

  Widget _buildResponsiveLayout() {
    if (context.isMobile) {
      return _buildMobileLayout();
    } else if (context.isTablet) {
      return _buildTabletLayout();
    } else {
      return _buildDesktopLayout();
    }
  }

  Widget _buildMobileLayout() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Account section
        _buildAccountSection(),
        SizedBox(height: context.isMobile ? 12 : 16),
        
        // General settings
        _buildGeneralSettingsCard(),
        SizedBox(height: context.isMobile ? 12 : 16),
        
        // Network settings
        _buildNetworkSettingsCard(),
        SizedBox(height: context.isMobile ? 12 : 16),
        
        // File settings
        _buildFileSettingsCard(),
        SizedBox(height: context.isMobile ? 12 : 16),
        
        // Appearance settings
        _buildAppearanceSettingsCard(),
        SizedBox(height: context.isMobile ? 12 : 16),
        
        // About section
        _buildAboutSection(context),
      ],
    );
  }

  Widget _buildTabletLayout() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Account section (full width)
        _buildAccountSection(),
        const SizedBox(height: 16),
        
        // Settings in rows
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                children: [
                  _buildGeneralSettingsCard(),
                  const SizedBox(height: 16),
                  _buildFileSettingsCard(),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                children: [
                  _buildNetworkSettingsCard(),
                  const SizedBox(height: 16),
                  _buildAppearanceSettingsCard(),
                ],
              ),
            ),
          ],
        ),
        
        const SizedBox(height: 16),
        
        // About section (full width)
        _buildAboutSection(context),
      ],
    );
  }

  Widget _buildDesktopLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left column
        Expanded(
          flex: 2,
          child: Column(
            children: [
              _buildAccountSection(),
              const SizedBox(height: 20),
              _buildGeneralSettingsCard(),
              const SizedBox(height: 20),
              _buildFileSettingsCard(),
            ],
          ),
        ),
        
        const SizedBox(width: 24),
        
        // Right column
        Expanded(
          flex: 2,
          child: Column(
            children: [
              _buildNetworkSettingsCard(),
              const SizedBox(height: 20),
              _buildAppearanceSettingsCard(),
              const SizedBox(height: 20),
              _buildAboutSection(context),
            ],
          ),
        ),
      ],
    );
  }
  
  Widget _buildAccountSection() {
    return Card(
      child: Padding(
        padding: context.responsivePadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: EdgeInsets.all(context.isMobile ? 6 : 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4E6AF3).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.person_rounded,
                    size: context.isMobile ? 14 : 18,
                    color: Color(0xFF4E6AF3),
                  ),
                ),
                SizedBox(width: context.isMobile ? 6 : 8),
                Text(
                  'Account',
                  style: TextStyle(
                    fontSize: (context.isMobile ? 14 : 16) * context.fontSizeMultiplier,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            SizedBox(height: context.isMobile ? 12 : 16),
            
            // User info card - Responsive
            _buildUserInfoCard(),
            
            SizedBox(height: context.isMobile ? 12 : 16),
            
            // Device name editor - Responsive
            _buildDeviceNameEditor(),
          ],
        ),
      ),
    );
  }

  Widget _buildUserInfoCard() {
    return Container(
      padding: context.responsivePadding,
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
            width: context.isMobile ? 40 : 48,
            height: context.isMobile ? 40 : 48,
            decoration: const BoxDecoration(
              color: Color(0xFF4E6AF3),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                deviceName.isNotEmpty ? deviceName.substring(0, 1).toUpperCase() : 'D',
                style: TextStyle(
                  fontSize: (context.isMobile ? 16 : 20) * context.fontSizeMultiplier,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          SizedBox(width: context.isMobile ? 12 : 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  deviceName,
                  style: TextStyle(
                    fontSize: (context.isMobile ? 14 : 16) * context.fontSizeMultiplier,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: context.isMobile ? 4 : 8),
                Row(
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: context.isMobile ? 6 : 8, 
                        vertical: context.isMobile ? 2 : 4
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2AB673),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Active',
                        style: TextStyle(
                          fontSize: (context.isMobile ? 9 : 11) * context.fontSizeMultiplier,
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
    );
  }

  Widget _buildDeviceNameEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Device Name',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: (context.isMobile ? 12 : 14) * context.fontSizeMultiplier,
          ),
        ),
        SizedBox(height: context.isMobile ? 6 : 8),
        TextField(
          controller: _deviceNameController,
          decoration: InputDecoration(
            hintText: 'Enter device name',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            contentPadding: EdgeInsets.symmetric(
              horizontal: context.isMobile ? 12 : 16,
              vertical: context.isMobile ? 8 : 12,
            ),
            prefixIcon: Icon(Icons.computer_rounded),
          ),
          style: TextStyle(
            fontSize: (context.isMobile ? 12 : 14) * context.fontSizeMultiplier,
          ),
          onChanged: (value) {
            setState(() {
              deviceName = value;
            });
          },
        ),
        SizedBox(height: context.isMobile ? 4 : 6),
        Text(
          'This name will be visible to other devices',
          style: TextStyle(
            fontSize: (context.isMobile ? 10 : 12) * context.fontSizeMultiplier,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildGeneralSettingsCard() {
    return _buildSettingsCard(
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
    );
  }

  Widget _buildNetworkSettingsCard() {
    return _buildSettingsCard(
      title: 'Network Settings',
      icon: Icons.wifi_rounded,
      children: [
        _buildPortSetting(),
      ],
    );
  }

  Widget _buildFileSettingsCard() {
    return _buildSettingsCard(
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
    );
  }

  Widget _buildAppearanceSettingsCard() {
    return _buildSettingsCard(
      title: 'Appearance',
      icon: Icons.palette_rounded,
      children: [
        _buildSwitchSetting(
          title: 'Dark mode',
          subtitle: 'Use dark theme throughout the app',
          value: darkMode,
          onChanged: (value) async {
            setState(() {
              darkMode = value;
            });
            
            // Save theme preference immediately
            try {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('darkMode', value);
              
              _showSnackBar(
                'Theme will change on next app restart',
                Icons.palette_rounded,
                Color(0xFF4E6AF3),
              );
            } catch (e) {
              _showSnackBar(
                'Error saving theme preference: $e',
                Icons.error_rounded,
                Colors.red,
              );
            }
          },
          icon: Icons.dark_mode_rounded,
        ),
      ],
    );
  }
  
  Widget _buildSettingsCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Card(
      child: Padding(
        padding: context.responsivePadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: EdgeInsets.all(context.isMobile ? 6 : 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4E6AF3).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    icon,
                    size: context.isMobile ? 14 : 18,
                    color: const Color(0xFF4E6AF3),
                  ),
                ),
                SizedBox(width: context.isMobile ? 6 : 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: (context.isMobile ? 14 : 16) * context.fontSizeMultiplier,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            SizedBox(height: context.isMobile ? 12 : 16),
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
      padding: EdgeInsets.symmetric(vertical: context.isMobile ? 2 : 4),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(context.isMobile ? 6 : 8),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.grey[800]
                  : Colors.grey[200],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: context.isMobile ? 12 : 16,
              color: value ? const Color(0xFF4E6AF3) : Colors.grey,
            ),
          ),
          SizedBox(width: context.isMobile ? 8 : 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: (context.isMobile ? 12 : 14) * context.fontSizeMultiplier,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: (context.isMobile ? 10 : 12) * context.fontSizeMultiplier,
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
      padding: EdgeInsets.symmetric(vertical: context.isMobile ? 2 : 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.all(context.isMobile ? 6 : 8),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.grey[800]
                  : Colors.grey[200],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.router_rounded,
              size: context.isMobile ? 12 : 16,
              color: isPortValid ? Color(0xFF4E6AF3) : Colors.red,
            ),
          ),
          SizedBox(width: context.isMobile ? 8 : 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Port',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: (context.isMobile ? 12 : 14) * context.fontSizeMultiplier,
                  ),
                ),
                Text(
                  'Set the port number for receiving files',
                  style: TextStyle(
                    fontSize: (context.isMobile ? 10 : 12) * context.fontSizeMultiplier,
                  ),
                ),
                SizedBox(height: context.isMobile ? 6 : 8),
                SizedBox(
                  width: context.isMobile ? 120 : 140,
                  child: TextField(
                    controller: _portController,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: isPortValid ? Colors.grey : Colors.red,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: isPortValid ? Colors.grey : Colors.red,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: isPortValid ? Color(0xFF4E6AF3) : Colors.red,
                        ),
                      ),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: context.isMobile ? 8 : 12,
                        vertical: context.isMobile ? 6 : 8,
                      ),
                      errorText: portError,
                      errorStyle: TextStyle(fontSize: (context.isMobile ? 9 : 10) * context.fontSizeMultiplier),
                    ),
                    style: TextStyle(
                      fontSize: (context.isMobile ? 12 : 14) * context.fontSizeMultiplier,
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: _validatePort,
                  ),
                ),
                SizedBox(height: context.isMobile ? 4 : 6),
                Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: context.isMobile ? 10 : 12,
                      color: Colors.orange,
                    ),
                    SizedBox(width: 4),
                    Text(
                      'Requires app restart',
                      style: TextStyle(
                        fontSize: (context.isMobile ? 9 : 11) * context.fontSizeMultiplier,
                        fontStyle: FontStyle.italic,
                        color: Colors.orange,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: context.isMobile ? 2 : 4),
                Text(
                  'Valid range: $MIN_PORT - $MAX_PORT',
                  style: TextStyle(
                    fontSize: (context.isMobile ? 8 : 10) * context.fontSizeMultiplier,
                    color: Colors.grey[500],
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
      padding: EdgeInsets.symmetric(vertical: context.isMobile ? 2 : 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.all(context.isMobile ? 6 : 8),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.grey[800]
                  : Colors.grey[200],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.download_rounded,
              size: context.isMobile ? 12 : 16,
              color: Color(0xFF4E6AF3),
            ),
          ),
          SizedBox(width: context.isMobile ? 8 : 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Download Location',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: (context.isMobile ? 12 : 14) * context.fontSizeMultiplier,
                  ),
                ),
                Text(
                  'Set where received files are saved',
                  style: TextStyle(
                    fontSize: (context.isMobile ? 10 : 12) * context.fontSizeMultiplier,
                  ),
                ),
                SizedBox(height: context.isMobile ? 6 : 8),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: context.isMobile ? 8 : 12, 
                    vertical: context.isMobile ? 6 : 8
                  ),
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
                          style: TextStyle(
                            fontSize: (context.isMobile ? 10 : 12) * context.fontSizeMultiplier,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      SizedBox(width: 8),
                      TextButton(
                        onPressed: _selectDownloadFolder,
                        child: Text(
                          'Browse',
                          style: TextStyle(
                            fontSize: (context.isMobile ? 11 : 13) * context.fontSizeMultiplier,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.symmetric(
                            horizontal: context.isMobile ? 8 : 12, 
                            vertical: 0
                          ),
                        ),
                      ),
                      if (downloadPath.isNotEmpty)
                        IconButton(
                          onPressed: _openDownloadsFolder,
                          icon: Icon(Icons.folder_open, size: context.isMobile ? 14 : 16),
                          tooltip: 'Open Folder',
                          padding: EdgeInsets.all(context.isMobile ? 4 : 6),
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
          title: Text(
            title,
            style: TextStyle(
              fontSize: (context.isMobile ? 16 : 18) * context.fontSizeMultiplier,
            ),
          ),
          content: SingleChildScrollView(
            child: Text(
              content,
              style: TextStyle(
                fontSize: (context.isMobile ? 12 : 14) * context.fontSizeMultiplier,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(
                'Close',
                style: TextStyle(
                  fontSize: (context.isMobile ? 12 : 14) * context.fontSizeMultiplier,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Helper to launch external URLs
    void _launchUrl(String url) async {
      try {
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          _showSnackBar(
            'Cannot open link: $url',
            Icons.error_rounded,
            Colors.red,
          );
        }
      } catch (e) {
        _showSnackBar(
          'Error opening link: $e',
          Icons.error_rounded,
          Colors.red,
        );
      }
    }

    return Card(
      child: Padding(
        padding: context.responsivePadding,
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: EdgeInsets.all(context.isMobile ? 6 : 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4E6AF3).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.info_outline_rounded,
                    size: context.isMobile ? 14 : 18,
                    color: Color(0xFF4E6AF3),
                  ),
                ),
                SizedBox(width: context.isMobile ? 6 : 8),
                Text(
                  'About',
                  style: TextStyle(
                    fontSize: (context.isMobile ? 14 : 16) * context.fontSizeMultiplier,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            SizedBox(height: context.isMobile ? 12 : 16),

            // App logo and info - Responsive
            Column(
              children: [
                Container(
                  padding: EdgeInsets.all(context.isMobile ? 8 : 12),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF4E6AF3), Color(0xFF2AB673)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.swap_horiz_rounded,
                    size: context.isMobile ? 24 : 32,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: context.isMobile ? 8 : 12),
                Text(
                  'SpeedShare',
                  style: TextStyle(
                    fontSize: (context.isMobile ? 16 : 18) * context.fontSizeMultiplier,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF4E6AF3),
                  ),
                ),
                Text(
                  'Version 1.0.0',
                  style: TextStyle(
                    fontSize: (context.isMobile ? 10 : 12) * context.fontSizeMultiplier,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.grey[400]
                        : Colors.grey[600],
                  ),
                ),
                SizedBox(height: context.isMobile ? 12 : 16),
                Text(
                  '© 2025 SpeedShare. All rights reserved.',
                  style: TextStyle(
                    fontSize: (context.isMobile ? 9 : 11) * context.fontSizeMultiplier,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.grey[500]
                        : Colors.grey[600],
                  ),
                ),
                SizedBox(height: context.isMobile ? 6 : 8),
                
                // Policy links - Responsive
                if (context.isMobile)
                  Column(
                    children: [
                      TextButton(
                        onPressed: () {
                          _showInfoDialog(
                            'Privacy Policy',
                            'Privacy Policy\n\n'
                            'Last updated: May 29, 2025\n\n'
                            'SpeedShare values your privacy. This Privacy Policy explains how SpeedShare handles your information when you use our application to share files between two computers over the same WiFi network.\n\n'
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
                        child: Text(
                          'Privacy Policy',
                          style: TextStyle(fontSize: (context.isMobile ? 10 : 11) * context.fontSizeMultiplier),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          _showInfoDialog(
                            'Terms of Service',
                            'Terms of Service\n\n'
                            'Last updated: May 29, 2025\n\n'
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
                        child: Text(
                          'Terms of Service',
                          style: TextStyle(fontSize: (context.isMobile ? 10 : 11) * context.fontSizeMultiplier),
                        ),
                      ),
                    ],
                  )
                else
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton(
                        onPressed: () {
                          _showInfoDialog(
                            'Privacy Policy',
                            'Privacy Policy\n\n'
                            'Last updated: May 29, 2025\n\n'
                            'SpeedShare values your privacy. This Privacy Policy explains how SpeedShare handles your information when you use our application to share files between two computers over the same WiFi network.\n\n'
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
                        child: Text(
                          'Privacy Policy',
                          style: TextStyle(fontSize: (context.isMobile ? 10 : 11) * context.fontSizeMultiplier),
                        ),
                      ),
                      Text('•', style: TextStyle(color: Colors.grey)),
                      TextButton(
                        onPressed: () {
                          _showInfoDialog(
                            'Terms of Service',
                            'Terms of Service\n\n'
                            'Last updated: May 29, 2025\n\n'
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
                        child: Text(
                          'Terms of Service',
                          style: TextStyle(fontSize: (context.isMobile ? 10 : 11) * context.fontSizeMultiplier),
                        ),
                      ),
                    ],
                  ),
                
                SizedBox(height: context.isMobile ? 16 : 24),

                // Navin Kumar's details and socials - Responsive
                Column(
                  children: [
                    CircleAvatar(
                      radius: context.isMobile ? 20 : 28,
                      backgroundImage: NetworkImage(
                        'https://avatars.githubusercontent.com/u/103583078?s=400&u=80572f8430b374171aaa46ee2d9c67c3b62c3b65&v=4',
                      ),
                    ),
                    SizedBox(height: context.isMobile ? 6 : 8),
                    Text(
                      'Navin Kumar',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: (context.isMobile ? 14 : 16) * context.fontSizeMultiplier,
                      ),
                    ),
                    Text(
                      'Flutter Developer',
                      style: TextStyle(
                        fontSize: (context.isMobile ? 11 : 13) * context.fontSizeMultiplier,
                        color: Colors.grey,
                      ),
                    ),
                    SizedBox(height: context.isMobile ? 2 : 4),
                    InkWell(
                      onTap: () => _launchUrl('mailto:kumarnavinverma7@gmail.com'),
                      child: Text(
                        'kumarnavinverma7@gmail.com',
                        style: TextStyle(
                          fontSize: (context.isMobile ? 11 : 13) * context.fontSizeMultiplier,
                          color: Color(0xFF4E6AF3),
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                    SizedBox(height: context.isMobile ? 8 : 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          icon: Icon(
                            Icons.code,
                            size: context.isMobile ? 16 : 20,
                          ),
                          tooltip: 'GitHub',
                          onPressed: () => _launchUrl('https://github.com/navin280123'),
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.business,
                            size: context.isMobile ? 16 : 20,
                          ),
                          tooltip: 'LinkedIn',
                          onPressed: () => _launchUrl('https://www.linkedin.com/in/navin-kumar-verma/'),
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.alternate_email,
                            size: context.isMobile ? 16 : 20,
                          ),
                          tooltip: 'Instagram',
                          onPressed: () => _launchUrl('https://www.instagram.com/navin.2801/'),
                        ),
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