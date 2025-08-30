import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mime/mime.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:lottie/lottie.dart';
import 'package:speedshare/main.dart';

class FileSenderScreen extends StatefulWidget {
  @override
  _FileSenderScreenState createState() => _FileSenderScreenState();
}

class _FileSenderScreenState extends State<FileSenderScreen> with SingleTickerProviderStateMixin {
  // Constants
  static const int MAX_FILE_SIZE = 5 * 1024 * 1024 * 1024; // 5GB
  static const int CHUNK_SIZE = 32 * 1024; // 32KB chunks
  static const int CONNECTION_TIMEOUT = 10; // seconds
  static const int DISCOVERY_TIMEOUT = 5; // seconds
  
  late AnimationController _controller;
  bool _isSending = false;
  double _progress = 0.0;
  int _totalFileSize = 0;
  int _totalBytesSent = 0;
  int _currentFileIndex = 0;
  bool _isHovering = false;
  bool _filesSelected = false;
  List<FileToSend> _selectedFiles = [];
  bool _transferComplete = false;

  bool isScanning = false;
  bool isConnecting = false;
  Socket? socket;
  Timer? _scanTimer;
  String? _receiverName;

  List<ReceiverDevice> availableReceivers = [];
  int _selectedReceiverIndex = -1;
  bool _isDiscovering = false;
  Timer? _discoveryTimer;
  RawDatagramSocket? _discoverySocket;

  int _currentStep = 1;
  String _searchQuery = '';
  List<ReceiverDevice> _filteredReceivers = [];

  final String _userLogin = Platform.localHostname;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _controller.forward();
    startScanning();

    _discoveryTimer = Timer.periodic(Duration(seconds: 30), (timer) {
      if (mounted) startScanning();
    });

    _filteredReceivers = availableReceivers;
  }

  void startScanning() {
    if (!mounted) return;
    setState(() {
      isScanning = true;
    });
    discoverWithUDP();
    _scanTimer = Timer(Duration(seconds: DISCOVERY_TIMEOUT), () {
      if (mounted) {
        setState(() {
          isScanning = false;
        });
      }
    });
  }

  void discoverWithUDP() async {
    try {
      setState(() {
        _isDiscovering = true;
        availableReceivers.clear();
        _filteredReceivers = [];
      });

      _discoverySocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);

      _discoverySocket!.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = _discoverySocket!.receive();
          if (datagram != null) {
            final message = utf8.decode(datagram.data);
            // Fixed protocol - expect exactly "SPEEDSHARE_RESPONSE:deviceName:"
            if (message.startsWith('SPEEDSHARE_RESPONSE:')) {
              final parts = message.split(':');
              if (parts.length >= 2) {
                final deviceName = parts[1];
                final ipAddress = datagram.address.address;
                if (mounted) {
                  setState(() {
                    if (!availableReceivers.any((device) => device.ip == ipAddress)) {
                      final newDevice = ReceiverDevice(
                        name: deviceName,
                        ip: ipAddress,
                      );
                      availableReceivers.add(newDevice);
                      _filteredReceivers = _filterReceivers();
                    }
                  });
                }
              }
            }
          }
        }
      });

      final interfaces = await NetworkInterface.list();
      for (var interface in interfaces) {
        if (interface.name.contains('lo')) continue;
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4) {
            final parts = addr.address.split('.');
            if (parts.length == 4) {
              final subnet = parts.sublist(0, 3).join('.');
              final message = utf8.encode('SPEEDSHARE_DISCOVERY');
              try {
                // Send to various broadcast addresses
                final addresses = [
                  '$subnet.255',
                  '$subnet.1',
                  addr.address,
                ];
                
                for (String address in addresses) {
                  try {
                    _discoverySocket!.send(message, InternetAddress(address), 8081);
                  } catch (e) {
                    print('Failed to send to $address: $e');
                  }
                }
                
                // Also send to common IP ranges
                for (int i = 2; i < 20; i++) {
                  try {
                    _discoverySocket!.send(message, InternetAddress('$subnet.$i'), 8081);
                  } catch (e) {
                    // Silent fail for individual IPs
                  }
                }
              } catch (e) {
                print('Failed to send discovery packet: $e');
              }
            }
          }
        }
      }
      
      Timer(Duration(seconds: 3), () {
        if (mounted) {
          if (availableReceivers.isEmpty) {
            checkDirectTCPConnections();
          } else {
            setState(() {
              _isDiscovering = false;
              isScanning = false;
              _filteredReceivers = _filterReceivers();
            });
          }
        }
      });
    } catch (e) {
      print('UDP discovery error: $e');
      if (mounted) checkDirectTCPConnections();
    }
  }

  void checkDirectTCPConnections() async {
    try {
      final interfaces = await NetworkInterface.list();
      for (var interface in interfaces) {
        if (interface.name.contains('lo')) continue;
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4) {
            final parts = addr.address.split('.');
            if (parts.length == 4) {
              final prefix = parts.sublist(0, 3).join('.');
              // Check more common IP ranges
              for (int i = 1; i <= 50; i++) {
                await checkReceiver('$prefix.$i');
              }
              // Check common router/device IPs
              final commonIPs = ['$prefix.100', '$prefix.101', '$prefix.102', '$prefix.254'];
              for (String ip in commonIPs) {
                await checkReceiver(ip);
              }
            }
          }
        }
      }
    } catch (e) {
      print('TCP discovery error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isDiscovering = false;
          isScanning = false;
          _filteredReceivers = _filterReceivers();
        });
      }
    }
  }

  Future<void> checkReceiver(String ip) async {
    try {
      final socket = await Socket.connect(
        ip, 
        8080, 
        timeout: Duration(milliseconds: 500)
      ).catchError((e) => null);

      if (socket == null) return;

      final completer = Completer<String?>();

      Timer(Duration(seconds: 1), () {
        if (!completer.isCompleted) {
          completer.complete(null);
        }
      });

      socket.listen((data) {
        final message = String.fromCharCodes(data);
        if (message.startsWith('DEVICE_NAME:')) {
          final deviceName = message.replaceFirst('DEVICE_NAME:', '');
          if (!completer.isCompleted) {
            completer.complete(deviceName);
          }
        }
      });

      final deviceName = await completer.future;
      socket.destroy();

      if (deviceName != null && deviceName.isNotEmpty && mounted) {
        setState(() {
          if (!availableReceivers.any((device) => device.ip == ip)) {
            availableReceivers.add(ReceiverDevice(
              name: deviceName,
              ip: ip,
            ));
            _filteredReceivers = _filterReceivers();
          }
        });
      }
    } catch (e) {
      // Silent fail for individual IP checks
    }
  }

  void connectToReceiver(String ip, [String? name]) async {
    if (_selectedFiles.isEmpty) {
      _showSnackBar(
        'Please select at least one file',
        Icons.warning_amber_rounded,
        Colors.orange,
      );
      return;
    }
    
    setState(() {
      isConnecting = true;
      _currentStep = 3;
    });
    
    try {
      socket = await Socket.connect(
        ip, 
        8080, 
        timeout: Duration(seconds: CONNECTION_TIMEOUT)
      );

      String deviceName = name ?? '';
      if (deviceName.isEmpty) {
        final completer = Completer<String>();
        socket!.listen((data) {
          String message = String.fromCharCodes(data);
          if (message.startsWith('DEVICE_NAME:')) {
            deviceName = message.replaceFirst('DEVICE_NAME:', '');
            if (!completer.isCompleted) {
              completer.complete(deviceName);
            }
          }
        }, onDone: () {
          if (!completer.isCompleted) {
            completer.complete('Unknown Device');
          }
        }, onError: (e) {
          if (!completer.isCompleted) {
            completer.completeError(e);
          }
        });
        
        try {
          deviceName = await completer.future.timeout(Duration(seconds: 2));
        } catch (e) {
          deviceName = 'Unknown Device';
        }
      }

      if (mounted) {
        setState(() {
          isConnecting = false;
          _receiverName = deviceName;
        });
      }

      _showSnackBar(
        'Connected to $deviceName',
        Icons.check_circle_rounded,
        Color(0xFF2AB673),
      );

      // Listen for receiver responses
      socket!.listen((data) {
        final message = utf8.decode(data);
        if (message == 'READY_FOR_FILE_DATA') {
          _sendCurrentFileData();
        } else if (message == 'TRANSFER_COMPLETE') {
          _handleFileTransferComplete();
        }
      }, onError: (error) {
        if (mounted) {
          setState(() {
            _isSending = false;
          });
        }
        _showSnackBar(
          'Connection error: ${error.toString().substring(0, _min(error.toString().length, 50))}',
          Icons.error_outline_rounded,
          Colors.red,
        );
      }, onDone: () {
        if (_isSending && _progress < 1.0 && mounted) {
          setState(() {
            _isSending = false;
          });
          _showSnackBar(
            'Connection closed unexpectedly',
            Icons.error_outline_rounded,
            Colors.red,
          );
        }
      });

      // Start the file transfer handshake for the first file
      _startFileTransfer();
    } catch (e) {
      if (mounted) {
        setState(() {
          isConnecting = false;
          _currentStep = 2;
        });
      }
      _showSnackBar(
        'Failed to connect: ${e.toString().substring(0, _min(e.toString().length, 50))}',
        Icons.error_outline_rounded,
        Colors.red,
        action: SnackBarAction(
          label: 'Retry',
          textColor: Colors.white,
          onPressed: () => connectToReceiver(ip, name),
        ),
      );
    }
  }

  void _pickFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: true,
        dialogTitle: 'Select files to send',
      );
      
      if (result != null && result.files.isNotEmpty) {
        List<FileToSend> files = [];
        int totalSize = 0;
        
        for (var file in result.files) {
          if (file.path != null) {
            File fileData = File(file.path!);
            String fileName = file.path!.split(Platform.isWindows ? '\\' : '/').last;
            int fileSize = fileData.lengthSync();
            
            // Validate file size
            if (fileSize > MAX_FILE_SIZE) {
              _showSnackBar(
                'File $fileName is too large. Maximum size is ${_formatFileSize(MAX_FILE_SIZE)}',
                Icons.error_rounded,
                Colors.red,
              );
              continue;
            }
            
            String fileType = lookupMimeType(file.path!) ?? 'application/octet-stream';
            files.add(FileToSend(
              file: fileData,
              name: fileName,
              size: fileSize,
              type: fileType,
              progress: 0.0,
              bytesSent: 0,
              status: 'Pending',
            ));
            totalSize += fileSize;
          }
        }
        
        if (files.isNotEmpty) {
          _prepareFiles(files, totalSize);
          _controller.reset();
          _controller.forward();
          setState(() {
            _currentStep = 2;
          });
        }
      }
    } catch (e) {
      _showSnackBar(
        'Error selecting files: $e',
        Icons.error_rounded,
        Colors.red,
      );
    }
  }

  void _prepareFiles(List<FileToSend> files, int totalSize) {
    setState(() {
      _selectedFiles = files;
      _totalFileSize = totalSize;
      _totalBytesSent = 0;
      _filesSelected = true;
      _transferComplete = false;
      _currentFileIndex = 0;
    });
  }

  void _removeFile(int index) {
    setState(() {
      _totalFileSize -= _selectedFiles[index].size;
      _selectedFiles.removeAt(index);
      if (_selectedFiles.isEmpty) {
        _filesSelected = false;
        _totalFileSize = 0;
      }
    });
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024)
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  void _startFileTransfer() {
    if (_selectedFiles.isEmpty || _currentFileIndex >= _selectedFiles.length) {
      return;
    }
    setState(() {
      _isSending = true;
      _selectedFiles[_currentFileIndex].progress = 0.0;
      _selectedFiles[_currentFileIndex].bytesSent = 0;
      _selectedFiles[_currentFileIndex].status = 'Sending';
    });
    _sendCurrentFileMetadata();
  }

  void _sendCurrentFileMetadata() async {
    if (socket == null || _currentFileIndex >= _selectedFiles.length) return;
    final currentFile = _selectedFiles[_currentFileIndex];
    try {
      final metadata = {
        'fileName': currentFile.name,
        'fileSize': currentFile.size,
        'fileType': currentFile.type,
        'sender': _userLogin,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'totalFiles': _selectedFiles.length,
        'fileIndex': _currentFileIndex,
      };
      final metadataStr = json.encode(metadata);
      final metadataBytes = utf8.encode(metadataStr);

      final metadataSize = Uint8List(4);
      ByteData.view(metadataSize.buffer).setInt32(0, metadataBytes.length);
      socket!.add(metadataSize);
      socket!.add(metadataBytes);
      await socket!.flush();
    } catch (e) {
      if (mounted) {
        setState(() {
          _selectedFiles[_currentFileIndex].status = 'Failed';
          _isSending = false;
        });
      }
      _showSnackBar(
        'Error sending metadata: ${e.toString().substring(0, _min(e.toString().length, 50))}',
        Icons.error_outline_rounded,
        Colors.red,
        action: SnackBarAction(
          label: 'Retry',
          textColor: Colors.white,
          onPressed: _sendCurrentFileMetadata,
        ),
      );
    }
  }

  // FIXED: Streaming file transfer instead of loading entire file into memory
  void _sendCurrentFileData() async {
    if (socket == null || _currentFileIndex >= _selectedFiles.length) return;
    final currentFile = _selectedFiles[_currentFileIndex];
    
    try {
      final fileStream = currentFile.file.openRead();
      int bytesSent = 0;
      int lastProgressUpdate = 0;
      final int updateThreshold = (currentFile.size / 100).round();

      await for (final chunk in fileStream) {
        if (socket == null) {
          throw Exception("Connection lost");
        }
        
        socket!.add(chunk);
        bytesSent += chunk.length;
        _totalBytesSent += chunk.length;

        if (bytesSent - lastProgressUpdate > updateThreshold && mounted) {
          setState(() {
            _selectedFiles[_currentFileIndex].progress = bytesSent / currentFile.size;
            _selectedFiles[_currentFileIndex].bytesSent = bytesSent;
            _progress = _totalBytesSent / _totalFileSize;
          });
          lastProgressUpdate = bytesSent;
        }
        
        // Small delay to prevent UI blocking
        if (bytesSent % (CHUNK_SIZE * 10) == 0) {
          await Future.delayed(Duration(milliseconds: 1));
        }
      }

      if (mounted) {
        setState(() {
          _selectedFiles[_currentFileIndex].progress = 1.0;
          _selectedFiles[_currentFileIndex].bytesSent = currentFile.size;
          _progress = _totalBytesSent / _totalFileSize;
        });
      }

      // Wait for confirmation or timeout
      Timer(Duration(seconds: 15), () {
        if (_isSending && _selectedFiles[_currentFileIndex].progress >= 0.99 && mounted) {
          _handleFileTransferComplete();
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _selectedFiles[_currentFileIndex].status = 'Failed';
          _isSending = false;
        });
      }
      _showSnackBar(
        'Error sending file: ${e.toString().substring(0, _min(e.toString().length, 50))}',
        Icons.error_outline_rounded,
        Colors.red,
        action: SnackBarAction(
          label: 'Retry',
          textColor: Colors.white,
          onPressed: _sendCurrentFileData,
        ),
      );
    }
  }

  void _handleFileTransferComplete() {
    if (!mounted) return;
    setState(() {
      _selectedFiles[_currentFileIndex].status = 'Completed';
      _currentFileIndex++;
      if (_currentFileIndex >= _selectedFiles.length) {
        _isSending = false;
        _transferComplete = true;
        _progress = 1.0;
        _showSnackBar(
          'All files sent successfully!',
          Icons.check_circle_rounded,
          Color(0xFF2AB673),
          action: SnackBarAction(
            label: 'Send More',
            textColor: Colors.white,
            onPressed: () {
              setState(() {
                _currentStep = 1;
                _filesSelected = false;
                _selectedFiles = [];
                _transferComplete = false;
                _totalFileSize = 0;
                _totalBytesSent = 0;
              });
            },
          ),
        );
      } else {
        // Continue with next file
        _sendCurrentFileMetadata();
      }
    });
  }

  List<ReceiverDevice> _filterReceivers() {
    if (_searchQuery.isEmpty) {
      return availableReceivers;
    }
    return availableReceivers.where((device) =>
      device.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
      device.ip.contains(_searchQuery)
    ).toList();
  }

  IconData _getFileIconData(String fileType) {
    if (fileType.startsWith('image/')) {
      return Icons.image_rounded;
    } else if (fileType.startsWith('video/')) {
      return Icons.video_file_rounded;
    } else if (fileType.startsWith('audio/')) {
      return Icons.audio_file_rounded;
    } else if (fileType.contains('pdf')) {
      return Icons.picture_as_pdf_rounded;
    } else if (fileType.contains('word') || fileType.contains('document')) {
      return Icons.description_rounded;
    } else if (fileType.contains('excel') || fileType.contains('sheet')) {
      return Icons.table_chart_rounded;
    } else if (fileType.contains('presentation') || fileType.contains('powerpoint')) {
      return Icons.slideshow_rounded;
    } else if (fileType.contains('zip') || fileType.contains('compressed')) {
      return Icons.folder_zip_rounded;
    } else {
      return Icons.insert_drive_file_rounded;
    }
  }

  Color _getFileIconColor(String fileType) {
    if (fileType.startsWith('image/')) {
      return Color(0xFF3498db);
    } else if (fileType.startsWith('video/')) {
      return Color(0xFFe74c3c);
    } else if (fileType.startsWith('audio/')) {
      return Color(0xFF9b59b6);
    } else if (fileType.contains('pdf')) {
      return Color(0xFFe74c3c);
    } else if (fileType.contains('word') || fileType.contains('document')) {
      return Color(0xFF3498db);
    } else if (fileType.contains('excel') || fileType.contains('sheet')) {
      return Color(0xFF2ecc71);
    } else if (fileType.contains('presentation') || fileType.contains('powerpoint')) {
      return Color(0xFFe67e22);
    } else if (fileType.contains('zip') || fileType.contains('compressed')) {
      return Color(0xFFf39c12);
    } else {
      return Color(0xFF95a5a6);
    }
  }

  int _min(int a, int b) {
    return a < b ? a : b;
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
  void dispose() {
    _controller.dispose();
    _scanTimer?.cancel();
    _discoveryTimer?.cancel();
    _discoverySocket?.close();
    socket?.close();
    super.dispose();
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
            
            // Step indicator - Responsive
            _buildStepIndicator(),
            
            SizedBox(height: context.isMobile ? 12 : 16),
            
            // Main content area
            Expanded(
              child: _buildCurrentStepContent(),
            ),
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
            Icons.send_rounded,
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
                'Send Files',
                style: TextStyle(
                  fontSize: context.isMobile ? 18 : 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF4E6AF3),
                ),
              ),
              Text(
                'Share between devices',
                style: TextStyle(
                  fontSize: context.isMobile ? 12 : 13,
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

  Widget _buildStepIndicator() {
    if (context.isMobile) {
      return _buildMobileStepIndicator();
    } else {
      return _buildDesktopStepIndicator();
    }
  }

  Widget _buildMobileStepIndicator() {
    return Container(
      height: 60,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildCompactStepItem(1, 'Files', _currentStep >= 1),
          _buildStepConnector(_currentStep >= 2, isCompact: true),
          _buildCompactStepItem(2, 'Receiver', _currentStep >= 2),
          _buildStepConnector(_currentStep >= 3, isCompact: true),
          _buildCompactStepItem(3, 'Transfer', _currentStep >= 3),
        ],
      ),
    );
  }

  Widget _buildDesktopStepIndicator() {
    return SizedBox(
      height: 60,
      child: Row(
        children: [
          _buildStepItem(1, 'Select Files', _currentStep >= 1),
          _buildStepConnector(_currentStep >= 2),
          _buildStepItem(2, 'Select Receiver', _currentStep >= 2),
          _buildStepConnector(_currentStep >= 3),
          _buildStepItem(3, 'Transfer', _currentStep >= 3),
        ],
      ),
    );
  }

  Widget _buildCompactStepItem(int step, String label, bool isActive) {
    return Expanded(
      child: Column(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: isActive ? const Color(0xFF4E6AF3) : Colors.grey[300],
              shape: BoxShape.circle,
              boxShadow: isActive ? [
                BoxShadow(
                  color: const Color(0xFF4E6AF3).withOpacity(0.3),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ] : null,
            ),
            child: Center(
              child: isActive && step < _currentStep
                ? const Icon(Icons.check, color: Colors.white, size: 14)
                : Text(
                    '$step',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              color: isActive ? const Color(0xFF4E6AF3) : Colors.grey[500],
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              fontSize: 11,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
  
  Widget _buildStepItem(int step, String label, bool isActive) {
    return Expanded(
      child: Column(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: isActive ? const Color(0xFF4E6AF3) : Colors.grey[300],
              shape: BoxShape.circle,
              boxShadow: isActive ? [
                BoxShadow(
                  color: const Color(0xFF4E6AF3).withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ] : null,
            ),
            child: Center(
              child: isActive && step < _currentStep
                ? const Icon(Icons.check, color: Colors.white, size: 16)
                : Text(
                    '$step',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              color: isActive ? const Color(0xFF4E6AF3) : Colors.grey[500],
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              fontSize: 12,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildStepConnector(bool isActive, {bool isCompact = false}) {
    return Container(
      width: isCompact ? 30 : 40,
      height: 2,
      color: isActive ? const Color(0xFF4E6AF3) : Colors.grey[300],
    );
  }

  Widget _buildCurrentStepContent() {
    switch (_currentStep) {
      case 1:
        return _buildSelectFileStep();
      case 2:
        return _buildSelectReceiverStep();
      case 3:
        return _buildTransferStep();
      default:
        return _buildSelectFileStep();
    }
  }
  
  Widget _buildSelectFileStep() {
    return Card(
      child: _filesSelected 
          ? _buildSelectedFilesInfo()
          : _buildFileDropArea(),
    );
  }
  
  Widget _buildFileDropArea() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final animationSize = context.isMobile 
            ? constraints.maxWidth * 0.3 
            : constraints.maxWidth * 0.25;
        final iconSize = context.isMobile ? 24.0 : 40.0;
        final headingSize = (context.isMobile ? 16.0 : 20.0) * context.fontSizeMultiplier;
        final contentPadding = context.responsivePadding;
        
        return DropTarget(
          onDragDone: (detail) async {
            if (detail.files.isNotEmpty) {
              List<FileToSend> files = [];
              int totalSize = 0;
              
              for (var fileEntry in detail.files) {
                File file = File(fileEntry.path);
                String fileName = fileEntry.path.split(Platform.isWindows ? '\\' : '/').last;
                int fileSize = file.lengthSync();
                
                // Validate file size
                if (fileSize > MAX_FILE_SIZE) {
                  _showSnackBar(
                    'File $fileName is too large. Maximum size is ${_formatFileSize(MAX_FILE_SIZE)}',
                    Icons.error_rounded,
                    Colors.red,
                  );
                  continue;
                }
                
                String fileType = lookupMimeType(fileEntry.path) ?? 'application/octet-stream';
                
                files.add(FileToSend(
                  file: file,
                  name: fileName,
                  size: fileSize,
                  type: fileType,
                  progress: 0.0,
                  bytesSent: 0,
                  status: 'Pending',
                ));
                
                totalSize += fileSize;
              }
              
              if (files.isNotEmpty) {
                _prepareFiles(files, totalSize);
                _controller.reset();
                _controller.forward();
                setState(() {
                  _currentStep = 2;
                });
              }
            }
          },
          onDragEntered: (detail) {
            setState(() {
              _isHovering = true;
            });
          },
          onDragExited: (detail) {
            setState(() {
              _isHovering = false;
            });
          },
          child: Container(
            padding: contentPadding,
            width: double.infinity,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Lottie.asset(
                    'assets/upload_animation.json',
                    width: animationSize,
                    height: animationSize,
                    fit: BoxFit.contain,
                    repeat: _isHovering,
                    animate: _isHovering,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        width: context.isMobile ? 60 : 80,
                        height: context.isMobile ? 60 : 80,
                        decoration: BoxDecoration(
                          color: const Color(0xFF4E6AF3).withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.cloud_upload_rounded,
                          size: iconSize,
                          color: _isHovering ? const Color(0xFF4E6AF3) : Colors.grey[400],
                        ),
                      );
                    },
                  ),
                ),
                SizedBox(height: context.isMobile ? 16 : 24),
                Text(
                  _isHovering ? 'Release to Upload' : 'Drop Files Here',
                  style: TextStyle(
                    fontSize: headingSize,
                    fontWeight: FontWeight.bold,
                    color: _isHovering ? const Color(0xFF4E6AF3) : Colors.grey[700],
                  ),
                ),
                SizedBox(height: context.isMobile ? 8 : 12),
                Text(
                  'or',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: (context.isMobile ? 12 : 14) * context.fontSizeMultiplier,
                  ),
                ),
                SizedBox(height: context.isMobile ? 16 : 24),
                ElevatedButton.icon(
                  onPressed: _pickFile,
                  icon: Icon(Icons.add_rounded, size: context.isMobile ? 16 : 18),
                  label: Text('Select Files'),
                  style: ElevatedButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: const Color(0xFF4E6AF3),
                    padding: EdgeInsets.symmetric(
                      horizontal: context.isMobile ? 20 : 24,
                      vertical: context.isMobile ? 12 : 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                    shadowColor: const Color(0xFF4E6AF3).withOpacity(0.3),
                  ),
                ),
                SizedBox(height: context.isMobile ? 20 : 32),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: context.isMobile ? 12 : 16, 
                    vertical: context.isMobile ? 8 : 10
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark 
                        ? Colors.grey[800]
                        : Colors.grey[100],
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.info_outline_rounded, 
                          size: context.isMobile ? 14 : 16, 
                          color: Colors.grey[600]),
                      SizedBox(width: context.isMobile ? 6 : 8),
                      Text(
                        'Multiple files supported • Max ${_formatFileSize(MAX_FILE_SIZE)} per file',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: (context.isMobile ? 11 : 12) * context.fontSizeMultiplier,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
  
  Widget _buildSelectedFilesInfo() {
    return Padding(
      padding: context.responsivePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Selected Files (${_selectedFiles.length})',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: (context.isMobile ? 14 : 16) * context.fontSizeMultiplier,
            ),
          ),
          
          SizedBox(height: context.isMobile ? 6 : 8),
          
          Text(
            'Total Size: ${_formatFileSize(_totalFileSize)}',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: (context.isMobile ? 12 : 13) * context.fontSizeMultiplier,
            ),
          ),
          
          SizedBox(height: context.isMobile ? 12 : 16),
          
          // List of selected files
          Expanded(
            child: ListView.builder(
              itemCount: _selectedFiles.length,
              itemBuilder: (context, index) {
                final file = _selectedFiles[index];
                return Card(
                  margin: EdgeInsets.only(bottom: context.isMobile ? 6 : 8),
                  child: ListTile(
                    dense: context.isMobile,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: context.isMobile ? 12 : 16,
                      vertical: context.isMobile ? 4 : 8,
                    ),
                    leading: Container(
                      padding: EdgeInsets.all(context.isMobile ? 6 : 8),
                      decoration: BoxDecoration(
                        color: _getFileIconColor(file.type).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        _getFileIconData(file.type),
                        size: context.isMobile ? 16 : 20,
                        color: _getFileIconColor(file.type),
                      ),
                    ),
                    title: Text(
                      file.name,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: (context.isMobile ? 12 : 14) * context.fontSizeMultiplier,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      _formatFileSize(file.size),
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: (context.isMobile ? 10 : 12) * context.fontSizeMultiplier,
                      ),
                    ),
                    trailing: IconButton(
                      icon: Icon(Icons.close, size: context.isMobile ? 16 : 18),
                      onPressed: () => _removeFile(index),
                      tooltip: 'Remove file',
                    ),
                  ),
                );
              },
            ),
          ),
          
          SizedBox(height: context.isMobile ? 12 : 16),
          
          // Action buttons - Responsive layout
          if (context.isMobile) ...[
            // Mobile: Full-width stacked buttons
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: _pickFile,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add More Files'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF4E6AF3),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _currentStep = 2;
                  });
                },
                icon: const Icon(Icons.arrow_forward),
                label: const Text('Continue to Select Receiver'),
                style: ElevatedButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: const Color(0xFF4E6AF3),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ] else ...[
            // Desktop: Centered buttons
            Center(
              child: TextButton.icon(
                onPressed: _pickFile,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add More Files'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF4E6AF3),
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            Center(
              child: ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _currentStep = 2;
                  });
                },
                icon: const Icon(Icons.arrow_forward),
                label: const Text('Continue to Select Receiver'),
                style: ElevatedButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: const Color(0xFF4E6AF3),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
  
  Widget _buildSelectReceiverStep() {
    return Card(
      child: Padding(
        padding: context.responsivePadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Selected files summary - Responsive
            _buildFilesSummary(),
            
            SizedBox(height: context.isMobile ? 12 : 16),
            
            // Search bar - Responsive
            _buildSearchBar(),
            
            SizedBox(height: context.isMobile ? 12 : 16),
            
            // Receiver list - Scrollable content
            Expanded(
              child: _filteredReceivers.isEmpty
                  ? _buildEmptyReceiverState()
                  : _buildReceiverList(),
            ),
            
            SizedBox(height: context.isMobile ? 12 : 16),
            
            // Bottom navigation - Responsive
            _buildReceiverStepNavigation(),
          ],
        ),
      ),
    );
  }

  Widget _buildFilesSummary() {
    if (context.isMobile) {
      return Column(
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
                  Icons.folder_rounded,
                  size: 16,
                  color: Color(0xFF4E6AF3),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_selectedFiles.length} File${_selectedFiles.length > 1 ? 's' : ''} Selected',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Total: ${_formatFileSize(_totalFileSize)}',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: () {
                setState(() {
                  _currentStep = 1;
                });
              },
              icon: const Icon(Icons.edit, size: 14),
              label: const Text('Change Files'),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF4E6AF3),
                padding: const EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF4E6AF3).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(
            Icons.folder_rounded,
            size: 20,
            color: Color(0xFF4E6AF3),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_selectedFiles.length} File${_selectedFiles.length > 1 ? 's' : ''} Selected',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                'Total: ${_formatFileSize(_totalFileSize)}',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        TextButton.icon(
          onPressed: () {
            setState(() {
              _currentStep = 1;
            });
          },
          icon: const Icon(Icons.edit, size: 16),
          label: const Text('Change'),
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF4E6AF3),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.grey.withOpacity(0.3),
        ),
      ),
      padding: EdgeInsets.symmetric(horizontal: context.isMobile ? 10 : 12),
      child: Row(
        children: [
          Icon(Icons.search, color: Colors.grey[500], size: context.isMobile ? 18 : 20),
          SizedBox(width: context.isMobile ? 6 : 8),
          Expanded(
            child: TextField(
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                  _filteredReceivers = _filterReceivers();
                });
              },
              decoration: InputDecoration(
                hintText: 'Search receivers...',
                border: InputBorder.none,
                hintStyle: TextStyle(color: Colors.grey[500]),
              ),
              style: TextStyle(fontSize: (context.isMobile ? 12 : 14) * context.fontSizeMultiplier),
            ),
          ),
          if (_searchQuery.isNotEmpty)
            IconButton(
              icon: Icon(Icons.clear, size: context.isMobile ? 16 : 18),
              onPressed: () {
                setState(() {
                  _searchQuery = '';
                  _filteredReceivers = _filterReceivers();
                });
              },
            ),
        ],
      ),
    );
  }

  Widget _buildReceiverList() {
    return ListView.builder(
      itemCount: _filteredReceivers.length,
      itemBuilder: (context, index) {
        final receiver = _filteredReceivers[index];
        final isSelected = _selectedReceiverIndex == index;

        return Card(
          margin: EdgeInsets.only(bottom: context.isMobile ? 6 : 8),
          color: isSelected 
              ? const Color(0xFF4E6AF3).withOpacity(0.05)
              : null,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: isSelected
                  ? const Color(0xFF4E6AF3)
                  : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: InkWell(
            onTap: () {
              setState(() {
                _selectedReceiverIndex = index;
              });
            },
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: EdgeInsets.all(context.isMobile ? 10 : 12),
              child: Row(
                children: [
                  Container(
                    width: context.isMobile ? 32 : 40,
                    height: context.isMobile ? 32 : 40,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF4E6AF3).withOpacity(0.2)
                          : Theme.of(context).brightness == Brightness.dark
                              ? Colors.grey[800]
                              : Colors.grey[200],
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isSelected ? Icons.check : Icons.computer,
                      color: isSelected
                          ? const Color(0xFF4E6AF3)
                          : Colors.grey[600],
                      size: context.isMobile ? 16 : 20,
                    ),
                  ),
                  SizedBox(width: context.isMobile ? 10 : 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          receiver.name,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: (context.isMobile ? 12 : 14) * context.fontSizeMultiplier,
                            color: isSelected
                                ? const Color(0xFF4E6AF3)
                                : null,
                          ),
                        ),
                        Text(
                          receiver.ip,
                          style: TextStyle(
                            fontSize: (context.isMobile ? 10 : 12) * context.fontSizeMultiplier,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildReceiverStepNavigation() {
    if (context.isMobile) {
      return Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                setState(() {
                  _currentStep = 1;
                });
              },
              icon: const Icon(Icons.arrow_back),
              label: const Text('Back'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF4E6AF3),
                side: const BorderSide(color: Color(0xFF4E6AF3)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: (_filesSelected &&
                      _selectedReceiverIndex >= 0 &&
                      _selectedReceiverIndex < _filteredReceivers.length)
                  ? () => connectToReceiver(
                      _filteredReceivers[_selectedReceiverIndex].ip,
                      _filteredReceivers[_selectedReceiverIndex].name)
                  : null,
              icon: isConnecting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.send),
              label: Text(
                isConnecting ? 'Connecting...' : 'Send Files',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: const Color(0xFF4E6AF3),
                padding: const EdgeInsets.symmetric(vertical: 16),
                disabledBackgroundColor: Colors.grey[400],
              ),
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () {
              setState(() {
                _currentStep = 1;
              });
            },
            icon: const Icon(Icons.arrow_back),
            label: const Text('Back'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF4E6AF3),
              side: const BorderSide(color: Color(0xFF4E6AF3)),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 2,
          child: ElevatedButton.icon(
            onPressed: (_filesSelected &&
                    _selectedReceiverIndex >= 0 &&
                    _selectedReceiverIndex < _filteredReceivers.length)
                ? () => connectToReceiver(
                    _filteredReceivers[_selectedReceiverIndex].ip,
                    _filteredReceivers[_selectedReceiverIndex].name)
                : null,
            icon: isConnecting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.send),
            label: Text(
              isConnecting ? 'Connecting...' : 'Send Files',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: const Color(0xFF4E6AF3),
              padding: const EdgeInsets.symmetric(vertical: 12),
              disabledBackgroundColor: Colors.grey[400],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyReceiverState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Lottie.asset(
            'assets/searchss.json',
            height: context.isMobile ? 60 : 80,
            errorBuilder: (context, error, stackTrace) {
              return Icon(
                Icons.search_off_rounded,
                size: context.isMobile ? 40 : 60,
                color: Colors.grey[300],
              );
            },
          ),
          SizedBox(height: context.isMobile ? 8 : 10),
          Text(
            'No receivers found',
            style: TextStyle(
              color: Theme.of(context).brightness == Brightness.dark 
                  ? Colors.grey[300] 
                  : Colors.grey[700],
              fontSize: (context.isMobile ? 14 : 16) * context.fontSizeMultiplier,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: context.isMobile ? 6 : 8),
          Text(
            'Make sure devices are online and receiving',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.grey[500],
              fontSize: (context.isMobile ? 11 : 13) * context.fontSizeMultiplier,
            ),
          ),
          SizedBox(height: context.isMobile ? 16 : 24),
          OutlinedButton.icon(
            onPressed: isScanning ? null : startScanning,
            icon: isScanning
                ? SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: const Color(0xFF4E6AF3),
                    ),
                  )
                : const Icon(Icons.refresh_rounded),
            label: Text(isScanning ? 'Scanning...' : 'Scan Again'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF4E6AF3),
              side: const BorderSide(color: Color(0xFF4E6AF3), width: 1.5),
              padding: EdgeInsets.symmetric(
                horizontal: context.isMobile ? 12 : 16, 
                vertical: context.isMobile ? 8 : 10
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildTransferStep() {
    return Card(
      child: Padding(
        padding: context.responsivePadding,
        child: Column(
          children: [
            // Header with receiver info - Responsive
            _buildTransferHeader(),
            
            Divider(height: context.isMobile ? 24 : 32),
            
            // Overall progress - Responsive
            _buildOverallProgress(),
            
            SizedBox(height: context.isMobile ? 12 : 16),
            
            // List of files with their progress - Responsive
            Expanded(
              child: _buildTransferFileList(),
            ),
            
            SizedBox(height: context.isMobile ? 16 : 20),
            
            // Bottom navigation - Responsive
            _buildTransferNavigation(),
          ],
        ),
      ),
    );
  }

  Widget _buildTransferHeader() {
    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(context.isMobile ? 8 : 10),
          decoration: BoxDecoration(
            color: const Color(0xFF4E6AF3).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            Icons.computer_rounded,
            size: context.isMobile ? 16 : 20,
            color: Color(0xFF4E6AF3),
          ),
        ),
        SizedBox(width: context.isMobile ? 8 : 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Sending to: ${_receiverName ?? "Device"}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: (context.isMobile ? 14 : 16) * context.fontSizeMultiplier,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                'From: ${_userLogin}',
                style: TextStyle(
                  fontSize: (context.isMobile ? 10 : 12) * context.fontSizeMultiplier,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOverallProgress() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Overall Progress',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: (context.isMobile ? 12 : 14) * context.fontSizeMultiplier,
              ),
            ),
            Text(
              '${(_progress * 100).toStringAsFixed(1)}%',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: _transferComplete 
                    ? const Color(0xFF2AB673) 
                    : const Color(0xFF4E6AF3),
                fontSize: (context.isMobile ? 12 : 14) * context.fontSizeMultiplier,
              ),
            ),
          ],
        ),
        SizedBox(height: context.isMobile ? 6 : 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: _progress,
            backgroundColor: Colors.grey[300],
            valueColor: AlwaysStoppedAnimation<Color>(
              _transferComplete 
                  ? const Color(0xFF2AB673) 
                  : const Color(0xFF4E6AF3),
            ),
            minHeight: context.isMobile ? 6 : 8,
          ),
        ),
        
        SizedBox(height: context.isMobile ? 4 : 6),
        
        Text(
          'Sending file ${_currentFileIndex + 1} of ${_selectedFiles.length}',
          style: TextStyle(
            fontSize: (context.isMobile ? 10 : 12) * context.fontSizeMultiplier,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildTransferFileList() {
    return ListView.builder(
      itemCount: _selectedFiles.length,
      itemBuilder: (context, index) {
        final file = _selectedFiles[index];
        final isCurrentFile = index == _currentFileIndex;
        
        // Determine status color
        Color statusColor;
        if (file.status == 'Completed') {
          statusColor = const Color(0xFF2AB673);
        } else if (file.status == 'Failed') {
          statusColor = Colors.red;
        } else if (file.status == 'Sending') {
          statusColor = const Color(0xFF4E6AF3);
        } else {
          statusColor = Colors.grey;
        }
        
        return Card(
          margin: EdgeInsets.only(bottom: context.isMobile ? 6 : 8),
          color: isCurrentFile 
              ? const Color(0xFF4E6AF3).withOpacity(0.05)
              : null,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: EdgeInsets.all(context.isMobile ? 10 : 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(context.isMobile ? 6 : 8),
                      decoration: BoxDecoration(
                        color: _getFileIconColor(file.type).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        _getFileIconData(file.type),
                        size: context.isMobile ? 14 : 18,
                        color: _getFileIconColor(file.type),
                      ),
                    ),
                    SizedBox(width: context.isMobile ? 8 : 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            file.name,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: (context.isMobile ? 12 : 14) * context.fontSizeMultiplier,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${_formatFileSize(file.bytesSent)} of ${_formatFileSize(file.size)}',
                            style: TextStyle(
                              fontSize: (context.isMobile ? 10 : 12) * context.fontSizeMultiplier,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: context.isMobile ? 6 : 8, 
                        vertical: context.isMobile ? 3 : 4
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isCurrentFile && file.status == 'Sending')
                            SizedBox(
                              width: context.isMobile ? 8 : 10,
                              height: context.isMobile ? 8 : 10,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                              ),
                            )
                          else if (file.status == 'Completed')
                            Icon(Icons.check_circle, size: context.isMobile ? 8 : 10, color: statusColor)
                          else if (file.status == 'Failed')
                            Icon(Icons.error, size: context.isMobile ? 8 : 10, color: statusColor)
                          else
                            Icon(Icons.schedule, size: context.isMobile ? 8 : 10, color: statusColor),
                          SizedBox(width: context.isMobile ? 3 : 4),
                          Text(
                            file.status,
                            style: TextStyle(
                              fontSize: (context.isMobile ? 9 : 10) * context.fontSizeMultiplier,
                              fontWeight: FontWeight.bold,
                              color: statusColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                
                if (isCurrentFile || file.progress > 0)
                  Padding(
                    padding: EdgeInsets.only(top: context.isMobile ? 6 : 8),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: file.progress,
                        backgroundColor: Colors.grey[300],
                        valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                        minHeight: context.isMobile ? 3 : 4,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTransferNavigation() {
    if (context.isMobile) {
      return Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _transferComplete || !_isSending 
                  ? () {
                      setState(() {
                        _currentStep = 2;
                      });
                    } 
                  : null,
              icon: const Icon(Icons.arrow_back),
              label: const Text('Back'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF4E6AF3),
                side: const BorderSide(color: Color(0xFF4E6AF3)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _transferComplete 
                  ? () {
                      setState(() {
                        _currentStep = 1;
                        _filesSelected = false;
                        _selectedFiles = [];
                        _transferComplete = false;
                        _totalFileSize = 0;
                        _totalBytesSent = 0;
                        _currentFileIndex = 0;
                      });
                    } 
                  : null,
              icon: const Icon(Icons.refresh),
              label: const Text(
                'Send More Files',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: const Color(0xFF2AB673),
                padding: const EdgeInsets.symmetric(vertical: 16),
                disabledBackgroundColor: Colors.grey[400],
              ),
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _transferComplete || !_isSending 
                ? () {
                    setState(() {
                      _currentStep = 2;
                    });
                  } 
                : null,
            icon: const Icon(Icons.arrow_back),
            label: const Text('Back'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF4E6AF3),
              side: const BorderSide(color: Color(0xFF4E6AF3)),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 2,
          child: ElevatedButton.icon(
            onPressed: _transferComplete 
                ? () {
                    setState(() {
                      _currentStep = 1;
                      _filesSelected = false;
                      _selectedFiles = [];
                      _transferComplete = false;
                      _totalFileSize = 0;
                      _totalBytesSent = 0;
                      _currentFileIndex = 0;
                    });
                  } 
                : null,
            icon: const Icon(Icons.refresh),
            label: const Text(
              'Send More Files',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: const Color(0xFF2AB673),
              padding: const EdgeInsets.symmetric(vertical: 12),
              disabledBackgroundColor: Colors.grey[400],
            ),
          ),
        ),
      ],
    );
  }
}

class ReceiverDevice {
  final String name;
  final String ip;

  ReceiverDevice({required this.name, required this.ip});
}

class FileToSend {
  final File file;
  final String name;
  final int size;
  final String type;
  double progress;
  int bytesSent;
  String status;

  FileToSend({
    required this.file,
    required this.name,
    required this.size,
    required this.type,
    required this.progress,
    required this.bytesSent,
    required this.status,
  });
}