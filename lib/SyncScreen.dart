import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lottie/lottie.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:mime/mime.dart';
import 'package:speedshare/main.dart';

/// True when on a desktop platform (reusePort is only available on non-Windows).
bool get _supportsReusePort =>
    !kIsWeb && (Platform.isMacOS || Platform.isLinux);

class SyncScreen extends StatefulWidget {
  @override
  _SyncScreenState createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> with TickerProviderStateMixin {
  // Constants
  static const int SYNC_HTTP_PORT_START = 8082;
  static const int SYNC_UDP_PORT = 8083;
  static const int MAX_FILE_SIZE = 10 * 1024 * 1024 * 1024; // 10GB
  static const int DISCOVERY_INTERVAL = 10; // seconds
  static const int DEVICE_TIMEOUT = 5; // minutes

  // Storage Server
  HttpServer? _storageServer;
  RawDatagramSocket? _syncDiscoverySocket;
  String? _accessCode;
  bool _isStorageSharing = false;
  List<String> _sharedPaths = [];
  List<SyncSession> _activeSessions = [];
  int _actualServerPort = SYNC_HTTP_PORT_START;

  // Storage Browser
  List<SyncDevice> _availableDevices = [];
  bool _isDiscovering = false;
  Timer? _discoveryTimer;

  // UI State
  late TabController _tabController;
  // _selectedDirectory: reserved for future directory browser feature
  SyncDevice? _selectedDevice;
  List<RemoteFileInfo> _remoteFiles = [];
  bool _isBrowsingFiles = false;
  String _currentRemotePath = '/';
  List<DownloadTask> _downloadQueue = [];

  // Dynamic values instead of hardcoded
  String get currentDateTime => DateTime.now().toString();
  String get userLogin => Platform.localHostname;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _initializeSync();
    _loadSettings();
    _startDiscovery();
  }

  Future<void> _initializeSync() async {
    try {
      // Close existing socket if any
      _syncDiscoverySocket?.close();

      print('Initializing UDP discovery socket...');

      // Initialize sync discovery socket with proper error handling
      _syncDiscoverySocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        SYNC_UDP_PORT,
        reuseAddress: true,
        // reusePort is not supported on Windows — only enable on macOS/Linux
        reusePort: _supportsReusePort,
      );

      _syncDiscoverySocket!.broadcastEnabled = true;

      _syncDiscoverySocket!.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = _syncDiscoverySocket!.receive();
          if (datagram != null) {
            print(
                'Received discovery message from ${datagram.address.address}');
            _handleSyncDiscovery(datagram);
          }
        }
      }, onError: (error) {
        print('UDP Discovery error: $error');
        _showSnackBar(
          'Network discovery error: $error',
          Icons.error_rounded,
          Colors.red,
        );
      });

      print(
          'UDP Discovery socket initialized successfully on port $SYNC_UDP_PORT');
    } catch (e) {
      print('Error initializing sync on port $SYNC_UDP_PORT: $e');
      // Try alternative port if main port is busy
      try {
        _syncDiscoverySocket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          SYNC_UDP_PORT + 1,
          reuseAddress: true,
          // reusePort is not supported on Windows
          reusePort: _supportsReusePort,
        );
        _syncDiscoverySocket!.broadcastEnabled = true;

        _syncDiscoverySocket!.listen((event) {
          if (event == RawSocketEvent.read) {
            final datagram = _syncDiscoverySocket!.receive();
            if (datagram != null) {
              print(
                  'Received discovery message from ${datagram.address.address} (alt port)');
              _handleSyncDiscovery(datagram);
            }
          }
        }, onError: (error) {
          print('UDP Discovery error on alt port: $error');
        });

        print(
            'UDP Discovery socket initialized on alternative port ${SYNC_UDP_PORT + 1}');
      } catch (e2) {
        print('Failed to initialize UDP socket on alternative port: $e2');
        _showSnackBar(
          'Failed to initialize network discovery',
          Icons.error_rounded,
          Colors.red,
        );
      }
    }
  }

  void _handleSyncDiscovery(Datagram datagram) {
    try {
      final message = utf8.decode(datagram.data);
      print('Received raw message: $message from ${datagram.address.address}');

      final data = json.decode(message) as Map<String, dynamic>;

      if (data['type'] == 'SPEEDSHARE_SYNC_ANNOUNCE') {
        // Validate required fields
        if (!data.containsKey('deviceName') ||
            !data.containsKey('storagePort') ||
            !data.containsKey('accessCode')) {
          print('Invalid announcement message: missing required fields');
          return;
        }

        final device = SyncDevice(
          name: data['deviceName'],
          ip: datagram.address.address,
          port: data['storagePort'],
          accessCode: data['accessCode'],
          capabilities: List<String>.from(data['capabilities'] ?? []),
          lastSeen: DateTime.now(),
        );

        print(
            'Found device: ${device.name} at ${device.ip}:${device.port} with code: ${device.accessCode}');

        setState(() {
          _availableDevices.removeWhere((d) => d.ip == device.ip);
          _availableDevices.add(device);
        });
      }
    } catch (e) {
      print('Error handling sync discovery: $e');
    }
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedPaths = prefs.getStringList('sync_shared_paths') ?? [];
      setState(() {
        _sharedPaths = savedPaths;
      });
      print('Loaded ${_sharedPaths.length} shared paths from settings');
    } catch (e) {
      print('Error loading sync settings: $e');
      _showSnackBar(
        'Error loading sync settings: $e',
        Icons.error_rounded,
        Colors.red,
      );
    }
  }

  Future<void> _saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('sync_shared_paths', _sharedPaths);
      print('Saved ${_sharedPaths.length} shared paths to settings');
    } catch (e) {
      print('Error saving sync settings: $e');
      _showSnackBar(
        'Error saving sync settings: $e',
        Icons.error_rounded,
        Colors.red,
      );
    }
  }

  void _startDiscovery() {
    print('Starting discovery timer...');
    _discoveryTimer =
        Timer.periodic(Duration(seconds: DISCOVERY_INTERVAL), (timer) {
      _sendSyncAnnouncement();
      _cleanupStaleDevices();
    });
    _sendSyncAnnouncement();
  }

  void _sendSyncAnnouncement() {
    if (_syncDiscoverySocket == null || !_isStorageSharing) {
      print(
          'Skipping announcement: socket=${_syncDiscoverySocket != null}, sharing=$_isStorageSharing');
      return;
    }

    try {
      final announcement = json.encode({
        'type': 'SPEEDSHARE_SYNC_ANNOUNCE',
        'deviceName': Platform.localHostname,
        'storagePort': _actualServerPort,
        'accessCode': _accessCode,
        'capabilities': ['storage_share', 'storage_browse'],
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'version': '1.0.0',
        'user': userLogin,
      });

      final data = utf8.encode(announcement);

      print('Sending announcement: $announcement');

      // Send to broadcast addresses
      _sendToBroadcastAddresses(data);

      // Also try sending to local network interfaces
      _sendToLocalInterfaces(data);
    } catch (e) {
      print('Error sending sync announcement: $e');
    }
  }

  void _sendToBroadcastAddresses(List<int> data) {
    final broadcastAddresses = [
      '255.255.255.255', // Global broadcast
      '192.168.1.255', // Common subnet
      '192.168.0.255', // Common subnet
      '10.0.0.255', // Common subnet
      '172.16.255.255', // Private network
    ];

    int successCount = 0;
    for (String address in broadcastAddresses) {
      try {
        _syncDiscoverySocket!
            .send(data, InternetAddress(address), SYNC_UDP_PORT);
        _syncDiscoverySocket!
            .send(data, InternetAddress(address), SYNC_UDP_PORT + 1);
        successCount++;
        print('Sent announcement to $address');
      } catch (e) {
        print('Failed to send to $address: $e');
      }
    }

    print('Announcement sent to $successCount broadcast addresses');
  }

  Future<void> _sendToLocalInterfaces(List<int> data) async {
    try {
      for (var interface in await NetworkInterface.list()) {
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            try {
              // Calculate broadcast address for this subnet
              final parts = addr.address.split('.');
              if (parts.length == 4) {
                final broadcastAddr = '${parts[0]}.${parts[1]}.${parts[2]}.255';
                _syncDiscoverySocket!
                    .send(data, InternetAddress(broadcastAddr), SYNC_UDP_PORT);
                _syncDiscoverySocket!.send(
                    data, InternetAddress(broadcastAddr), SYNC_UDP_PORT + 1);
                print('Sent to interface broadcast: $broadcastAddr');
              }
            } catch (e) {
              print('Failed to send to interface ${addr.address}: $e');
            }
          }
        }
      }
    } catch (e) {
      print('Error getting network interfaces: $e');
    }
  }

  void _cleanupStaleDevices() {
    final now = DateTime.now();
    final before = _availableDevices.length;
    setState(() {
      _availableDevices.removeWhere((device) =>
          now.difference(device.lastSeen).inMinutes > DEVICE_TIMEOUT);
    });
    final after = _availableDevices.length;
    if (before != after) {
      print('Cleaned up ${before - after} stale devices');
    }
  }

  Future<void> _startStorageSharing() async {
    if (_sharedPaths.isEmpty) {
      _showSnackBar(
        'Please select at least one directory to share',
        Icons.warning_rounded,
        Colors.orange,
      );
      return;
    }

    try {
      print('Starting storage sharing...');

      // Close existing server if any
      await _storageServer?.close();

      _accessCode = _generateAccessCode();

      // Try to bind to port with fallback options
      HttpServer? server;
      int port = SYNC_HTTP_PORT_START;

      for (int attempts = 0; attempts < 5; attempts++) {
        try {
          server =
              await HttpServer.bind(InternetAddress.anyIPv4, port + attempts);
          _actualServerPort = port + attempts;
          break;
        } catch (e) {
          print('Failed to bind to port ${port + attempts}: $e');
          if (attempts == 4) rethrow;
        }
      }

      _storageServer = server;

      // Add CORS headers for web compatibility
      _storageServer!.listen((request) {
        print('Received ${request.method} request: ${request.uri}');

        // Add CORS headers
        request.response.headers.add('Access-Control-Allow-Origin', '*');
        request.response.headers
            .add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
        request.response.headers
            .add('Access-Control-Allow-Headers', 'Content-Type');

        if (request.method == 'OPTIONS') {
          request.response.statusCode = 200;
          request.response.close();
          return;
        }

        _handleStorageRequest(request);
      });

      setState(() {
        _isStorageSharing = true;
      });

      print(
          'Storage server started on port $_actualServerPort with access code: $_accessCode');

      // Start sending announcements
      _sendSyncAnnouncement();

      _showSnackBar(
        'Storage sharing started on port $_actualServerPort',
        Icons.check_circle_rounded,
        Color(0xFF2AB673),
      );
    } catch (e) {
      print('Failed to start storage sharing: $e');
      _showSnackBar(
        'Failed to start storage sharing: $e',
        Icons.error_rounded,
        Colors.red,
      );
    }
  }

  Future<void> _stopStorageSharing() async {
    try {
      print('Stopping storage sharing...');
      await _storageServer?.close();
      _storageServer = null;
      _accessCode = null;

      setState(() {
        _isStorageSharing = false;
        _activeSessions.clear();
      });

      print('Storage sharing stopped');
      _showSnackBar(
        'Storage sharing stopped',
        Icons.info_rounded,
        Colors.orange,
      );
    } catch (e) {
      print('Failed to stop storage sharing: $e');
      _showSnackBar(
        'Failed to stop storage sharing: $e',
        Icons.error_rounded,
        Colors.red,
      );
    }
  }

  void _handleStorageRequest(HttpRequest request) async {
    try {
      final uri = request.uri;
      final accessCode = uri.queryParameters['code'];

      print('Handling request: ${uri.path} with code: $accessCode');

      if (accessCode != _accessCode) {
        print(
            'Invalid access code provided: $accessCode, expected: $_accessCode');
        request.response.statusCode = 403;
        request.response.write('Invalid access code');
        await request.response.close();
        return;
      }

      if (uri.path.startsWith('/api/files')) {
        await _handleFileListRequest(request);
      } else if (uri.path.startsWith('/api/download')) {
        await _handleFileDownloadRequest(request);
      } else {
        print('Unknown API path: ${uri.path}');
        request.response.statusCode = 404;
        await request.response.close();
      }
    } catch (e) {
      print('Error handling storage request: $e');
      request.response.statusCode = 500;
      request.response.write('Internal server error: $e');
      await request.response.close();
    }
  }

  Future<void> _handleFileListRequest(HttpRequest request) async {
    final path = request.uri.queryParameters['path'] ?? '/';
    final files = <Map<String, dynamic>>[];

    print('Listing files for path: $path');

    try {
      for (final sharedPath in _sharedPaths) {
        print('Checking shared path: $sharedPath');

        final targetPath = path == '/'
            ? sharedPath
            : p.join(sharedPath, path.replaceFirst('/', ''));
        final directory = Directory(targetPath);

        print('Target directory: ${directory.path}');

        if (await directory.exists()) {
          await for (final entity in directory.list()) {
            try {
              final stat = await entity.stat();
              final fileInfo = {
                'name': p.basename(entity.path),
                'path': entity.path,
                'isDirectory': entity is Directory,
                'size': entity is File ? stat.size : 0,
                'modified': stat.modified.toIso8601String(),
                'type': entity is File
                    ? (lookupMimeType(entity.path) ??
                        'application/octet-stream')
                    : 'directory',
              };
              files.add(fileInfo);
              print('Added file: ${fileInfo['name']}');
            } catch (e) {
              print('Error processing entity ${entity.path}: $e');
            }
          }
        } else {
          print('Directory does not exist: ${directory.path}');
        }
      }

      print('Returning ${files.length} files');
      request.response.headers.contentType = ContentType.json;
      request.response.write(json.encode(files));
    } catch (e) {
      print('Error listing files: $e');
      request.response.statusCode = 500;
      request.response.write('Error listing files: $e');
    }

    await request.response.close();
  }

  Future<void> _handleFileDownloadRequest(HttpRequest request) async {
    final filePath = request.uri.queryParameters['file'];

    print('Download request for file: $filePath');

    if (filePath == null || !_isPathAllowed(filePath)) {
      print('Access denied for file: $filePath');
      request.response.statusCode = 403;
      request.response.write('Access denied');
      await request.response.close();
      return;
    }

    try {
      final file = File(filePath);
      if (await file.exists()) {
        final fileSize = await file.length();

        // Validate file size
        if (fileSize > MAX_FILE_SIZE) {
          print('File too large: $filePath ($fileSize bytes)');
          request.response.statusCode = 413;
          request.response.write('File too large');
          await request.response.close();
          return;
        }

        print('Serving file: $filePath (${fileSize} bytes)');

        request.response.headers.contentType = ContentType.binary;
        request.response.headers.add('Content-Length', fileSize.toString());
        request.response.headers.add('Content-Disposition',
            'attachment; filename="${p.basename(filePath)}"');

        await file.openRead().pipe(request.response);
      } else {
        print('File not found: $filePath');
        request.response.statusCode = 404;
        request.response.write('File not found');
        await request.response.close();
      }
    } catch (e) {
      print('Error downloading file: $e');
      request.response.statusCode = 500;
      request.response.write('Error downloading file: $e');
      await request.response.close();
    }
  }

  bool _isPathAllowed(String filePath) {
    final allowed =
        _sharedPaths.any((sharedPath) => filePath.startsWith(sharedPath));
    print('Path $filePath allowed: $allowed');
    return allowed;
  }

  String _generateAccessCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rng = Random.secure();
    final code =
        List.generate(6, (_) => chars[rng.nextInt(chars.length)]).join();
    return code;
  }

  Future<void> _addSharedDirectory() async {
    try {
      final result = await FilePicker.platform.getDirectoryPath();
      if (result != null) {
        // Validate directory exists and is accessible
        final directory = Directory(result);
        if (await directory.exists()) {
          print('Adding shared directory: $result');
          setState(() {
            if (!_sharedPaths.contains(result)) {
              _sharedPaths.add(result);
            }
          });
          await _saveSettings();
          _showSnackBar(
            'Directory added to shared folders',
            Icons.check_circle_rounded,
            Color(0xFF2AB673),
          );
        } else {
          _showSnackBar(
            'Selected directory is not accessible',
            Icons.error_rounded,
            Colors.red,
          );
        }
      }
    } catch (e) {
      print('Error adding shared directory: $e');
      _showSnackBar(
        'Error adding directory: $e',
        Icons.error_rounded,
        Colors.red,
      );
    }
  }

  void _removeSharedDirectory(String path) {
    print('Removing shared directory: $path');
    setState(() {
      _sharedPaths.remove(path);
    });
    _saveSettings();
    _showSnackBar(
      'Directory removed from shared folders',
      Icons.info_rounded,
      Colors.orange,
    );
  }

  Future<void> _browseDevice(SyncDevice device) async {
    print('Browsing device: ${device.name} at ${device.ip}:${device.port}');
    setState(() {
      _selectedDevice = device;
      _isBrowsingFiles = true;
      _currentRemotePath = '/';
    });

    await _loadRemoteFiles('/');
  }

  Future<void> _loadRemoteFiles(String path) async {
    if (_selectedDevice == null) return;

    print('Loading remote files from path: $path');

    try {
      final url =
          'http://${_selectedDevice!.ip}:${_selectedDevice!.port}/api/files?path=${Uri.encodeComponent(path)}&code=${_selectedDevice!.accessCode}';
      print('Making request to: $url');

      final response = await http.get(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
      ).timeout(Duration(seconds: 10));

      print('Response status: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        setState(() {
          _remoteFiles =
              data.map((item) => RemoteFileInfo.fromJson(item)).toList();
          _currentRemotePath = path;
        });
        print('Loaded ${_remoteFiles.length} remote files');
      } else {
        print(
            'Failed to load files: ${response.statusCode} - ${response.body}');
        _showSnackBar(
          'Failed to load files: ${response.statusCode}',
          Icons.error_rounded,
          Colors.red,
        );
      }
    } catch (e) {
      print('Error loading remote files: $e');
      _showSnackBar(
        'Error loading files: $e',
        Icons.error_rounded,
        Colors.red,
      );
    }
  }

  Future<void> _downloadFile(RemoteFileInfo file) async {
    if (_selectedDevice == null) return;

    print('Downloading file: ${file.name}');

    try {
      final downloadsDir = await getDownloadsDirectory();
      final savePath = p.join(downloadsDir!.path, 'speedshare', file.name);

      // Create directory if it doesn't exist
      await Directory(p.dirname(savePath)).create(recursive: true);

      final downloadTask = DownloadTask(
        file: file,
        savePath: savePath,
        progress: 0.0,
        status: 'Starting',
      );

      setState(() {
        _downloadQueue.add(downloadTask);
      });

      final url =
          'http://${_selectedDevice!.ip}:${_selectedDevice!.port}/api/download?file=${Uri.encodeComponent(file.path)}&code=${_selectedDevice!.accessCode}';
      print('Downloading from: $url');

      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        await File(savePath).writeAsBytes(response.bodyBytes);

        setState(() {
          downloadTask.progress = 1.0;
          downloadTask.status = 'Completed';
        });

        print('Download completed: ${file.name}');
        _showSnackBar(
          'Downloaded: ${file.name}',
          Icons.check_circle_rounded,
          Color(0xFF2AB673),
        );
      } else {
        setState(() {
          downloadTask.status = 'Failed';
        });
        print('Download failed: ${response.statusCode}');
        _showSnackBar(
          'Download failed: ${response.statusCode}',
          Icons.error_rounded,
          Colors.red,
        );
      }
    } catch (e) {
      print('Error downloading file: $e');
      _showSnackBar(
        'Error downloading file: $e',
        Icons.error_rounded,
        Colors.red,
      );
    }
  }

  void _showSnackBar(String message, IconData icon, Color color,
      {SnackBarAction? action}) {
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

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024)
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  @override
  void dispose() {
    print('Disposing SyncScreen...');
    _tabController.dispose();
    _discoveryTimer?.cancel();
    _storageServer?.close();
    _syncDiscoverySocket?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: context.responsivePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header - Responsive
          _buildHeader(),

          SizedBox(height: context.isMobile ? 12 : 20),

          // Tab bar - Responsive
          _buildTabBar(),

          SizedBox(height: context.isMobile ? 12 : 16),

          // Tab content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildShareStorageTab(),
                _buildAccessStorageTab(),
              ],
            ),
          ),
        ],
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
            Icons.sync_rounded,
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
                'Sync',
                style: TextStyle(
                  fontSize:
                      (context.isMobile ? 18 : 20) * context.fontSizeMultiplier,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF4E6AF3),
                ),
              ),
              Text(
                'Share and access device storage',
                style: TextStyle(
                  fontSize:
                      (context.isMobile ? 11 : 13) * context.fontSizeMultiplier,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.grey[400]
                      : Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
        // Status indicator - Responsive
        Container(
          padding: EdgeInsets.symmetric(
              horizontal: context.isMobile ? 8 : 12,
              vertical: context.isMobile ? 4 : 6),
          decoration: BoxDecoration(
            color: _isStorageSharing ? const Color(0xFF2AB673) : Colors.grey,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            _isStorageSharing ? 'Sharing Active' : 'Inactive',
            style: TextStyle(
              color: Colors.white,
              fontSize:
                  (context.isMobile ? 10 : 12) * context.fontSizeMultiplier,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTabBar() {
    return TabBar(
      controller: _tabController,
      labelColor: const Color(0xFF4E6AF3),
      unselectedLabelColor: Colors.grey,
      indicatorColor: const Color(0xFF4E6AF3),
      labelStyle: TextStyle(
        fontSize: (context.isMobile ? 13 : 14) * context.fontSizeMultiplier,
        fontWeight: FontWeight.bold,
      ),
      unselectedLabelStyle: TextStyle(
        fontSize: (context.isMobile ? 13 : 14) * context.fontSizeMultiplier,
      ),
      tabs: const [
        Tab(text: 'Share Storage'),
        Tab(text: 'Access Storage'),
      ],
    );
  }

  Widget _buildShareStorageTab() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Storage sharing status - Responsive
          _buildStorageSharingCard(),

          SizedBox(height: context.isMobile ? 12 : 16),

          // Shared directories - Responsive
          _buildSharedDirectoriesCard(),
        ],
      ),
    );
  }

  Widget _buildStorageSharingCard() {
    return Card(
      child: Padding(
        padding: context.responsivePadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _isStorageSharing
                      ? Icons.share_rounded
                      : Icons.share_outlined,
                  color:
                      _isStorageSharing ? const Color(0xFF2AB673) : Colors.grey,
                  size: context.isMobile ? 16 : 20,
                ),
                SizedBox(width: context.isMobile ? 6 : 8),
                Text(
                  'Storage Sharing',
                  style: TextStyle(
                    fontSize: (context.isMobile ? 14 : 16) *
                        context.fontSizeMultiplier,
                    fontWeight: FontWeight.bold,
                    color: _isStorageSharing ? const Color(0xFF2AB673) : null,
                  ),
                ),
              ],
            ),
            SizedBox(height: context.isMobile ? 10 : 12),

            if (_isStorageSharing) ...[
              // Access code display - Responsive
              _buildAccessCodeSection(),
              SizedBox(height: context.isMobile ? 6 : 8),
              Text(
                'Active sessions: ${_activeSessions.length} • Port: $_actualServerPort',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize:
                      (context.isMobile ? 11 : 13) * context.fontSizeMultiplier,
                ),
              ),
            ],

            SizedBox(height: context.isMobile ? 12 : 16),

            // Control button - Responsive
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isStorageSharing
                    ? _stopStorageSharing
                    : (_sharedPaths.isNotEmpty ? _startStorageSharing : null),
                icon: Icon(
                  _isStorageSharing ? Icons.stop : Icons.play_arrow,
                  size: context.isMobile ? 16 : 18,
                ),
                label: Text(
                  _isStorageSharing ? 'Stop Sharing' : 'Start Sharing',
                  style: TextStyle(
                    fontSize: (context.isMobile ? 13 : 14) *
                        context.fontSizeMultiplier,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor:
                      _isStorageSharing ? Colors.red : const Color(0xFF2AB673),
                  padding: EdgeInsets.symmetric(
                      vertical: context.isMobile ? 12 : 16),
                  disabledBackgroundColor: Colors.grey[400],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccessCodeSection() {
    if (context.isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Access Code:',
            style: TextStyle(
              fontSize:
                  (context.isMobile ? 12 : 14) * context.fontSizeMultiplier,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4E6AF3).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _accessCode ?? '',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF4E6AF3),
                      fontSize: (context.isMobile ? 14 : 16) *
                          context.fontSizeMultiplier,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(Icons.copy, size: context.isMobile ? 14 : 16),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _accessCode ?? ''));
                  _showSnackBar(
                    'Access code copied to clipboard',
                    Icons.check_circle_rounded,
                    Color(0xFF2AB673),
                  );
                },
                tooltip: 'Copy access code',
              ),
            ],
          ),
        ],
      );
    }

    return Row(
      children: [
        Text(
          'Access Code: ',
          style: TextStyle(
            fontSize: (context.isMobile ? 12 : 14) * context.fontSizeMultiplier,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF4E6AF3).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            _accessCode ?? '',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Color(0xFF4E6AF3),
              fontSize:
                  (context.isMobile ? 12 : 14) * context.fontSizeMultiplier,
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          icon: Icon(Icons.copy, size: context.isMobile ? 14 : 16),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: _accessCode ?? ''));
            _showSnackBar(
              'Access code copied to clipboard',
              Icons.check_circle_rounded,
              Color(0xFF2AB673),
            );
          },
          tooltip: 'Copy access code',
        ),
      ],
    );
  }

  Widget _buildSharedDirectoriesCard() {
    return Card(
      child: Padding(
        padding: context.responsivePadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Shared Directories',
                  style: TextStyle(
                    fontSize: (context.isMobile ? 14 : 16) *
                        context.fontSizeMultiplier,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextButton.icon(
                  onPressed: _addSharedDirectory,
                  icon: Icon(Icons.add, size: context.isMobile ? 14 : 16),
                  label: Text(
                    context.isMobile ? 'Add' : 'Add Directory',
                    style: TextStyle(
                      fontSize: (context.isMobile ? 11 : 13) *
                          context.fontSizeMultiplier,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: context.isMobile ? 8 : 12),
            if (_sharedPaths.isEmpty)
              _buildEmptySharedDirectories()
            else
              _buildSharedDirectoriesList(),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptySharedDirectories() {
    return Container(
      padding: EdgeInsets.all(context.isMobile ? 16 : 20),
      child: Column(
        children: [
          Icon(
            Icons.folder_open,
            size: context.isMobile ? 36 : 48,
            color: Colors.grey[400],
          ),
          SizedBox(height: context.isMobile ? 6 : 8),
          Text(
            'No directories shared',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize:
                  (context.isMobile ? 12 : 14) * context.fontSizeMultiplier,
            ),
          ),
          SizedBox(height: context.isMobile ? 2 : 4),
          Text(
            'Add directories to share with other devices',
            style: TextStyle(
              color: Colors.grey[500],
              fontSize:
                  (context.isMobile ? 10 : 12) * context.fontSizeMultiplier,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSharedDirectoriesList() {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _sharedPaths.length,
      itemBuilder: (context, index) {
        final path = _sharedPaths[index];
        return ListTile(
          dense: context.isMobile,
          contentPadding: EdgeInsets.symmetric(
            horizontal: context.isMobile ? 8 : 16,
            vertical: context.isMobile ? 0 : 4,
          ),
          leading: Icon(
            Icons.folder,
            color: Color(0xFF4E6AF3),
            size: context.isMobile ? 16 : 20,
          ),
          title: Text(
            p.basename(path),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize:
                  (context.isMobile ? 12 : 14) * context.fontSizeMultiplier,
            ),
          ),
          subtitle: Text(
            path,
            style: TextStyle(
                fontSize:
                    (context.isMobile ? 10 : 12) * context.fontSizeMultiplier,
                color: Colors.grey[600]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: IconButton(
            icon: Icon(
              Icons.remove_circle,
              color: Colors.red,
              size: context.isMobile ? 16 : 20,
            ),
            onPressed: () => _removeSharedDirectory(path),
            tooltip: 'Remove directory',
          ),
        );
      },
    );
  }

  Widget _buildAccessStorageTab() {
    if (_isBrowsingFiles && _selectedDevice != null) {
      return _buildFileBrowser();
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Device discovery - Responsive
          _buildDeviceDiscoveryCard(),

          // Download queue - Responsive
          if (_downloadQueue.isNotEmpty) ...[
            SizedBox(height: context.isMobile ? 12 : 16),
            _buildDownloadQueueCard(),
          ],
        ],
      ),
    );
  }

  Widget _buildDeviceDiscoveryCard() {
    return Card(
      child: Padding(
        padding: context.responsivePadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.devices,
                  color: Color(0xFF4E6AF3),
                  size: context.isMobile ? 16 : 20,
                ),
                SizedBox(width: context.isMobile ? 6 : 8),
                Text(
                  'Available Devices',
                  style: TextStyle(
                    fontSize: (context.isMobile ? 14 : 16) *
                        context.fontSizeMultiplier,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                if (_isDiscovering)
                  SizedBox(
                    width: context.isMobile ? 14 : 16,
                    height: context.isMobile ? 14 : 16,
                    child: const CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            SizedBox(height: context.isMobile ? 8 : 12),
            if (_availableDevices.isEmpty)
              _buildEmptyDevicesList()
            else
              _buildDevicesList(),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyDevicesList() {
    return Container(
      padding: EdgeInsets.all(context.isMobile ? 16 : 20),
      child: Column(
        children: [
          Lottie.asset(
            'assets/searchss.json',
            height: context.isMobile ? 60 : 80,
            errorBuilder: (context, error, stackTrace) {
              return Icon(
                Icons.search_off,
                size: context.isMobile ? 36 : 48,
                color: Colors.grey[400],
              );
            },
          ),
          SizedBox(height: context.isMobile ? 6 : 8),
          Text(
            'No devices found',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize:
                  (context.isMobile ? 12 : 14) * context.fontSizeMultiplier,
            ),
          ),
          SizedBox(height: context.isMobile ? 2 : 4),
          Text(
            'Make sure other devices are sharing storage',
            style: TextStyle(
              color: Colors.grey[500],
              fontSize:
                  (context.isMobile ? 10 : 12) * context.fontSizeMultiplier,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDevicesList() {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _availableDevices.length,
      itemBuilder: (context, index) {
        final device = _availableDevices[index];
        return Card(
          margin: EdgeInsets.only(bottom: context.isMobile ? 6 : 8),
          child: ListTile(
            dense: context.isMobile,
            contentPadding: EdgeInsets.symmetric(
              horizontal: context.isMobile ? 8 : 12,
              vertical: context.isMobile ? 4 : 8,
            ),
            leading: Container(
              padding: EdgeInsets.all(context.isMobile ? 6 : 8),
              decoration: BoxDecoration(
                color: const Color(0xFF2AB673).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                device.name.toLowerCase().contains('mobile') ||
                        device.name.toLowerCase().contains('phone')
                    ? Icons.phone_android
                    : Icons.computer,
                color: const Color(0xFF2AB673),
                size: context.isMobile ? 16 : 20,
              ),
            ),
            title: Text(
              device.name,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize:
                    (context.isMobile ? 12 : 14) * context.fontSizeMultiplier,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'IP: ${device.ip}:${device.port}',
                  style: TextStyle(
                    fontSize: (context.isMobile ? 10 : 12) *
                        context.fontSizeMultiplier,
                  ),
                ),
                Text(
                  'Last seen: ${_getTimeAgo(device.lastSeen)} • Code: ${device.accessCode}',
                  style: TextStyle(
                      fontSize: (context.isMobile ? 9 : 11) *
                          context.fontSizeMultiplier,
                      color: Colors.grey[500]),
                ),
              ],
            ),
            trailing: ElevatedButton(
              onPressed: () => _browseDevice(device),
              child: Text(
                'Browse',
                style: TextStyle(
                  fontSize:
                      (context.isMobile ? 11 : 13) * context.fontSizeMultiplier,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4E6AF3),
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(
                  horizontal: context.isMobile ? 8 : 12,
                  vertical: context.isMobile ? 4 : 8,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDownloadQueueCard() {
    return Card(
      child: Padding(
        padding: context.responsivePadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Download Queue',
              style: TextStyle(
                fontSize:
                    (context.isMobile ? 14 : 16) * context.fontSizeMultiplier,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: context.isMobile ? 8 : 12),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _downloadQueue.length,
              itemBuilder: (context, index) {
                final task = _downloadQueue[index];
                return ListTile(
                  dense: context.isMobile,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: context.isMobile ? 8 : 16,
                    vertical: context.isMobile ? 0 : 4,
                  ),
                  leading: Icon(
                    _getFileIcon(task.file.type),
                    color: _getFileIconColor(task.file.type),
                    size: context.isMobile ? 16 : 20,
                  ),
                  title: Text(
                    task.file.name,
                    style: TextStyle(
                      fontSize: (context.isMobile ? 12 : 14) *
                          context.fontSizeMultiplier,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.status,
                        style: TextStyle(
                          fontSize: (context.isMobile ? 10 : 12) *
                              context.fontSizeMultiplier,
                        ),
                      ),
                      if (task.progress > 0 && task.progress < 1)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: LinearProgressIndicator(
                            value: task.progress,
                            minHeight: context.isMobile ? 3 : 4,
                          ),
                        ),
                    ],
                  ),
                  trailing: task.status == 'Completed'
                      ? Icon(
                          Icons.check_circle,
                          color: Color(0xFF2AB673),
                          size: context.isMobile ? 16 : 20,
                        )
                      : task.status == 'Failed'
                          ? Icon(
                              Icons.error,
                              color: Colors.red,
                              size: context.isMobile ? 16 : 20,
                            )
                          : null,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileBrowser() {
    return Column(
      children: [
        // Navigation bar - Responsive
        _buildFileBrowserNavigation(),

        SizedBox(height: context.isMobile ? 6 : 8),

        // File list - Responsive
        Expanded(
          child: _buildFileList(),
        ),
      ],
    );
  }

  Widget _buildFileBrowserNavigation() {
    return Card(
      child: Padding(
        padding: context.responsivePadding,
        child: Row(
          children: [
            IconButton(
              icon: Icon(
                Icons.arrow_back,
                size: context.isMobile ? 18 : 24,
              ),
              onPressed: () {
                setState(() {
                  _isBrowsingFiles = false;
                  _selectedDevice = null;
                  _remoteFiles.clear();
                });
              },
            ),
            SizedBox(width: context.isMobile ? 6 : 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _selectedDevice?.name ?? '',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: (context.isMobile ? 12 : 14) *
                          context.fontSizeMultiplier,
                    ),
                  ),
                  Text(
                    _currentRemotePath,
                    style: TextStyle(
                        fontSize: (context.isMobile ? 10 : 12) *
                            context.fontSizeMultiplier,
                        color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(
                Icons.refresh,
                size: context.isMobile ? 18 : 24,
              ),
              onPressed: () => _loadRemoteFiles(_currentRemotePath),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileList() {
    if (_remoteFiles.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.folder_open,
              size: context.isMobile ? 48 : 64,
              color: Colors.grey[400],
            ),
            SizedBox(height: context.isMobile ? 12 : 16),
            Text(
              'No files found',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize:
                    (context.isMobile ? 12 : 14) * context.fontSizeMultiplier,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _remoteFiles.length,
      itemBuilder: (context, index) {
        final file = _remoteFiles[index];
        return Card(
          margin: EdgeInsets.only(bottom: context.isMobile ? 3 : 4),
          child: ListTile(
            dense: context.isMobile,
            contentPadding: EdgeInsets.symmetric(
              horizontal: context.isMobile ? 8 : 12,
              vertical: context.isMobile ? 2 : 4,
            ),
            leading: Icon(
              file.isDirectory ? Icons.folder : _getFileIcon(file.type),
              color: file.isDirectory
                  ? const Color(0xFF4E6AF3)
                  : _getFileIconColor(file.type),
              size: context.isMobile ? 16 : 20,
            ),
            title: Text(
              file.name,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize:
                    (context.isMobile ? 11 : 13) * context.fontSizeMultiplier,
              ),
            ),
            subtitle: file.isDirectory
                ? Text(
                    'Directory',
                    style: TextStyle(
                      fontSize: (context.isMobile ? 9 : 11) *
                          context.fontSizeMultiplier,
                    ),
                  )
                : Text(
                    _formatFileSize(file.size),
                    style: TextStyle(
                      fontSize: (context.isMobile ? 9 : 11) *
                          context.fontSizeMultiplier,
                    ),
                  ),
            trailing: file.isDirectory
                ? Icon(
                    Icons.chevron_right,
                    size: context.isMobile ? 16 : 20,
                  )
                : IconButton(
                    icon: Icon(
                      Icons.download,
                      size: context.isMobile ? 16 : 20,
                    ),
                    onPressed: () => _downloadFile(file),
                  ),
            onTap: file.isDirectory ? () => _loadRemoteFiles(file.path) : null,
          ),
        );
      },
    );
  }

  IconData _getFileIcon(String type) {
    if (type.startsWith('image/')) return Icons.image;
    if (type.startsWith('video/')) return Icons.video_file;
    if (type.startsWith('audio/')) return Icons.audio_file;
    if (type.contains('pdf')) return Icons.picture_as_pdf;
    if (type.contains('document') || type.contains('word'))
      return Icons.description;
    if (type.contains('spreadsheet') || type.contains('excel'))
      return Icons.table_chart;
    if (type.contains('presentation')) return Icons.slideshow;
    if (type.contains('zip') || type.contains('compressed'))
      return Icons.folder_zip;
    return Icons.insert_drive_file;
  }

  Color _getFileIconColor(String type) {
    if (type.startsWith('image/')) return Colors.blue;
    if (type.startsWith('video/')) return Colors.red;
    if (type.startsWith('audio/')) return Colors.purple;
    if (type.contains('pdf')) return Colors.red;
    if (type.contains('document') || type.contains('word')) return Colors.blue;
    if (type.contains('spreadsheet') || type.contains('excel'))
      return const Color(0xFF2AB673);
    if (type.contains('presentation')) return Colors.orange;
    if (type.contains('zip') || type.contains('compressed'))
      return Colors.amber;
    return Colors.grey;
  }

  String _getTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) return 'Just now';
    if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
    if (difference.inHours < 24) return '${difference.inHours}h ago';
    return '${difference.inDays}d ago';
  }
}

// Data models
class SyncDevice {
  final String name;
  final String ip;
  final int port;
  final String accessCode;
  final List<String> capabilities;
  final DateTime lastSeen;

  SyncDevice({
    required this.name,
    required this.ip,
    required this.port,
    required this.accessCode,
    required this.capabilities,
    required this.lastSeen,
  });
}

class SyncSession {
  final String deviceName;
  final String ip;
  final DateTime startTime;

  SyncSession({
    required this.deviceName,
    required this.ip,
    required this.startTime,
  });
}

class RemoteFileInfo {
  final String name;
  final String path;
  final bool isDirectory;
  final int size;
  final DateTime modified;
  final String type;

  RemoteFileInfo({
    required this.name,
    required this.path,
    required this.isDirectory,
    required this.size,
    required this.modified,
    required this.type,
  });

  factory RemoteFileInfo.fromJson(Map<String, dynamic> json) {
    return RemoteFileInfo(
      name: json['name'],
      path: json['path'],
      isDirectory: json['isDirectory'],
      size: json['size'],
      modified: DateTime.parse(json['modified']),
      type: json['type'],
    );
  }
}

class DownloadTask {
  final RemoteFileInfo file;
  final String savePath;
  double progress;
  String status;

  DownloadTask({
    required this.file,
    required this.savePath,
    required this.progress,
    required this.status,
  });
}
