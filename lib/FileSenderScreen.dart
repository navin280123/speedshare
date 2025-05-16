import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mime/mime.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:animate_do/animate_do.dart';
import 'package:lottie/lottie.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';

class FileSenderScreen extends StatefulWidget {
  @override
  _FileSenderScreenState createState() => _FileSenderScreenState();
}

class _FileSenderScreenState extends State<FileSenderScreen> with SingleTickerProviderStateMixin {
  // Animation controllers
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<Offset> _slideAnimation;
  
  // File handling variables
  bool _isSending = false;
  double _progress = 0.0;
  String _fileName = '';
  int _fileSize = 0;
  String _fileType = '';
  bool _isHovering = false;
  bool _fileSelected = false;
  File? _selectedFile;
  bool _transferComplete = false;
  Directory? _tempDirectory;

  // Connection and discovery variables
  bool isScanning = false;
  bool isConnecting = false;
  Socket? socket;
  Timer? _scanTimer;
  String? _receiverName;

  // For device discovery
  List<ReceiverDevice> availableReceivers = [];
  int _selectedReceiverIndex = -1;
  bool _isDiscovering = false;
  Timer? _discoveryTimer;
  RawDatagramSocket? _discoverySocket;
  
  // UI state
  bool _showReceiverList = true;
  bool _showFileInfo = true;
  int _currentStep = 1; // 1: Select file, 2: Select receiver, 3: Transfer
  String _searchQuery = '';
  List<ReceiverDevice> _filteredReceivers = [];

  @override
  void initState() {
    super.initState();
    
    // Initialize animation controller
    _controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    
    _scaleAnimation = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutQuart,
      ),
    );
    
    _slideAnimation = Tween<Offset>(
      begin: Offset(0.1, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));
    
    _controller.forward();
    
    // Start scanning for devices
    startScanning();

    // Set up periodic discovery
    _discoveryTimer = Timer.periodic(Duration(seconds: 30), (timer) {
      if (mounted) startScanning();
    });
    
    // Initialize filtered receivers
    _filteredReceivers = availableReceivers;
  }

  void startScanning() {
    if (!mounted) return;
    
    setState(() {
      isScanning = true;
    });

    // Use UDP discovery to find receivers
    discoverWithUDP();

    // Set a timeout to end scanning
    _scanTimer = Timer(Duration(seconds: 5), () {
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
      
      // Create UDP socket for discovery
      _discoverySocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      
      // Listen for responses
      _discoverySocket!.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = _discoverySocket!.receive();
          if (datagram != null) {
            final message = utf8.decode(datagram.data);
            
            if (message.startsWith('SPEEDSHARE_RESPONSE:')) {
              final parts = message.split(':');
              if (parts.length >= 3) {
                final deviceName = parts[1];
                final ipAddress = datagram.address.address;
                
                // Add to the list if not already present
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
      
      // Try targeted discovery instead of broadcasting
      final interfaces = await NetworkInterface.list();
      for (var interface in interfaces) {
        // Skip loopback interfaces
        if (interface.name.contains('lo')) continue;
        
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4) {
            // Get the subnet for this network interface
            final parts = addr.address.split('.');
            if (parts.length == 4) {
              final subnet = parts.sublist(0, 3).join('.');
              final message = utf8.encode('SPEEDSHARE_DISCOVERY');
              
              // Try sending to specific common addresses in the subnet
              try {
                // Try subnet's gateway (usually .1)
                final gatewayAddress = InternetAddress('$subnet.1');
                _discoverySocket!.send(message, gatewayAddress, 8081);
                
                // Try device's own address (for loopback discovery)
                final ownAddress = InternetAddress(addr.address);
                _discoverySocket!.send(message, ownAddress, 8081);
                
                // Try a few other common IPs
                for (int i = 2; i < 10; i++) {
                  _discoverySocket!.send(message, InternetAddress('$subnet.$i'), 8081);
                }
                
                // Try sending to subnet broadcast (less likely to be blocked)
                _discoverySocket!.send(message, InternetAddress('$subnet.255'), 8081);
              } catch (e) {
                print('Failed to send discovery packet: $e');
                // Continue trying other addresses
              }
            }
          }
        }
      }
      
      // Fall back to TCP scanning if no devices found
      Timer(Duration(seconds: 2), () {
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
      
      // Fallback to direct TCP scanning
      if (mounted) checkDirectTCPConnections();
    }
  }

  // Fallback method to check TCP connections directly
  void checkDirectTCPConnections() async {
    try {
      final interfaces = await NetworkInterface.list();

      for (var interface in interfaces) {
        // Skip loopback interfaces
        if (interface.name.contains('lo')) continue;

        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4) {
            // Get the network prefix (e.g., 192.168.1)
            final parts = addr.address.split('.');
            if (parts.length == 4) {
              final prefix = parts.sublist(0, 3).join('.');

              // Scan some common IPs
              for (int i = 1; i <= 10; i++) {
                await checkReceiver('$prefix.$i');
              }
              await checkReceiver('$prefix.100');
              await checkReceiver('$prefix.101');
              await checkReceiver('$prefix.102');
              await checkReceiver('$prefix.255');
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
      // Try to connect to the potential receiver with a short timeout
      final socket =
          await Socket.connect(ip, 8080, timeout: Duration(milliseconds: 500))
              .catchError((e) => null);

      if (socket == null) return;

      // Listen for the device name
      final completer = Completer<String?>();

      // Set a timeout
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

      // Wait for device name or timeout
      final deviceName = await completer.future;
      socket.destroy();

      if (deviceName != null && deviceName.isNotEmpty && mounted) {
        setState(() {
          // Add to list if not already present
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
      // Connection failed, not a receiver
    }
  }

  void connectToReceiver(String ip, [String? name]) async {
    if (_selectedFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.white),
              SizedBox(width: 10),
              Text('Please select a file first', style: GoogleFonts.poppins()),
            ],
          ),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: EdgeInsets.all(20),
          elevation: 6,
          action: SnackBarAction(
            label: 'OK',
            textColor: Colors.white,
            onPressed: () {},
          ),
        ),
      );
      return;
    }

    setState(() {
      isConnecting = true;
      _currentStep = 3; // Move to transfer step
    });

    try {
      socket = await Socket.connect(ip, 8080, timeout: Duration(seconds: 5));

      String deviceName = name ?? '';

      // If no name was provided, try to get it from the socket
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

        // Wait briefly for device name
        try {
          deviceName = await completer.future.timeout(Duration(seconds: 1));
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

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle_rounded, color: Colors.white),
              SizedBox(width: 10),
              Text('Connected to $deviceName', style: GoogleFonts.poppins()),
            ],
          ),
          backgroundColor: Color(0xFF2AB673),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: EdgeInsets.all(20),
          elevation: 6,
        ),
      );

      // Set up listener for responses from receiver
      socket!.listen((data) {
        final message = utf8.decode(data);
        if (message == 'READY_FOR_FILE_DATA') {
          // Continue sending data if we were waiting for a ready signal
        } else if (message == 'TRANSFER_COMPLETE') {
          // Handle transfer completion
          if (mounted) {
            setState(() {
              _isSending = false;
              _transferComplete = true;
              _progress = 1.0;
            });
          }
        }
      }, onError: (error) {
        if (mounted) {
          setState(() {
            _isSending = false;
          });
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.error_outline_rounded, color: Colors.white),
                SizedBox(width: 10),
                Text('Connection error: ${error.toString().substring(0, min(error.toString().length, 50))}', 
                  style: GoogleFonts.poppins()),
              ],
            ),
            backgroundColor: Colors.red[700],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: EdgeInsets.all(20),
            elevation: 6,
          ),
        );
      }, onDone: () {
        if (_isSending && _progress < 1.0 && mounted) {
          setState(() {
            _isSending = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.error_outline_rounded, color: Colors.white),
                  SizedBox(width: 10),
                  Text('Connection closed unexpectedly', style: GoogleFonts.poppins()),
                ],
              ),
              backgroundColor: Colors.red[700],
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              margin: EdgeInsets.all(20),
              elevation: 6,
            ),
          );
        }
      });

      // Now send the file
      _sendFile();
    } catch (e) {
      if (mounted) {
        setState(() {
          isConnecting = false;
          _currentStep = 2; // Go back to receiver selection
        });
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.error_outline_rounded, color: Colors.white),
              SizedBox(width: 10),
              Text('Failed to connect: ${e.toString().substring(0, min(e.toString().length, 50))}', 
                style: GoogleFonts.poppins()),
            ],
          ),
          backgroundColor: Colors.red[700],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: EdgeInsets.all(20),
          elevation: 6,
          action: SnackBarAction(
            label: 'Retry',
            textColor: Colors.white,
            onPressed: () => connectToReceiver(ip, name),
          ),
        ),
      );
    }
  }

  void _pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
      dialogTitle: 'Select a file to send',
    );
    
    if (result != null) {
      _prepareFile(File(result.files.single.path!));
      
      // Play animation and update step
      _controller.reset();
      _controller.forward();
      
      setState(() {
        _currentStep = 2; // Move to receiver selection
      });
    }
  }

  void _prepareFile(File file) {
    setState(() {
      _selectedFile = file;
      _fileName = file.path.split(Platform.isWindows ? '\\' : '/').last;
      _fileSize = file.lengthSync();
      _fileType = lookupMimeType(file.path) ?? 'application/octet-stream';
      _fileSelected = true;
      _transferComplete = false;
      _showFileInfo = true;
    });
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024)
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  void _sendFile() async {
    if (_selectedFile == null || socket == null) return;

    setState(() {
      _isSending = true;
      _progress = 0;
    });

    try {
      // Create metadata in JSON format
      final metadata = {
        'fileName': _fileName,
        'fileSize': _fileSize,
        'fileType': _fileType,
        'sender': 'navin280123',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      // Convert metadata to JSON string
      final metadataStr = json.encode(metadata);
      final metadataBytes = utf8.encode(metadataStr);

      // Send metadata size as first 4 bytes (int32)
      final metadataSize = Uint8List(4);
      ByteData.view(metadataSize.buffer).setInt32(0, metadataBytes.length);
      socket!.add(metadataSize);

      // Send metadata
      socket!.add(metadataBytes);

      // Wait for a small delay to ensure metadata is processed
      await Future.delayed(Duration(milliseconds: 100));

      // Read file as bytes
      final fileBytes = await _selectedFile!.readAsBytes();

      // Adaptive buffer size based on file size
      final int bufferSize = _fileSize > 100 * 1024 * 1024 
          ? 32 * 1024  // 32KB for large files
          : 4 * 1024;  // 4KB for smaller files
          
      int bytesSent = 0;
      int lastProgressUpdate = 0;
      final int updateThreshold = (_fileSize / 100).round(); // Update every 1%

      for (int i = 0; i < fileBytes.length; i += bufferSize) {
        // Check if socket is still connected
        if (socket == null) {
          throw Exception("Connection lost");
        }

        int end = (i + bufferSize < fileBytes.length)
            ? i + bufferSize
            : fileBytes.length;
        List<int> chunk = fileBytes.sublist(i, end);

        socket!.add(chunk);
        bytesSent += chunk.length;

        // Only update UI every 1% to avoid excessive rebuilds
        if (bytesSent - lastProgressUpdate > updateThreshold && mounted) {
          setState(() {
            _progress = bytesSent / fileBytes.length;
          });
          lastProgressUpdate = bytesSent;
        }

        // Adaptive delay based on network conditions
        if (i % (bufferSize * 10) == 0) {
          await Future.delayed(Duration(milliseconds: 1));
        }
      }

      // Ensure progress shows 100% during waiting for completion confirmation
      if (mounted) {
        setState(() {
          _progress = 1.0;
        });
      }

      // If we don't get the completion message within a timeout, consider it complete anyway
      Timer(Duration(seconds: 15), () {
        if (_isSending && _progress >= 0.99 && mounted) {
          setState(() {
            _isSending = false;
            _transferComplete = true;
            _progress = 1.0;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle_rounded, color: Colors.white),
                  SizedBox(width: 10),
                  Text('File sent successfully!', style: GoogleFonts.poppins()),
                ],
              ),
              backgroundColor: Color(0xFF2AB673),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              margin: EdgeInsets.all(20),
              elevation: 6,
              action: SnackBarAction(
                label: 'Send Another',
                textColor: Colors.white,
                onPressed: () {
                  setState(() {
                    _currentStep = 1;
                    _fileSelected = false;
                    _selectedFile = null;
                    _transferComplete = false;
                  });
                },
              ),
            ),
          );
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.error_outline_rounded, color: Colors.white),
              SizedBox(width: 10),
              Text('Error sending file: ${e.toString().substring(0, min(e.toString().length, 50))}', 
                style: GoogleFonts.poppins()),
            ],
          ),
          backgroundColor: Colors.red[700],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: EdgeInsets.all(20),
          elevation: 6,
          action: SnackBarAction(
            label: 'Retry',
            textColor: Colors.white,
            onPressed: _sendFile,
          ),
        ),
      );
    }
  }

  Widget _buildFilePreview() {
    IconData iconData;
    Color iconColor;
    Widget? filePreviewWidget;

    // Determine file type icon and color
    if (_fileType.startsWith('image/')) {
      iconData = Icons.image_rounded;
      iconColor = Color(0xFF3498db);
      
      // Generate image preview
      if (_selectedFile != null && _selectedFile!.existsSync()) {
        try {
          filePreviewWidget = ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(
              _selectedFile!,
              height: 100,
              width: 100,
              fit: BoxFit.cover,
              errorBuilder: (ctx, obj, stack) => Container(
                height: 100,
                width: 100,
                color: iconColor.withOpacity(0.1),
                child: Icon(iconData, size: 40, color: iconColor),
              ),
            ),
          );
        } catch (e) {
          // Fallback to icon if image can't be loaded
          filePreviewWidget = null;
        }
      }
    } else if (_fileType.startsWith('video/')) {
      iconData = Icons.video_file_rounded;
      iconColor = Color(0xFFe74c3c);
    } else if (_fileType.startsWith('audio/')) {
      iconData = Icons.audio_file_rounded;
      iconColor = Color(0xFF9b59b6);
    } else if (_fileType.contains('pdf')) {
      iconData = Icons.picture_as_pdf_rounded;
      iconColor = Color(0xFFe74c3c);
    } else if (_fileType.contains('word') || _fileType.contains('document')) {
      iconData = Icons.description_rounded;
      iconColor = Color(0xFF3498db);
    } else if (_fileType.contains('excel') || _fileType.contains('sheet')) {
      iconData = Icons.table_chart_rounded;
      iconColor = Color(0xFF2ecc71);
    } else if (_fileType.contains('presentation') || _fileType.contains('powerpoint')) {
      iconData = Icons.slideshow_rounded;
      iconColor = Color(0xFFe67e22);
    } else if (_fileType.contains('zip') || _fileType.contains('compressed')) {
      iconData = Icons.folder_zip_rounded;
      iconColor = Color(0xFFf39c12);
    } else if (_fileType.contains('text') || _fileType.contains('txt')) {
      iconData = Icons.text_snippet_rounded;
      iconColor = Color(0xFF7f8c8d);
    } else {
      iconData = Icons.insert_drive_file_rounded;
      iconColor = Color(0xFF95a5a6);
    }

    return SlideTransition(
      position: _slideAnimation,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Card(
          elevation: 4,
          shadowColor: Colors.black.withOpacity(0.2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Show file preview if available, otherwise show icon
                    filePreviewWidget != null
                      ? Hero(
                          tag: 'file-preview',
                          child: filePreviewWidget,
                        )
                      : Container(
                          padding: EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: iconColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(iconData, size: 40, color: iconColor),
                        ),
                    SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _fileName,
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Colors.grey[800],
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          SizedBox(height: 6),
                          Row(
                            children: [
                              Container(
                                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: iconColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  _fileType.split('/').last.toUpperCase(),
                                  style: GoogleFonts.poppins(
                                    color: iconColor,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              SizedBox(width: 8),
                              Text(
                                _formatFileSize(_fileSize),
                                style: GoogleFonts.poppins(
                                  color: Colors.grey[600],
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 10),
                          Text(
                            'Selected ${_getTimeAgo()}',
                            style: GoogleFonts.poppins(
                              color: Colors.grey[500],
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close_rounded),
                      onPressed: () {
                        setState(() {
                          _fileSelected = false;
                          _selectedFile = null;
                          _transferComplete = false;
                          _currentStep = 1; // Go back to file selection
                        });
                      },
                      tooltip: 'Remove file',
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.grey.withOpacity(0.1),
                        foregroundColor: Colors.grey[700],
                      ),
                    ),
                  ],
                ),
                if (_isSending || _transferComplete) ...[
                  SizedBox(height: 24),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Transfer Progress',
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Colors.grey[800],
                            ),
                          ),
                          Text(
                            '${(_progress * 100).toStringAsFixed(1)}%',
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.bold,
                              color: _transferComplete 
                                ? Color(0xFF2AB673) 
                                : Color(0xFF4E6AF3),
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 12),
                      Stack(
                        children: [
                          // Background
                          Container(
                            height: 10,
                            decoration: BoxDecoration(
                              color: Colors.grey[200],
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          // Progress
                          AnimatedContainer(
                            duration: Duration(milliseconds: 300),
                            height: 10,
                            width: MediaQuery.of(context).size.width * _progress * 0.65,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: _transferComplete
                                  ? [Color(0xFF2AB673), Color(0xFF1D9A62)]
                                  : [Color(0xFF4E6AF3), Color(0xFF3F58C7)],
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                              ),
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: [
                                BoxShadow(
                                  color: _transferComplete
                                    ? Color(0xFF2AB673).withOpacity(0.3)
                                    : Color(0xFF4E6AF3).withOpacity(0.3),
                                  blurRadius: 6,
                                  offset: Offset(0, 3),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(
                                _transferComplete
                                  ? Icons.devices_rounded
                                  : Icons.device_hub_rounded,
                                size: 14,
                                color: Colors.grey[600],
                              ),
                              SizedBox(width: 6),
                              Text(
                                'To: ${_receiverName ?? "Device"}',
                                style: GoogleFonts.poppins(
                                  color: Colors.grey[600],
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                          AnimatedSwitcher(
                            duration: Duration(milliseconds: 300),
                            child: _transferComplete
                              ? Row(
                                  key: ValueKey('complete'),
                                  children: [
                                    Container(
                                      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Color(0xFF2AB673).withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: Color(0xFF2AB673).withOpacity(0.2),
                                          width: 1,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(Icons.check_circle_rounded, 
                                            color: Color(0xFF2AB673), size: 14),
                                          SizedBox(width: 4),
                                          Text(
                                            'Complete',
                                            style: GoogleFonts.poppins(
                                              fontWeight: FontWeight.normal,
                                              color: Color(0xFF2AB673),
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                )
                              : Row(
                                  key: ValueKey('sending'),
                                  children: [
                                    SpinKitThreeBounce(
                                      color: Color(0xFF4E6AF3),
                                      size: 14,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'Sending...',
                                      style: GoogleFonts.poppins(
                                        fontStyle: FontStyle.italic,
                                        color: Color(0xFF4E6AF3),
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (_transferComplete) ...[
                    SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () {
                            setState(() {
                              _currentStep = 1;
                              _fileSelected = false;
                              _selectedFile = null;
                              _transferComplete = false;
                            });
                          },
                          icon: Icon(Icons.add_rounded),
                          label: Text('Send Another File'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Color(0xFF4E6AF3),
                            side: BorderSide(color: Color(0xFF4E6AF3), width: 1.5),
                            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getTimeAgo() {
    // This would be the actual time since file selection
    // For now, we'll just return "just now" as a placeholder
    return "just now";
  }

  @override
  void dispose() {
    _controller.dispose();
    _scanTimer?.cancel();
    _discoveryTimer?.cancel();
    _discoverySocket?.close();
    socket?.close();
    _tempDirectory?.deleteSync(recursive: true);
    super.dispose();
  }

  // Build a file drop area using desktop_drop
  Widget _buildFileDropArea() {
    return DropTarget(
      onDragDone: (detail) async {
        // Handle the dropped files
        if (detail.files.isNotEmpty) {
          final file = detail.files.first;
          final fileData = File(file.path);
          _prepareFile(fileData);
          
          // Play animation and update step
          _controller.reset();
          _controller.forward();
          
          setState(() {
            _currentStep = 2; // Move to receiver selection
          });
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
      child: AnimatedContainer(
        duration: Duration(milliseconds: 300),
        decoration: BoxDecoration(
          color: _isHovering
              ? Color(0xFF4E6AF3).withOpacity(0.1)
              : Colors.grey.withOpacity(0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _isHovering ? Color(0xFF4E6AF3) : Colors.grey.withOpacity(0.3),
            width: 2,
            style: BorderStyle.solid,
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Use SVG or Lottie animation if available
                Lottie.asset(
                  'assets/upload_animation.json',
                  width: 180,
                  height: 180,
                  fit: BoxFit.contain,
                  repeat: _isHovering,
                  animate: _isHovering,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        color: Color(0xFF4E6AF3).withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.cloud_upload_rounded,
                        size: 60,
                        color: _isHovering ? Color(0xFF4E6AF3) : Colors.grey[400],
                      ),
                    );
                  },
                ),
                SizedBox(height: 16),
                Text(
                  _isHovering ? 'Release to Upload' : 'Drop Files Here',
                  style: GoogleFonts.poppins(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: _isHovering ? Color(0xFF4E6AF3) : Colors.grey[700],
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'or',
                  style: GoogleFonts.poppins(
                    color: Colors.grey[600],
                    fontSize: 14,
                  ),
                ),
                SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _pickFile,
                  icon: Icon(Icons.add_rounded),
                  label: Text('Select File'),
                  style: ElevatedButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: Color(0xFF4E6AF3),
                    padding: EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 4,
                    shadowColor: Color(0xFF4E6AF3).withOpacity(0.3),
                    textStyle: GoogleFonts.poppins(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
                SizedBox(height: 24),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.info_outline_rounded, size: 16, color: Colors.grey[600]),
                      SizedBox(width: 8),
                      Text(
                        'Maximum file size: 4GB',
                        style: GoogleFonts.poppins(
                          color: Colors.grey[600],
                          fontSize: 12,
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
    );
  }

  // Filter receivers based on search query
  List<ReceiverDevice> _filterReceivers() {
    if (_searchQuery.isEmpty) {
      return availableReceivers;
    }
    
    return availableReceivers.where((device) => 
      device.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
      device.ip.contains(_searchQuery)
    ).toList();
  }

  // Search bar for filtering receivers
  Widget _buildSearchBar() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        onChanged: (value) {
          setState(() {
            _searchQuery = value;
            _filteredReceivers = _filterReceivers();
          });
        },
        decoration: InputDecoration(
          hintText: 'Search devices...',
          hintStyle: GoogleFonts.poppins(
            color: Colors.grey[400],
            fontSize: 14,
          ),
          prefixIcon: Icon(Icons.search_rounded, color: Colors.grey[400]),
          border: InputBorder.none,
          contentPadding: EdgeInsets.zero,
        ),
        style: GoogleFonts.poppins(
          fontSize: 14,
          color: Colors.grey[800],
        ),
      ),
    );
  }

  // Build steppers for process indication
  Widget _buildStepper() {
    return Row(
      children: [
        _buildStepperItem(1, 'Select File', _currentStep >= 1),
        _buildStepperConnector(_currentStep >= 2),
        _buildStepperItem(2, 'Select Receiver', _currentStep >= 2),
        _buildStepperConnector(_currentStep >= 3),
        _buildStepperItem(3, 'Transfer', _currentStep >= 3),
      ],
    );
  }

  Widget _buildStepperItem(int step, String label, bool isActive) {
    return Expanded(
      child: Column(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: isActive ? Color(0xFF4E6AF3) : Colors.grey[300],
              shape: BoxShape.circle,
              boxShadow: isActive ? [
                BoxShadow(
                  color: Color(0xFF4E6AF3).withOpacity(0.3),
                  blurRadius: 8,
                  offset: Offset(0, 3),
                ),
              ] : null,
            ),
            child: Center(
              child: isActive && step < _currentStep
                ? Icon(Icons.check, color: Colors.white, size: 16)
                : Text(
                    '$step',
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
            ),
          ),
          SizedBox(height: 8),
          Text(
            label,
            style: GoogleFonts.poppins(
              color: isActive ? Color(0xFF4E6AF3) : Colors.grey[500],
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              fontSize: 12,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildStepperConnector(bool isActive) {
    return Container(
      width: 40,
      height: 2,
      color: isActive ? Color(0xFF4E6AF3) : Colors.grey[300],
    );
  }

  // Calculate the minimum of two integers (helper function)
  int min(int a, int b) {
    return a < b ? a : b;
  }

  @override
  Widget build(BuildContext context) {
    // Get screen size for responsive design
    final Size screenSize = MediaQuery.of(context).size;
    final bool isSmallScreen = screenSize.width < 900;
    final bool isMediumScreen = screenSize.width >= 900 && screenSize.width < 1400;
    
    return Scaffold(
      body: FadeIn(
        duration: Duration(milliseconds: 600),
        child: Container(
          color: Colors.grey[50],
          padding: EdgeInsets.all(isSmallScreen ? 12 : 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with stepper
              FadeInDown(
                duration: Duration(milliseconds: 600),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Color(0xFF4E6AF3).withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.send_rounded,
                            size: 24,
                            color: Color(0xFF4E6AF3),
                          ),
                        ),
                        SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Send Files',
                              style: GoogleFonts.poppins(
                                fontSize: isSmallScreen ? 20 : 24,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF4E6AF3),
                              ),
                            ),
                            Text(
                              'Share files quickly between devices',
                              style: GoogleFonts.poppins(
                                color: Colors.grey[600],
                                fontSize: isSmallScreen ? 12 : 14,
                              ),
                            ),
                          ],
                        ),
                        Spacer(),
                        // Current date/time
                        if (!isSmallScreen)
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 10,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.access_time_rounded, size: 16, color: Colors.grey[600]),
                                SizedBox(width: 6),
                                Text(
                                  '2025-05-15 16:53',
                                  style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    color: Colors.grey[700],
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    SizedBox(height: 24),
                    _buildStepper(),
                  ],
                ),
              ),
              SizedBox(height: 24),

              // Main content area
              Expanded(
                child: isSmallScreen
                    ? _buildMobileLayout()
                    : _buildDesktopLayout(isMediumScreen),
              ),

              // Bottom section: Send button
              if (_currentStep == 2 && _fileSelected && !isSmallScreen)
                Column(
                  children: [
                    SizedBox(height: 16),
                    FadeInUp(
                      duration: Duration(milliseconds: 600),
                      child: SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton.icon(
                          onPressed: (_fileSelected &&
                                  _selectedReceiverIndex >= 0 &&
                                  _selectedReceiverIndex < availableReceivers.length &&
                                  !_isSending &&
                                  !_transferComplete &&
                                  !isConnecting)
                              ? () => connectToReceiver(
                                  availableReceivers[_selectedReceiverIndex].ip,
                                  availableReceivers[_selectedReceiverIndex].name)
                              : null,
                          icon: isConnecting
                              ? SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : Icon(Icons.send_rounded),
                          label: Text(
                            isConnecting ? 'Connecting...' : 'Send File',
                            style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          style: ElevatedButton.styleFrom(
                            foregroundColor: Colors.white,
                            backgroundColor: Color(0xFF4E6AF3),
                            disabledBackgroundColor: Colors.grey[300],
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 4,
                            shadowColor: Color(0xFF4E6AF3).withOpacity(0.3),
                          ),
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
    switch (_currentStep) {
      case 1:
        return _buildMobileFileSelection();
      case 2:
        return _buildMobileReceiverSelection();
      case 3:
        return _buildMobileTransfer();
      default:
        return _buildMobileFileSelection();
    }
  }
  
  Widget _buildMobileFileSelection() {
    return SingleChildScrollView(
      child: Column(
        children: [
          // File card
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Color(0xFF4E6AF3).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.file_present_rounded,
                          color: Color(0xFF4E6AF3),
                          size: 20,
                        ),
                      ),
                      SizedBox(width: 12),
                      Text(
                        'Select File',
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Color(0xFF4E6AF3),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 16),
                  
                  // File area
                  Container(
                    height: 350,
                    child: _fileSelected
                        ? _buildFilePreview()
                        : _buildFileDropArea(),
                  ),
                  
                  // Next button - only when file is selected
                  if (_fileSelected) ...[
                    SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          setState(() {
                            _currentStep = 2; // Move to receiver selection
                          });
                        },
                        icon: Icon(Icons.arrow_forward_rounded),
                        label: Text(
                          'Continue to Select Receiver',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: Color(0xFF4E6AF3),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 2,
                          shadowColor: Color(0xFF4E6AF3).withOpacity(0.3),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          
          SizedBox(height: 20),
          
          // Recent files card
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Color(0xFF2AB673).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.history_rounded,
                          color: Color(0xFF2AB673),
                          size: 20,
                        ),
                      ),
                      SizedBox(width: 12),
                      Text(
                        'Recent Files',
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Color(0xFF2AB673),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 16),
                  
                  // Recent files - Empty state as a placeholder
                  Container(
                    padding: EdgeInsets.symmetric(vertical: 30),
                    width: double.infinity,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.history_rounded,
                          size: 48,
                          color: Colors.grey[300],
                        ),
                        SizedBox(height: 16),
                        Text(
                          'No recent files',
                          style: GoogleFonts.poppins(
                            color: Colors.grey[600],
                            fontSize: 14,
                            fontWeight: FontWeight.normal,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Files you\'ve sent will appear here',
                          style: GoogleFonts.poppins(
                            color: Colors.grey[500],
                            fontSize: 12,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildMobileReceiverSelection() {
    return Column(
      children: [
        // Search and available receivers
        Expanded(
          child: Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: Color(0xFF4E6AF3).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              Icons.devices_rounded,
                              color: Color(0xFF4E6AF3),
                              size: 20,
                            ),
                          ),
                          SizedBox(width: 12),
                          Text(
                            'Available Receivers',
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Color(0xFF4E6AF3),
                            ),
                          ),
                        ],
                      ),
                      if (isScanning)
                        SpinKitThreeBounce(
                          color: Color(0xFF4E6AF3),
                          size: 14,
                        ),
                    ],
                  ),
                  SizedBox(height: 16),
                  
                  // Search bar
                  _buildSearchBar(),
                  SizedBox(height: 16),
                  
                  // Currently selected file info
                  if (_fileSelected) ...[
                    Container(
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.file_present_rounded,
                            color: Color(0xFF4E6AF3),
                            size: 20,
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _fileName,
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                color: Colors.grey[800],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          SizedBox(width: 10),
                          TextButton(
                            onPressed: () {
                              setState(() {
                                _currentStep = 1; // Go back to file selection
                              });
                            },
                            child: Text(
                              'Change',
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                color: Color(0xFF4E6AF3),
                              ),
                            ),
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              minimumSize: Size(0, 0),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 16),
                  ],
                  
                  // Device list
                  Expanded(
                    child: _filteredReceivers.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Lottie.asset(
                                  'assets/searchss.json',
                                  height: 120,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Icon(
                                      Icons.search_off_rounded,
                                      size: 60,
                                      color: Colors.grey[300],
                                    );
                                  },
                                ),
                                SizedBox(height: 16),
                                Text(
                                  'No receivers found',
                                  style: GoogleFonts.poppins(
                                    color: Colors.grey[600],
                                    fontSize: 16,
                                    fontWeight: FontWeight.normal,
                                  ),
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'Make sure devices are online and\nhave receiving mode enabled',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.poppins(
                                    color: Colors.grey[500],
                                    fontSize: 12,
                                  ),
                                ),
                                SizedBox(height: 20),
                                OutlinedButton.icon(
                                  onPressed: isScanning ? null : startScanning,
                                  icon: isScanning
                                      ? SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Color(0xFF4E6AF3),
                                          ),
                                        )
                                      : Icon(Icons.refresh_rounded),
                                  label: Text(isScanning ? 'Scanning...' : 'Scan Again'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Color(0xFF4E6AF3),
                                    side: BorderSide(color: Color(0xFF4E6AF3), width: 1.5),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            itemCount: _filteredReceivers.length,
                              itemBuilder: (context, index) {
                              final receiver = _filteredReceivers[index];
                              final isSelected = _selectedReceiverIndex == index;

                              return FadeInUp(
                                duration: Duration(milliseconds: 200 + (index * 50)),
                                child: Card(
                                  elevation: isSelected ? 4 : 1,
                                  margin: EdgeInsets.only(bottom: 8),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    side: BorderSide(
                                      color: isSelected
                                          ? Color(0xFF4E6AF3)
                                          : Colors.transparent,
                                      width: 2,
                                    ),
                                  ),
                                  color: isSelected
                                      ? Color(0xFF4E6AF3).withOpacity(0.05)
                                      : Colors.white,
                                  child: InkWell(
                                    onTap: () {
                                      setState(() {
                                        _selectedReceiverIndex = index;
                                      });
                                    },
                                    borderRadius: BorderRadius.circular(12),
                                    child: Padding(
                                      padding: EdgeInsets.all(12),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 44,
                                            height: 44,
                                            decoration: BoxDecoration(
                                              color: isSelected
                                                  ? Color(0xFF4E6AF3).withOpacity(0.2)
                                                  : Colors.grey.withOpacity(0.1),
                                              shape: BoxShape.circle,
                                              boxShadow: isSelected ? [
                                                BoxShadow(
                                                  color: Color(0xFF4E6AF3).withOpacity(0.2),
                                                  blurRadius: 6,
                                                  offset: Offset(0, 2),
                                                )
                                              ] : null,
                                            ),
                                            child: Icon(
                                              Icons.computer_rounded,
                                              color: isSelected
                                                  ? Color(0xFF4E6AF3)
                                                  : Colors.grey[600],
                                              size: 20,
                                            ),
                                          ),
                                          SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: Text(
                                                        receiver.name,
                                                        style: GoogleFonts.poppins(
                                                          fontWeight: FontWeight.bold,
                                                          color: isSelected
                                                              ? Color(0xFF4E6AF3)
                                                              : Colors.grey[800],
                                                          fontSize: 14,
                                                        ),
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ),
                                                    if (isSelected)
                                                      Container(
                                                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                        decoration: BoxDecoration(
                                                          color: Color(0xFF4E6AF3).withOpacity(0.1),
                                                          borderRadius: BorderRadius.circular(20),
                                                        ),
                                                        child: Text(
                                                          'Selected',
                                                          style: GoogleFonts.poppins(
                                                            color: Color(0xFF4E6AF3),
                                                            fontWeight: FontWeight.bold,
                                                            fontSize: 10,
                                                          ),
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                                SizedBox(height: 4),
                                                Row(
                                                  children: [
                                                    Icon(
                                                      Icons.wifi_rounded,
                                                      size: 12,
                                                      color: Colors.grey[500],
                                                    ),
                                                    SizedBox(width: 4),
                                                    Text(
                                                      receiver.ip,
                                                      style: GoogleFonts.poppins(
                                                        fontSize: 12,
                                                        color: Colors.grey[500],
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
                                ),
                              );
                            },
                          ),
                  ),
                  
                  // Bottom navigation
                  SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            setState(() {
                              _currentStep = 1; // Go back to file selection
                            });
                          },
                          icon: Icon(Icons.arrow_back_rounded),
                          label: Text('Back'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Color(0xFF4E6AF3),
                            padding: EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            side: BorderSide(color: Color(0xFF4E6AF3)),
                          ),
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: (_fileSelected &&
                                  _selectedReceiverIndex >= 0 &&
                                  _selectedReceiverIndex < _filteredReceivers.length &&
                                  !_isSending &&
                                  !_transferComplete &&
                                  !isConnecting)
                              ? () => connectToReceiver(
                                  _filteredReceivers[_selectedReceiverIndex].ip,
                                  _filteredReceivers[_selectedReceiverIndex].name)
                              : null,
                          icon: isConnecting
                              ? SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : Icon(Icons.send_rounded),
                          label: Text(
                            isConnecting ? 'Connecting...' : 'Send File',
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            foregroundColor: Colors.white,
                            backgroundColor: Color(0xFF4E6AF3),
                            padding: EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 2,
                            shadowColor: Color(0xFF4E6AF3).withOpacity(0.3),
                            disabledBackgroundColor: Colors.grey[300],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
  
  Widget _buildMobileTransfer() {
    return Column(
      children: [
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Transfer animation
                  if (!_transferComplete)
                    Lottie.asset(
                      'assets/file_transfer_animation.json',
                      height: 200,
                      repeat: true,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          height: 150,
                          width: 150,
                          decoration: BoxDecoration(
                            color: Color(0xFF4E6AF3).withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.send_rounded,
                            size: 80,
                            color: Color(0xFF4E6AF3),
                          ),
                        );
                      },
                    )
                  else
                    Lottie.asset(
                      'assets/transfer_complete_animation.json',
                      height: 200,
                      repeat: false,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          height: 150,
                          width: 150,
                          decoration: BoxDecoration(
                            color: Color(0xFF2AB673).withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.check_circle_rounded,
                            size: 80,
                            color: Color(0xFF2AB673),
                          ),
                        );
                      },
                    ),
                  SizedBox(height: 32),
                  
                  // File info card
                  Card(
                    elevation: 3,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Icon(
                                _getFileIconData(_fileType),
                                size: 40,
                                color: _getFileIconColor(_fileType),
                              ),
                              SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _fileName,
                                      style: GoogleFonts.poppins(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      '${_formatFileSize(_fileSize)} • ${_fileType.split('/').last.toUpperCase()}',
                                      style: GoogleFonts.poppins(
                                        color: Colors.grey[600],
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 20),
                          
                          // Transfer details
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Sending to',
                                      style: GoogleFonts.poppins(
                                        color: Colors.grey[600],
                                        fontSize: 12,
                                      ),
                                    ),
                                    SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.computer_rounded,
                                          size: 14,
                                          color: Color(0xFF4E6AF3),
                                        ),
                                        SizedBox(width: 6),
                                        Text(
                                          _receiverName ?? 'Device',
                                          style: GoogleFonts.poppins(
                                            fontWeight: FontWeight.bold,
                                            color: Colors.grey[800],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                height: 30,
                                width: 1,
                                color: Colors.grey[300],
                              ),
                              SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Status',
                                      style: GoogleFonts.poppins(
                                        color: Colors.grey[600],
                                        fontSize: 12,
                                      ),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      _transferComplete ? 'Complete' : 'Transferring...',
                                      style: GoogleFonts.poppins(
                                        fontWeight: FontWeight.bold,
                                        color: _transferComplete ? Color(0xFF2AB673) : Color(0xFF4E6AF3),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 24),
                          
                          // Progress
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Progress',
                                    style: GoogleFonts.poppins(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                  Text(
                                    '${(_progress * 100).toStringAsFixed(1)}%',
                                    style: GoogleFonts.poppins(
                                      fontWeight: FontWeight.bold,
                                      color: _transferComplete 
                                        ? Color(0xFF2AB673) 
                                        : Color(0xFF4E6AF3),
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 12),
                              Stack(
                                children: [
                                  // Background
                                  Container(
                                    height: 10,
                                    decoration: BoxDecoration(
                                      color: Colors.grey[200],
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                  // Progress
                                  AnimatedContainer(
                                    duration: Duration(milliseconds: 300),
                                    height: 10,
                                    width: MediaQuery.of(context).size.width * _progress * 0.65,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: _transferComplete
                                          ? [Color(0xFF2AB673), Color(0xFF1D9A62)]
                                          : [Color(0xFF4E6AF3), Color(0xFF3F58C7)],
                                        begin: Alignment.centerLeft,
                                        end: Alignment.centerRight,
                                      ),
                                      borderRadius: BorderRadius.circular(10),
                                      boxShadow: [
                                        BoxShadow(
                                          color: _transferComplete
                                            ? Color(0xFF2AB673).withOpacity(0.3)
                                            : Color(0xFF4E6AF3).withOpacity(0.3),
                                          blurRadius: 6,
                                          offset: Offset(0, 3),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          
                          SizedBox(height: 16),
                          
                          // Transfer date & time
                          Center(
                            child: Container(
                              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.grey[100],
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.access_time_rounded,
                                    size: 14,
                                    color: Colors.grey[600],
                                  ),
                                  SizedBox(width: 6),
                                  Text(
                                    '2025-05-15 16:57:45', // Use current timestamp
                                    style: GoogleFonts.poppins(
                                      fontSize: 12,
                                      color: Colors.grey[700],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        
        // Bottom buttons
        Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _transferComplete || !_isSending 
                      ? () {
                          setState(() {
                            _currentStep = 2; // Back to receiver selection
                          });
                        }
                      : null,
                  icon: Icon(Icons.arrow_back_rounded),
                  label: Text('Back'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Color(0xFF4E6AF3),
                    padding: EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    side: BorderSide(color: Color(0xFF4E6AF3)),
                  ),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: _transferComplete 
                      ? () {
                          setState(() {
                            _currentStep = 1; // Start over
                            _fileSelected = false;
                            _selectedFile = null;
                            _transferComplete = false;
                            _selectedReceiverIndex = -1;
                          });
                        }
                      : null,
                  icon: Icon(Icons.refresh_rounded),
                  label: Text(
                    'Send Another File',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: Color(0xFF2AB673),
                    padding: EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                    shadowColor: Color(0xFF2AB673).withOpacity(0.3),
                    disabledBackgroundColor: Colors.grey[300],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
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
  
  Widget _buildDesktopLayout(bool isMediumScreen) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Left side: File selection & info
        Expanded(
          flex: 3,
          child: FadeInLeft(
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
                    // Header with collapse button
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Color(0xFF4E6AF3).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Icons.file_present_rounded,
                                color: Color(0xFF4E6AF3),
                                size: 20,
                              ),
                            ),
                            SizedBox(width: 12),
                            Text(
                              _fileSelected ? 'Selected File' : 'Select File',
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                                color: Color(0xFF4E6AF3),
                              ),
                            ),
                          ],
                        ),
                        if (_fileSelected)
                          IconButton(
                            icon: Icon(
                              _showFileInfo ? Icons.expand_less : Icons.expand_more,
                              color: Colors.grey[600],
                            ),
                            onPressed: () {
                              setState(() {
                                _showFileInfo = !_showFileInfo;
                              });
                            },
                            tooltip: _showFileInfo ? 'Collapse' : 'Expand',
                          ),
                      ],
                    ),
                    SizedBox(height: 20),

                    // File area
                    Expanded(
                      child: _fileSelected
                          ? AnimatedCrossFade(
                              firstChild: _buildFilePreview(),
                              secondChild: Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(
                                      padding: EdgeInsets.all(20),
                                      decoration: BoxDecoration(
                                        color: _getFileIconColor(_fileType).withOpacity(0.1),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        _getFileIconData(_fileType),
                                        size: 40,
                                        color: _getFileIconColor(_fileType),
                                      ),
                                    ),
                                    SizedBox(height: 16),
                                    Text(
                                      _fileName,
                                      style: GoogleFonts.poppins(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    SizedBox(height: 8),
                                    Text(
                                      'Click to expand',
                                      style: GoogleFonts.poppins(
                                        color: Colors.grey[600],
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              crossFadeState: _showFileInfo
                                  ? CrossFadeState.showFirst
                                  : CrossFadeState.showSecond,
                              duration: Duration(milliseconds: 300),
                            )
                          : _buildFileDropArea(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        SizedBox(width: 20),

        // Right side: Receiver selection or transfer status
        Expanded(
          flex: isMediumScreen ? 2 : 2,
          child: FadeInRight(
            duration: Duration(milliseconds: 600),
            child: _currentStep == 3
                ? _buildTransferStatusCard()
                : Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header with collapse button
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Color(0xFF4E6AF3).withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(
                                      Icons.devices_rounded,
                                      color: Color(0xFF4E6AF3),
                                      size: 20,
                                    ),
                                  ),
                                  SizedBox(width: 12),
                                  Text(
                                    'Available Receivers',
                                    style: GoogleFonts.poppins(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                      color: Color(0xFF4E6AF3),
                                    ),
                                  ),
                                ],
                              ),
                              Row(
                                children: [
                                  if (isScanning)
                                    Container(
                                      margin: EdgeInsets.only(right: 8),
                                      child: SpinKitThreeBounce(
                                        color: Color(0xFF4E6AF3),
                                        size: 16,
                                      ),
                                    ),
                                  IconButton(
                                    icon: Icon(
                                      _showReceiverList ? Icons.expand_less : Icons.expand_more,
                                      color: Colors.grey[600],
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _showReceiverList = !_showReceiverList;
                                      });
                                    },
                                    tooltip: _showReceiverList ? 'Collapse' : 'Expand',
                                  ),
                                ],
                              ),
                            ],
                          ),
                          SizedBox(height: 20),

                          // Search box
                          _buildSearchBar(),
                          SizedBox(height: 16),

                          // Receiver list
                          Expanded(
                            child: AnimatedCrossFade(
                              firstChild: _filteredReceivers.isEmpty
                                  ? Center(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Lottie.asset(
                                            'assets/searchss.json',
                                            height: 150,
                                            errorBuilder: (context, error, stackTrace) {
                                              return Icon(
                                                Icons.search_off_rounded,
                                                size: 80,
                                                color: Colors.grey[300],
                                              );
                                            },
                                          ),
                                          SizedBox(height: 24),
                                          Text(
                                            'No receivers found',
                                            style: GoogleFonts.poppins(
                                              color: Colors.grey[700],
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          SizedBox(height: 8),
                                          Text(
                                            'Make sure devices are online and\nhave receiving mode enabled',
                                            textAlign: TextAlign.center,
                                            style: GoogleFonts.poppins(
                                              color: Colors.grey[600],
                                              fontSize: 14,
                                            ),
                                          ),
                                          SizedBox(height: 24),
                                          OutlinedButton.icon(
                                            onPressed: isScanning ? null : startScanning,
                                            icon: isScanning
                                                ? SizedBox(
                                                    width: 16,
                                                    height: 16,
                                                    child: CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      color: Color(0xFF4E6AF3),
                                                    ),
                                                  )
                                                : Icon(Icons.refresh_rounded),
                                            label: Text(isScanning ? 'Scanning...' : 'Scan Again'),
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: Color(0xFF4E6AF3),
                                              side: BorderSide(color: Color(0xFF4E6AF3), width: 1.5),
                                              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(10),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  : ListView.builder(
                                      itemCount: _filteredReceivers.length,
                                      itemBuilder: (context, index) {
                                        final receiver = _filteredReceivers[index];
                                        final isSelected = _selectedReceiverIndex == index;

                                        return FadeInUp(
                                          duration: Duration(milliseconds: 200 + (index * 50)),
                                          child: Card(
                                            elevation: isSelected ? 3 : 0,
                                            margin: EdgeInsets.only(bottom: 12),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(14),
                                              side: BorderSide(
                                                color: isSelected
                                                    ? Color(0xFF4E6AF3)
                                                    : Colors.transparent,
                                                width: 2,
                                              ),
                                            ),
                                            color: isSelected
                                                ? Color(0xFF4E6AF3).withOpacity(0.05)
                                                : Colors.white,
                                            child: InkWell(
                                              onTap: () {
                                                setState(() {
                                                  _selectedReceiverIndex = index;
                                                });
                                              },
                                              borderRadius: BorderRadius.circular(14),
                                              child: Padding(
                                                padding: EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                                                child: Row(
                                                  children: [
                                                    Container(
                                                      width: 50,
                                                      height: 50,
                                                      decoration: BoxDecoration(
                                                        color: isSelected
                                                            ? Color(0xFF4E6AF3).withOpacity(0.2)
                                                            : Colors.grey.withOpacity(0.1),
                                                        shape: BoxShape.circle,
                                                        boxShadow: isSelected ? [
                                                          BoxShadow(
                                                            color: Color(0xFF4E6AF3).withOpacity(0.2),
                                                            blurRadius: 8,
                                                            offset: Offset(0, 2),
                                                          )
                                                        ] : null,
                                                      ),
                                                      child: Center(
                                                        child: Icon(
                                                          isSelected ? Icons.check_rounded : Icons.computer_rounded,
                                                          color: isSelected
                                                              ? Color(0xFF4E6AF3)
                                                              : Colors.grey[700],
                                                          size: isSelected ? 28 : 24,
                                                        ),
                                                      ),
                                                    ),
                                                    SizedBox(width: 16),
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                        children: [
                                                          Text(
                                                            receiver.name,
                                                            style: GoogleFonts.poppins(
                                                              fontWeight: FontWeight.bold,
                                                              fontSize: 16,
                                                              color: isSelected
                                                                  ? Color(0xFF4E6AF3)
                                                                  : Colors.grey[800],
                                                            ),
                                                          ),
                                                          SizedBox(height: 4),
                                                          Row(
                                                            children: [
                                                              Icon(
                                                                Icons.wifi_rounded,
                                                                size: 14,
                                                                color: Colors.grey[500],
                                                              ),
                                                              SizedBox(width: 6),
                                                              Text(
                                                                receiver.ip,
                                                                style: GoogleFonts.poppins(
                                                                  fontSize: 13,
                                                                  color: Colors.grey[500],
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                    if (isSelected)
                                                      Container(
                                                        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                                        decoration: BoxDecoration(
                                                          color: Color(0xFF4E6AF3).withOpacity(0.1),
                                                          borderRadius: BorderRadius.circular(20),
                                                          border: Border.all(
                                                            color: Color(0xFF4E6AF3).withOpacity(0.3),
                                                            width: 1,
                                                          ),
                                                        ),
                                                        child: Text(
                                                          'Selected',
                                                          style: GoogleFonts.poppins(
                                                            fontSize: 12,
                                                            fontWeight: FontWeight.bold,
                                                            color: Color(0xFF4E6AF3),
                                                          ),
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                              secondChild: Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.devices_rounded,
                                      size: 48,
                                      color: Colors.grey[400],
                                    ),
                                    SizedBox(height: 16),
                                    Text(
                                      _selectedReceiverIndex >= 0 && _selectedReceiverIndex < _filteredReceivers.length
                                          ? 'Selected: ${_filteredReceivers[_selectedReceiverIndex].name}'
                                          : 'No device selected',
                                      style: GoogleFonts.poppins(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                        color: _selectedReceiverIndex >= 0 ? Color(0xFF4E6AF3) : Colors.grey[700],
                                      ),
                                    ),
                                    SizedBox(height: 8),
                                    Text(
                                      'Click to expand',
                                      style: GoogleFonts.poppins(
                                        color: Colors.grey[600],
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              crossFadeState: _showReceiverList
                                  ? CrossFadeState.showFirst
                                  : CrossFadeState.showSecond,
                              duration: Duration(milliseconds: 300),
                            ),
                          ),

                          SizedBox(height: 16),

                          // Refresh button and counter of available devices
                          Row(
                            children: [
                              Expanded(
                                child: Container(
                                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[100],
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    '${_filteredReceivers.length} device${_filteredReceivers.length != 1 ? 's' : ''} found',
                                    style: GoogleFonts.poppins(
                                      fontSize: 12,
                                      color: Colors.grey[700],
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                              SizedBox(width: 12),
                              ElevatedButton.icon(
                                onPressed: isScanning ? null : startScanning,
                                icon: isScanning 
                                    ? SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Color(0xFF4E6AF3),
                                        ),
                                      )
                                    : Icon(Icons.refresh_rounded),
                                label: Text(isScanning ? 'Scanning...' : 'Refresh'),
                                style: ElevatedButton.styleFrom(
                                  foregroundColor: Color(0xFF4E6AF3),
                                  backgroundColor: Color(0xFF4E6AF3).withOpacity(0.1),
                                  elevation: 0,
                                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  textStyle: GoogleFonts.poppins(
                                    fontWeight: FontWeight.normal,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
  
  Widget _buildTransferStatusCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _transferComplete 
                        ? Color(0xFF2AB673).withOpacity(0.1)
                        : Color(0xFF4E6AF3).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _transferComplete 
                        ? Icons.check_circle_rounded
                        : Icons.sync_rounded,
                    color: _transferComplete 
                        ? Color(0xFF2AB673)
                        : Color(0xFF4E6AF3),
                    size: 24,
                  ),
                ),
                SizedBox(width: 12),
                Text(
                  _transferComplete 
                      ? 'Transfer Complete'
                      : 'Transferring File',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    color: _transferComplete 
                        ? Color(0xFF2AB673)
                        : Color(0xFF4E6AF3),
                  ),
                ),
              ],
            ),
            
            SizedBox(height: 40),
            
            // Transfer animation
            if (!_transferComplete)
              Lottie.asset(
                'assets/file_transfer_animation.json',
                height: 200,
                repeat: true,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    height: 150,
                    width: 150,
                    decoration: BoxDecoration(
                      color: Color(0xFF4E6AF3).withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.send_rounded,
                      size: 80,
                      color: Color(0xFF4E6AF3),
                    ),
                  );
                },
              )
            else
              Lottie.asset(
                'assets/transfer_complete_animation.json',
                height: 200,
                repeat: false,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    height: 150,
                    width: 150,
                    decoration: BoxDecoration(
                      color: Color(0xFF2AB673).withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.check_circle_rounded,
                      size: 80,
                      color: Color(0xFF2AB673),
                    ),
                  );
                },
              ),
              
            SizedBox(height: 40),
            
            // Transfer details
            Container(
              padding: EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.grey[200]!,
                  width: 1,
                ),
              ),
              child: Column(
                children: [
                  // File details
                  Row(
                    children: [
                      Container(
                        padding: EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _getFileIconColor(_fileType).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          _getFileIconData(_fileType),
                          size: 24,
                          color: _getFileIconColor(_fileType),
                        ),
                      ),
                      SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _fileName,
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            SizedBox(height: 4),
                            Text(
                              '${_formatFileSize(_fileSize)} • ${_fileType.split('/').last.toUpperCase()}',
                              style: GoogleFonts.poppins(
                                color: Colors.grey[600],
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  
                  SizedBox(height: 20),
                  Divider(),
                  SizedBox(height: 20),
                  
                  // Transfer details in 2 columns
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Sender',
                              style: GoogleFonts.poppins(
                                color: Colors.grey[600],
                                fontSize: 12,
                              ),
                            ),
                            SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(
                                  Icons.person_rounded,
                                  size: 14,
                                  color: Color(0xFF4E6AF3),
                                ),
                                SizedBox(width: 6),
                                Text(
                                  'navin280123',
                                  style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey[800],
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Container(
                        height: 40,
                        width: 1,
                        color: Colors.grey[300],
                      ),
                      SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Receiver',
                              style: GoogleFonts.poppins(
                                color: Colors.grey[600],
                                fontSize: 12,
                              ),
                            ),
                            SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(
                                  Icons.computer_rounded,
                                  size: 14,
                                  color: Color(0xFF4E6AF3),
                                ),
                                SizedBox(width: 6),
                                Text(
                                  _receiverName ?? 'Device',
                                  style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey[800],
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  
                  SizedBox(height: 20),
                  
                  // Progress bar
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Progress',
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.normal,
                              fontSize: 14,
                              color: Colors.grey[700],
                            ),
                          ),
                          Text(
                            '${(_progress * 100).toStringAsFixed(1)}%',
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.bold,
                              color: _transferComplete 
                                ? Color(0xFF2AB673) 
                                : Color(0xFF4E6AF3),
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 12),
                      Stack(
                        children: [
                          // Background
                          Container(
                            height: 10,
                            decoration: BoxDecoration(
                              color: Colors.grey[200],
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          // Progress
                          AnimatedContainer(
                            duration: Duration(milliseconds: 300),
                            height: 10,
                            width: 350 * _progress,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: _transferComplete
                                  ? [Color(0xFF2AB673), Color(0xFF1D9A62)]
                                  : [Color(0xFF4E6AF3), Color(0xFF3F58C7)],
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                              ),
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: [
                                BoxShadow(
                                  color: _transferComplete
                                    ? Color(0xFF2AB673).withOpacity(0.3)
                                    : Color(0xFF4E6AF3).withOpacity(0.3),
                                  blurRadius: 6,
                                  offset: Offset(0, 3),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  
                  SizedBox(height: 20),
                  
                  // Time & date information
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.access_time_rounded,
                          size: 14,
                          color: Colors.grey[600],
                        ),
                        SizedBox(width: 6),
                        Text(
                          '2025-05-15 16:57:45', // Current time from the UTC timestamp
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: Colors.grey[700],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            SizedBox(height: 40),
            
            // Action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: _transferComplete || !_isSending 
                      ? () {
                          setState(() {
                            _currentStep = 2; // Back to receiver selection
                          });
                        }
                      : null,
                  icon: Icon(Icons.arrow_back_rounded),
                  label: Text('Back'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Color(0xFF4E6AF3),
                    padding: EdgeInsets.symmetric(vertical: 12, horizontal: 20),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    side: BorderSide(color: Color(0xFF4E6AF3)),
                  ),
                ),
                SizedBox(width: 16),
                ElevatedButton.icon(
                  onPressed: _transferComplete 
                      ? () {
                          setState(() {
                            _currentStep = 1; // Start over
                            _fileSelected = false;
                            _selectedFile = null;
                            _transferComplete = false;
                            _selectedReceiverIndex = -1;
                          });
                        }
                      : null,
                  icon: Icon(Icons.refresh_rounded),
                  label: Text(
                    'Send Another File',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: Color(0xFF2AB673),
                    padding: EdgeInsets.symmetric(vertical: 12, horizontal: 20),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 3,
                    shadowColor: Color(0xFF2AB673).withOpacity(0.3),
                    disabledBackgroundColor: Colors.grey[300],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class ReceiverDevice {
  final String name;
  final String ip;

  ReceiverDevice({required this.name, required this.ip});
}