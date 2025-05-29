import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:animate_do/animate_do.dart';
import 'package:lottie/lottie.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:mime/mime.dart';

class SyncScreen extends StatefulWidget {
  @override
  _SyncScreenState createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> with TickerProviderStateMixin {
  // Storage Server
  HttpServer? _storageServer;
  RawDatagramSocket? _syncDiscoverySocket;
  String? _accessCode;
  bool _isStorageSharing = false;
  List<String> _sharedPaths = [];
  List<SyncSession> _activeSessions = [];
  
  // Storage Browser
  List<SyncDevice> _availableDevices = [];
  bool _isDiscovering = false;
  Timer? _discoveryTimer;
  
  // UI State
  late TabController _tabController;
  String _selectedDirectory = '';
  SyncDevice? _selectedDevice;
  List<RemoteFileInfo> _remoteFiles = [];
  bool _isBrowsingFiles = false;
  String _currentRemotePath = '/';
  List<DownloadTask> _downloadQueue = [];
  
  // Current date/time and user
  final String currentDateTime = "2025-05-29 10:45:07";
  final String userLogin = "navin280123";
  
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
      // Initialize sync discovery socket
      _syncDiscoverySocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        8083,
        reuseAddress: true,
      );
      _syncDiscoverySocket!.broadcastEnabled = true;
      
      _syncDiscoverySocket!.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = _syncDiscoverySocket!.receive();
          if (datagram != null) {
            _handleSyncDiscovery(datagram);
          }
        }
      });
    } catch (e) {
      print('Error initializing sync: $e');
    }
  }

  void _handleSyncDiscovery(Datagram datagram) {
    try {
      final message = utf8.decode(datagram.data);
      final data = json.decode(message) as Map<String, dynamic>;
      
      if (data['type'] == 'SPEEDSHARE_SYNC_ANNOUNCE') {
        final device = SyncDevice(
          name: data['deviceName'],
          ip: datagram.address.address,
          port: data['storagePort'],
          accessCode: data['accessCode'],
          capabilities: List<String>.from(data['capabilities']),
          lastSeen: DateTime.now(),
        );
        
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
    } catch (e) {
      print('Error loading sync settings: $e');
    }
  }

  Future<void> _saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('sync_shared_paths', _sharedPaths);
    } catch (e) {
      print('Error saving sync settings: $e');
    }
  }

  void _startDiscovery() {
    _discoveryTimer = Timer.periodic(Duration(seconds: 10), (timer) {
      _sendSyncAnnouncement();
      _cleanupStaleDevices();
    });
    _sendSyncAnnouncement();
  }

  void _sendSyncAnnouncement() {
    if (_syncDiscoverySocket == null || !_isStorageSharing) return;
    
    try {
      final announcement = json.encode({
        'type': 'SPEEDSHARE_SYNC_ANNOUNCE',
        'deviceName': Platform.localHostname,
        'storagePort': 8082,
        'accessCode': _accessCode,
        'capabilities': ['storage_share', 'storage_browse'],
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
      
      final data = utf8.encode(announcement);
      
      // Broadcast to network
      _syncDiscoverySocket!.send(data, InternetAddress('255.255.255.255'), 8083);
    } catch (e) {
      print('Error sending sync announcement: $e');
    }
  }

  void _cleanupStaleDevices() {
    final now = DateTime.now();
    setState(() {
      _availableDevices.removeWhere((device) =>
          now.difference(device.lastSeen).inMinutes > 5);
    });
  }

  Future<void> _startStorageSharing() async {
    if (_sharedPaths.isEmpty) {
      _showErrorSnackBar('Please select at least one directory to share');
      return;
    }

    try {
      _accessCode = _generateAccessCode();
      
      _storageServer = await HttpServer.bind(InternetAddress.anyIPv4, 8082);
      _storageServer!.listen(_handleStorageRequest);
      
      setState(() {
        _isStorageSharing = true;
      });
      
      _sendSyncAnnouncement();
      
      _showSuccessSnackBar('Storage sharing started with code: $_accessCode');
    } catch (e) {
      _showErrorSnackBar('Failed to start storage sharing: $e');
    }
  }

  Future<void> _stopStorageSharing() async {
    try {
      await _storageServer?.close();
      _storageServer = null;
      _accessCode = null;
      
      setState(() {
        _isStorageSharing = false;
        _activeSessions.clear();
      });
      
      _showSuccessSnackBar('Storage sharing stopped');
    } catch (e) {
      _showErrorSnackBar('Failed to stop storage sharing: $e');
    }
  }

  void _handleStorageRequest(HttpRequest request) async {
    try {
      final uri = request.uri;
      final accessCode = uri.queryParameters['code'];
      
      if (accessCode != _accessCode) {
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
        request.response.statusCode = 404;
        await request.response.close();
      }
    } catch (e) {
      print('Error handling storage request: $e');
      request.response.statusCode = 500;
      await request.response.close();
    }
  }

  Future<void> _handleFileListRequest(HttpRequest request) async {
    final path = request.uri.queryParameters['path'] ?? '/';
    final files = <Map<String, dynamic>>[];
    
    try {
      for (final sharedPath in _sharedPaths) {
        final targetPath = path == '/' ? sharedPath : p.join(sharedPath, path);
        final directory = Directory(targetPath);
        
        if (await directory.exists()) {
          await for (final entity in directory.list()) {
            final stat = await entity.stat();
            files.add({
              'name': p.basename(entity.path),
              'path': entity.path,
              'isDirectory': entity is Directory,
              'size': entity is File ? stat.size : 0,
              'modified': stat.modified.toIso8601String(),
              'type': entity is File ? lookupMimeType(entity.path) ?? 'application/octet-stream' : 'directory',
            });
          }
        }
      }
      
      request.response.headers.contentType = ContentType.json;
      request.response.write(json.encode(files));
    } catch (e) {
      request.response.statusCode = 500;
      request.response.write('Error listing files: $e');
    }
    
    await request.response.close();
  }

  Future<void> _handleFileDownloadRequest(HttpRequest request) async {
    final filePath = request.uri.queryParameters['file'];
    
    if (filePath == null || !_isPathAllowed(filePath)) {
      request.response.statusCode = 403;
      request.response.write('Access denied');
      await request.response.close();
      return;
    }
    
    try {
      final file = File(filePath);
      if (await file.exists()) {
        final fileSize = await file.length();
        request.response.headers.contentType = ContentType.binary;
        request.response.headers.add('Content-Length', fileSize.toString());
        request.response.headers.add('Content-Disposition', 'attachment; filename="${p.basename(filePath)}"');
        
        await file.openRead().pipe(request.response);
      } else {
        request.response.statusCode = 404;
        request.response.write('File not found');
        await request.response.close();
      }
    } catch (e) {
      request.response.statusCode = 500;
      request.response.write('Error downloading file: $e');
      await request.response.close();
    }
  }

  bool _isPathAllowed(String filePath) {
    return _sharedPaths.any((sharedPath) => filePath.startsWith(sharedPath));
  }

  String _generateAccessCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = DateTime.now().millisecondsSinceEpoch;
    return List.generate(6, (index) => chars[(random + index) % chars.length]).join();
  }

  Future<void> _addSharedDirectory() async {
    final result = await FilePicker.platform.getDirectoryPath();
    if (result != null) {
      setState(() {
        if (!_sharedPaths.contains(result)) {
          _sharedPaths.add(result);
        }
      });
      await _saveSettings();
    }
  }

  void _removeSharedDirectory(String path) {
    setState(() {
      _sharedPaths.remove(path);
    });
    _saveSettings();
  }

  Future<void> _browseDevice(SyncDevice device) async {
    setState(() {
      _selectedDevice = device;
      _isBrowsingFiles = true;
      _currentRemotePath = '/';
    });
    
    await _loadRemoteFiles('/');
  }

  Future<void> _loadRemoteFiles(String path) async {
    if (_selectedDevice == null) return;
    
    try {
      final response = await http.get(
        Uri.parse('http://${_selectedDevice!.ip}:${_selectedDevice!.port}/api/files?path=$path&code=${_selectedDevice!.accessCode}'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        setState(() {
          _remoteFiles = data.map((item) => RemoteFileInfo.fromJson(item)).toList();
          _currentRemotePath = path;
        });
      } else {
        _showErrorSnackBar('Failed to load files: ${response.statusCode}');
      }
    } catch (e) {
      _showErrorSnackBar('Error loading files: $e');
    }
  }

  Future<void> _downloadFile(RemoteFileInfo file) async {
    if (_selectedDevice == null) return;
    
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
      
      final response = await http.get(
        Uri.parse('http://${_selectedDevice!.ip}:${_selectedDevice!.port}/api/download?file=${file.path}&code=${_selectedDevice!.accessCode}'),
      );
      
      if (response.statusCode == 200) {
        await File(savePath).writeAsBytes(response.bodyBytes);
        
        setState(() {
          downloadTask.progress = 1.0;
          downloadTask.status = 'Completed';
        });
        
        _showSuccessSnackBar('Downloaded: ${file.name}');
      } else {
        setState(() {
          downloadTask.status = 'Failed';
        });
        _showErrorSnackBar('Download failed: ${response.statusCode}');
      }
    } catch (e) {
      _showErrorSnackBar('Error downloading file: $e');
    }
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.white),
            SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Color(0xFF2AB673),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: EdgeInsets.all(20),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.error_rounded, color: Colors.white),
            SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: EdgeInsets.all(20),
      ),
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  @override
  void dispose() {
    _tabController.dispose();
    _discoveryTimer?.cancel();
    _storageServer?.close();
    _syncDiscoverySocket?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF4E6AF3).withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.sync_rounded,
                  size: 24,
                  color: Color(0xFF4E6AF3),
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Sync',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF4E6AF3),
                    ),
                  ),
                  Text(
                    'Share and access device storage',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).brightness == Brightness.dark 
                          ? Colors.grey[400] 
                          : Colors.grey[600],
                    ),
                  ),
                ],
              ),
              const Spacer(),
              // Status indicator
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _isStorageSharing ? const Color(0xFF2AB673) : Colors.grey,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _isStorageSharing ? 'Sharing Active' : 'Inactive',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 20),
          
          // Tab bar
          TabBar(
            controller: _tabController,
            labelColor: const Color(0xFF4E6AF3),
            unselectedLabelColor: Colors.grey,
            indicatorColor: const Color(0xFF4E6AF3),
            tabs: const [
              Tab(text: 'Share Storage'),
              Tab(text: 'Access Storage'),
            ],
          ),
          
          const SizedBox(height: 16),
          
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

  Widget _buildShareStorageTab() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Storage sharing status
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _isStorageSharing ? Icons.share_rounded : Icons.share_outlined,
                        color: _isStorageSharing ? const Color(0xFF2AB673) : Colors.grey,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Storage Sharing',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: _isStorageSharing ? const Color(0xFF2AB673) : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_isStorageSharing) ...[
                    Row(
                      children: [
                        const Text('Access Code: '),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF4E6AF3).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _accessCode ?? '',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF4E6AF3),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.copy, size: 16),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: _accessCode ?? ''));
                            _showSuccessSnackBar('Access code copied to clipboard');
                          },
                          tooltip: 'Copy access code',
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Active sessions: ${_activeSessions.length}',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isStorageSharing ? _stopStorageSharing : (_sharedPaths.isNotEmpty ? _startStorageSharing : null),
                          icon: Icon(_isStorageSharing ? Icons.stop : Icons.play_arrow),
                          label: Text(_isStorageSharing ? 'Stop Sharing' : 'Start Sharing'),
                          style: ElevatedButton.styleFrom(
                            foregroundColor: Colors.white,
                            backgroundColor: _isStorageSharing ? Colors.red : const Color(0xFF2AB673),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Shared directories
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Shared Directories',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _addSharedDirectory,
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Add Directory'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_sharedPaths.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          Icon(
                            Icons.folder_open,
                            size: 48,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'No directories shared',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Add directories to share with other devices',
                            style: TextStyle(color: Colors.grey[500], fontSize: 12),
                          ),
                        ],
                      ),
                    )
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _sharedPaths.length,
                      itemBuilder: (context, index) {
                        final path = _sharedPaths[index];
                        return ListTile(
                          leading: const Icon(Icons.folder, color: Color(0xFF4E6AF3)),
                          title: Text(
                            p.basename(path),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            path,
                            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.remove_circle, color: Colors.red),
                            onPressed: () => _removeSharedDirectory(path),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
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
          // Device discovery
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.devices, color: Color(0xFF4E6AF3)),
                      const SizedBox(width: 8),
                      const Text(
                        'Available Devices',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      if (_isDiscovering)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_availableDevices.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          Lottie.asset(
                            'assets/searchss.json',
                            height: 80,
                            errorBuilder: (context, error, stackTrace) {
                              return Icon(
                                Icons.search_off,
                                size: 48,
                                color: Colors.grey[400],
                              );
                            },
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'No devices found',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Make sure other devices are sharing storage',
                            style: TextStyle(color: Colors.grey[500], fontSize: 12),
                          ),
                        ],
                      ),
                    )
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _availableDevices.length,
                      itemBuilder: (context, index) {
                        final device = _availableDevices[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF2AB673).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                device.name.toLowerCase().contains('mobile') || device.name.toLowerCase().contains('phone')
                                    ? Icons.phone_android
                                    : Icons.computer,
                                color: const Color(0xFF2AB673),
                              ),
                            ),
                            title: Text(
                              device.name,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('IP: ${device.ip}'),
                                Text(
                                  'Last seen: ${_getTimeAgo(device.lastSeen)}',
                                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                                ),
                              ],
                            ),
                            trailing: ElevatedButton(
                              onPressed: () => _browseDevice(device),
                              child: const Text('Browse'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF4E6AF3),
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
          
          // Download queue
          if (_downloadQueue.isNotEmpty) ...[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Download Queue',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _downloadQueue.length,
                      itemBuilder: (context, index) {
                        final task = _downloadQueue[index];
                        return ListTile(
                          leading: Icon(
                            _getFileIcon(task.file.type),
                            color: _getFileIconColor(task.file.type),
                          ),
                          title: Text(task.file.name),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(task.status),
                              if (task.progress > 0 && task.progress < 1)
                                LinearProgressIndicator(value: task.progress),
                            ],
                          ),
                          trailing: task.status == 'Completed'
                              ? const Icon(Icons.check_circle, color: Color(0xFF2AB673))
                              : task.status == 'Failed'
                                  ? const Icon(Icons.error, color: Colors.red)
                                  : null,
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFileBrowser() {
    return Column(
      children: [
        // Navigation bar
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () {
                    setState(() {
                      _isBrowsingFiles = false;
                      _selectedDevice = null;
                      _remoteFiles.clear();
                    });
                  },
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _selectedDevice?.name ?? '',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        _currentRemotePath,
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () => _loadRemoteFiles(_currentRemotePath),
                ),
              ],
            ),
          ),
        ),
        
        const SizedBox(height: 8),
        
        // File list
        Expanded(
          child: _remoteFiles.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.folder_open,
                        size: 64,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No files found',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _remoteFiles.length,
                  itemBuilder: (context, index) {
                    final file = _remoteFiles[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 4),
                      child: ListTile(
                        leading: Icon(
                          file.isDirectory ? Icons.folder : _getFileIcon(file.type),
                          color: file.isDirectory 
                              ? const Color(0xFF4E6AF3) 
                              : _getFileIconColor(file.type),
                        ),
                        title: Text(
                          file.name,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: file.isDirectory
                            ? const Text('Directory')
                            : Text(_formatFileSize(file.size)),
                        trailing: file.isDirectory
                            ? const Icon(Icons.chevron_right)
                            : IconButton(
                                icon: const Icon(Icons.download),
                                onPressed: () => _downloadFile(file),
                              ),
                        onTap: file.isDirectory
                            ? () => _loadRemoteFiles(file.path)
                            : null,
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  IconData _getFileIcon(String type) {
    if (type.startsWith('image/')) return Icons.image;
    if (type.startsWith('video/')) return Icons.video_file;
    if (type.startsWith('audio/')) return Icons.audio_file;
    if (type.contains('pdf')) return Icons.picture_as_pdf;
    if (type.contains('document') || type.contains('word')) return Icons.description;
    if (type.contains('spreadsheet') || type.contains('excel')) return Icons.table_chart;
    if (type.contains('presentation')) return Icons.slideshow;
    if (type.contains('zip') || type.contains('compressed')) return Icons.folder_zip;
    return Icons.insert_drive_file;
  }

  Color _getFileIconColor(String type) {
    if (type.startsWith('image/')) return Colors.blue;
    if (type.startsWith('video/')) return Colors.red;
    if (type.startsWith('audio/')) return Colors.purple;
    if (type.contains('pdf')) return Colors.red;
    if (type.contains('document') || type.contains('word')) return Colors.blue;
    if (type.contains('spreadsheet') || type.contains('excel')) return const Color(0xFF2AB673);
    if (type.contains('presentation')) return Colors.orange;
    if (type.contains('zip') || type.contains('compressed')) return Colors.amber;
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