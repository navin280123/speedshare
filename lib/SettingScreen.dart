import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:animate_do/animate_do.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';

class SettingsScreen extends StatefulWidget {
  @override
  _SettingsScreenState createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // User settings
  String username = 'navin280123';
  DateTime expiryDate = DateTime(2025, 5, 15);
  
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
              Text(
                'Settings saved successfully',
                style: GoogleFonts.poppins(),
              ),
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
              Text(
                'Error saving settings',
                style: GoogleFonts.poppins(),
              ),
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
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'This will reset all settings to default values. Are you sure you want to continue?',
          style: GoogleFonts.poppins(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Cancel',
              style: GoogleFonts.poppins(
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
                      Text(
                        'Settings reset to defaults',
                        style: GoogleFonts.poppins(),
                      ),
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
              style: GoogleFonts.poppins(
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
    // Get screen size for responsive design
    final Size screenSize = MediaQuery.of(context).size;
    final bool isSmallScreen = screenSize.width < 1000;
    
    return Scaffold(
      body: FadeIn(
        duration: Duration(milliseconds: 500),
        child: Container(
          color: Colors.grey[50],
          padding: EdgeInsets.all(isSmallScreen ? 12 : 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header section
              FadeInDown(
                duration: Duration(milliseconds: 500),
                child: Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Color(0xFF4E6AF3).withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.settings_rounded,
                        size: 24,
                        color: Color(0xFF4E6AF3),
                      ),
                    ),
                    SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Settings',
                          style: GoogleFonts.poppins(
                            fontSize: isSmallScreen ? 20 : 24,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF4E6AF3),
                          ),
                        ),
                        Text(
                          'Configure your SpeedShare preferences',
                          style: GoogleFonts.poppins(
                            color: Colors.grey[600],
                            fontSize: isSmallScreen ? 12 : 14,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(height: 24),
              
              // Main content
              Expanded(
                child: loading 
                    ? Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFF4E6AF3),
                        ),
                      )
                    : isSmallScreen
                        ? _buildMobileLayout()
                        : _buildDesktopLayout(),
              ),
              
              // Save button at bottom
              SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _saveSettings,
                      icon: Icon(Icons.save_rounded),
                      label: Text(
                        'Save Settings',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: Color(0xFF2AB673),
                        padding: EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                        shadowColor: Color(0xFF2AB673).withOpacity(0.3),
                      ),
                    ),
                  ),
                  SizedBox(width: 16),
                  OutlinedButton.icon(
                    onPressed: _resetSettings,
                    icon: Icon(Icons.refresh_rounded),
                    label: Text(
                      'Reset',
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: BorderSide(color: Colors.red, width: 1.5),
                      padding: EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildMobileLayout() {
    return SingleChildScrollView(
      child: Column(
        children: [
          // Account info section
          _buildAccountSection(),
          SizedBox(height: 16),
          
          // General settings
          _buildGeneralSettings(),
          SizedBox(height: 16),
          
          // Network settings
          _buildNetworkSettings(),
          SizedBox(height: 16),
          
          // File settings
          _buildFileSettings(),
          SizedBox(height: 16),
          
          // Appearance settings
          _buildAppearanceSettings(),
        ],
      ),
    );
  }
  
  Widget _buildDesktopLayout() {
    return SingleChildScrollView(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left side
          Expanded(
            child: Column(
              children: [
                _buildAccountSection(),
                SizedBox(height: 20),
                _buildGeneralSettings(),
                SizedBox(height: 20),
                _buildNetworkSettings(),
              ],
            ),
          ),
          
          SizedBox(width: 20),
          
          // Right side
          Expanded(
            child: Column(
              children: [
                _buildFileSettings(),
                SizedBox(height: 20),
                _buildAppearanceSettings(),
                SizedBox(height: 20),
                _buildAboutSection(),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildAccountSection() {
    return FadeInUp(
      duration: Duration(milliseconds: 600),
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Color(0xFF4E6AF3).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.person_rounded,
                      color: Color(0xFF4E6AF3),
                      size: 24,
                    ),
                  ),
                  SizedBox(width: 16),
                  Text(
                    'Account Information',
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF4E6AF3),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 24),
              
              // User info
              Container(
                padding: EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color(0xFF4E6AF3).withOpacity(0.1),
                      Color(0xFF2AB673).withOpacity(0.1),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Color(0xFF4E6AF3).withOpacity(0.2),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Color(0xFF4E6AF3).withOpacity(0.2),
                            blurRadius: 8,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: CircleAvatar(
                        radius: 30,
                        backgroundColor: Color(0xFF4E6AF3).withOpacity(0.1),
                        child: Text(
                          username.substring(0, 1).toUpperCase(),
                          style: GoogleFonts.poppins(
                            color: Color(0xFF4E6AF3),
                            fontWeight: FontWeight.bold,
                            fontSize: 24,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            username,
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: Color(0xFF4E6AF3),
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Valid until: ${expiryDate.year}-${expiryDate.month.toString().padLeft(2, '0')}-${expiryDate.day.toString().padLeft(2, '0')}',
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              color: Colors.grey[700],
                            ),
                          ),
                          SizedBox(height: 8),
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Color(0xFF2AB673),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              'Active',
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              
              SizedBox(height: 16),
              
              // Device name
              TextField(
                decoration: InputDecoration(
                  labelText: 'Device Name',
                  labelStyle: GoogleFonts.poppins(
                    color: Colors.grey[700],
                  ),
                  hintText: 'Enter a name for this device',
                  hintStyle: GoogleFonts.poppins(
                    color: Colors.grey[400],
                  ),
                  prefixIcon: Icon(Icons.computer_rounded, color: Color(0xFF4E6AF3)),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Color(0xFF4E6AF3), width: 2),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                ),
                style: GoogleFonts.poppins(
                  fontSize: 15,
                ),
                controller: TextEditingController(text: deviceName),
                onChanged: (value) {
                  deviceName = value;
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildGeneralSettings() {
    return FadeInUp(
      duration: Duration(milliseconds: 700),
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Color(0xFF4E6AF3).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.tune_rounded,
                      color: Color(0xFF4E6AF3),
                      size: 24,
                    ),
                  ),
                  SizedBox(width: 16),
                  Text(
                    'General Settings',
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF4E6AF3),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 24),
              
              // Auto start
              _buildSwitchOption(
                title: 'Auto-start with system',
                subtitle: 'SpeedShare will start when your computer starts',
                value: autoStart,
                onChanged: (value) {
                  setState(() {
                    autoStart = value;
                  });
                },
                icon: Icons.play_circle_rounded,
              ),
              
              SizedBox(height: 12),
              Divider(),
              SizedBox(height: 12),
              
              // Minimize to tray
              _buildSwitchOption(
                title: 'Minimize to system tray',
                subtitle: 'Keep SpeedShare running in the background',
                value: minimizeToTray,
                onChanged: (value) {
                  setState(() {
                    minimizeToTray = value;
                  });
                },
                icon: Icons.arrow_downward_rounded,
              ),
              
              SizedBox(height: 12),
              Divider(),
              SizedBox(height: 12),
              
              // Show notifications
              _buildSwitchOption(
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
        ),
      ),
    );
  }
  
  Widget _buildNetworkSettings() {
    return FadeInUp(
      duration: Duration(milliseconds: 800),
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Color(0xFF4E6AF3).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.wifi_rounded,
                      color: Color(0xFF4E6AF3),
                      size: 24,
                    ),
                  ),
                  SizedBox(width: 16),
                  Text(
                    'Network Settings',
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF4E6AF3),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 24),
              
              // Port setting
              Text(
                'Port',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Colors.grey[800],
                ),
              ),
              SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.router_rounded, color: Colors.grey[600], size: 22),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Set the port number for receiving files',
                          style: GoogleFonts.poppins(
                            color: Colors.grey[600],
                            fontSize: 14,
                          ),
                        ),
                        SizedBox(height: 12),
                        Container(
                          width: 200,
                          child: TextField(
                            decoration: InputDecoration(
                              hintText: '8080',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                            ),
                            keyboardType: TextInputType.number,
                            controller: TextEditingController(text: port.toString()),
                            onChanged: (value) {
                              try {
                                port = int.parse(value);
                              } catch (e) {
                                // Invalid input, keep the old value
                              }
                            },
                            style: GoogleFonts.poppins(),
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Note: Changing this requires a restart of the application',
                          style: GoogleFonts.poppins(
                            color: Colors.orange[700],
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildFileSettings() {
    return FadeInUp(
      duration: Duration(milliseconds: 800),
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Color(0xFF4E6AF3).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.folder_rounded,
                      color: Color(0xFF4E6AF3),
                      size: 24,
                    ),
                  ),
                  SizedBox(width: 16),
                  Text(
                    'File Settings',
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF4E6AF3),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 24),
              
              // Download location
              Text(
                'Download Location',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Colors.grey[800],
                ),
              ),
              SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.download_rounded, color: Colors.grey[600], size: 22),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Set where received files are saved',
                          style: GoogleFonts.poppins(
                            color: Colors.grey[600],
                            fontSize: 14,
                          ),
                        ),
                        SizedBox(height: 12),
                        Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey[300]!),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Padding(
                                  padding: EdgeInsets.all(12),
                                  child: Text(
                                    downloadPath,
                                    style: GoogleFonts.poppins(
                                      fontSize: 14,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              ElevatedButton(
                                onPressed: _selectDownloadFolder,
                                style: ElevatedButton.styleFrom(
                                  foregroundColor: Color(0xFF4E6AF3),
                                  backgroundColor: Color(0xFF4E6AF3).withOpacity(0.1),
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  padding: EdgeInsets.symmetric(horizontal: 16),
                                ),
                                child: Text(
                                  'Browse',
                                  style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.bold,
                                  ),
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
              
              SizedBox(height: 16),
              Divider(),
              SizedBox(height: 16),
              
              // Keep transfer history
              _buildSwitchOption(
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
        ),
      ),
    );
  }
  
  Widget _buildAppearanceSettings() {
    return FadeInUp(
      duration: Duration(milliseconds: 900),
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Color(0xFF4E6AF3).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.palette_rounded,
                      color: Color(0xFF4E6AF3),
                      size: 24,
                    ),
                  ),
                  SizedBox(width: 16),
                  Text(
                    'Appearance',
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF4E6AF3),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 24),
              
              // Dark Mode
              _buildSwitchOption(
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
              
              SizedBox(height: 16),
              Divider(),
              SizedBox(height: 16),
              
              // Theme selection
              Text(
                'Theme Colors',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Colors.grey[800],
                ),
              ),
              SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildColorOption(Color(0xFF4E6AF3), isSelected: true),
                  _buildColorOption(Color(0xFF8B54D3)),
                  _buildColorOption(Color(0xFF2AB673)),
                  _buildColorOption(Color(0xFFE74C3C)),
                  _buildColorOption(Color(0xFF3498DB)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildAboutSection() {
    return FadeInUp(
      duration: Duration(milliseconds: 900),
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Color(0xFF4E6AF3).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.info_rounded,
                      color: Color(0xFF4E6AF3),
                      size: 24,
                    ),
                  ),
                  SizedBox(width: 16),
                  Text(
                    'About',
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF4E6AF3),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 24),
              
              // App info
              Center(
                child: Column(
                  children: [
                    Container(
                      padding: EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF4E6AF3), Color(0xFF2AB673)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Color(0xFF4E6AF3).withOpacity(0.3),
                            blurRadius: 15,
                            offset: Offset(0, 5),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.swap_horiz_rounded,
                        size: 48,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 16),
                    Text(
                      'SpeedShare',
                      style: GoogleFonts.poppins(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        foreground: Paint()
                          ..shader = LinearGradient(
                            colors: [Color(0xFF4E6AF3), Color(0xFF2AB673)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ).createShader(Rect.fromLTWH(0, 0, 200, 70)),
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Version 1.0.0',
                      style: GoogleFonts.poppins(
                        color: Colors.grey[600],
                        fontSize: 14,
                      ),
                    ),
                    SizedBox(height: 24),
                    Text(
                      '© 2025 navin280123. All rights reserved.',
                      style: GoogleFonts.poppins(
                        color: Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                    SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TextButton(
                          onPressed: () {
                            // Open Privacy Policy
                          },
                          child: Text(
                            'Privacy Policy',
                            style: GoogleFonts.poppins(
                              color: Color(0xFF4E6AF3),
                              fontSize: 12,
                            ),
                          ),
                        ),
                        Text('•', style: TextStyle(color: Colors.grey)),
                        TextButton(
                          onPressed: () {
                            // Open Terms of Service
                          },
                          child: Text(
                            'Terms of Service',
                            style: GoogleFonts.poppins(
                              color: Color(0xFF4E6AF3),
                              fontSize: 12,
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
      ),
    );
  }
  
  Widget _buildSwitchOption({
    required String title,
    required String subtitle,
    required bool value,
    required Function(bool) onChanged,
    required IconData icon,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Colors.grey[600], size: 22),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Colors.grey[800],
                ),
              ),
              SizedBox(height: 4),
              Text(
                subtitle,
                style: GoogleFonts.poppins(
                  color: Colors.grey[600],
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeColor: Color(0xFF2AB673),
          activeTrackColor: Color(0xFF2AB673).withOpacity(0.3),
        ),
      ],
    );
  }
  
  Widget _buildColorOption(Color color, {bool isSelected = false}) {
    return InkWell(
      onTap: () {
        // Handle color selection
      },
      borderRadius: BorderRadius.circular(30),
      child: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.3),
              blurRadius: 8,
              offset: Offset(0, 3),
            ),
          ],
          border: isSelected
              ? Border.all(color: Colors.white, width: 3)
              : null,
        ),
        child: isSelected
            ? Icon(
                Icons.check,
                color: Colors.white,
              )
            : null,
      ),
    );
  }
}