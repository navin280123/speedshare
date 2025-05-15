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

class FileSenderScreen extends StatefulWidget {
  @override
  _FileSenderScreenState createState() => _FileSenderScreenState();
}

class _FileSenderScreenState extends State<FileSenderScreen> with SingleTickerProviderStateMixin {
  // Animation controllers
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  
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

  @override
  void initState() {
    super.initState();
    
    // Initialize animation controller
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    
    _scaleAnimation = Tween<double>(begin: 0.95, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOut,
      ),
    );
    
    _controller.forward();
    
    // Start scanning for devices
    startScanning();

    // Set up periodic discovery
    _discoveryTimer = Timer.periodic(Duration(seconds: 30), (timer) {
      startScanning();
    });
  }

  void startScanning() {
    setState(() {
      isScanning = true;
    });

    // Use UDP discovery to find receivers
    discoverWithUDP();

    // Set a timeout to end scanning
    _scanTimer = Timer(Duration(seconds: 5), () {
      setState(() {
        isScanning = false;
      });
    });
  }

  void discoverWithUDP() async {
    try {
      setState(() {
        _isDiscovering = true;
        availableReceivers.clear();
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
                setState(() {
                  if (!availableReceivers.any((device) => device.ip == ipAddress)) {
                    availableReceivers.add(ReceiverDevice(
                      name: deviceName,
                      ip: ipAddress,
                    ));
                  }
                });
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
        if (availableReceivers.isEmpty) {
          checkDirectTCPConnections();
        } else {
          setState(() {
            _isDiscovering = false;
            isScanning = false;
          });
        }
      });
      
    } catch (e) {
      print('UDP discovery error: $e');
      
      // Fallback to direct TCP scanning
      checkDirectTCPConnections();
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
                checkReceiver('$prefix.$i');
              }
              checkReceiver('$prefix.100');
              checkReceiver('$prefix.101');
              checkReceiver('$prefix.102');
              checkReceiver('$prefix.255');
            }
          }
        }
      }
    } catch (e) {
      print('TCP discovery error: $e');
    } finally {
      setState(() {
        _isDiscovering = false;
        isScanning = false;
      });
    }
  }

  Future<void> checkReceiver(String ip) async {
    try {
      // Try to connect to the potential receiver with a short timeout
      final socket =
          await Socket.connect(ip, 8080, timeout: Duration(milliseconds: 500))
              .catchError((e) => null);

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

      if (deviceName != null && deviceName.isNotEmpty) {
        setState(() {
          // Add to list if not already present
          if (!availableReceivers.any((device) => device.ip == ip)) {
            availableReceivers.add(ReceiverDevice(
              name: deviceName,
              ip: ip,
            ));
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
          content: Text('Please select a file first'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: EdgeInsets.all(20),
        ),
      );
      return;
    }

    setState(() {
      isConnecting = true;
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

      setState(() {
        isConnecting = false;
        _receiverName = deviceName;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 10),
              Text('Connected to $deviceName'),
            ],
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: EdgeInsets.all(20),
        ),
      );

      // Set up listener for responses from receiver
      socket!.listen((data) {
        final message = utf8.decode(data);
        if (message == 'READY_FOR_FILE_DATA') {
          // Continue sending data if we were waiting for a ready signal
        } else if (message == 'TRANSFER_COMPLETE') {
          // Handle transfer completion
          setState(() {
            _isSending = false;
            _transferComplete = true;
            _progress = 1.0;
          });
        }
      }, onError: (error) {
        setState(() {
          _isSending = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connection error: $error'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }, onDone: () {
        if (_isSending && _progress < 1.0) {
          setState(() {
            _isSending = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Connection closed unexpectedly'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
        }
      });

      // Now send the file
      _sendFile();
    } catch (e) {
      setState(() {
        isConnecting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.error, color: Colors.white),
              SizedBox(width: 10),
              Text('Failed to connect: $e'),
            ],
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  void _pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();
    if (result != null) {
      _prepareFile(File(result.files.single.path!));
      
      // Play animation
      _controller.reset();
      _controller.forward();
    }
  }

  void _prepareFile(File file) {
    setState(() {
      _selectedFile = file;
      _fileName = file.path.split('/').last;
      _fileSize = file.lengthSync();
      _fileType = lookupMimeType(file.path) ?? 'application/octet-stream';
      _fileSelected = true;
      _transferComplete = false;
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

      // Use a buffer size of 4KB for better control and progress updates
      final int bufferSize = 4 * 1024; // 4KB
      int bytesSent = 0;

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

        setState(() {
          _progress = bytesSent / fileBytes.length;
        });

        // Small delay to allow UI to update and prevent network congestion
        await Future.delayed(Duration(milliseconds: 5));
      }

      // We don't immediately set _isSending to false or _transferComplete to true
      // Instead, we wait for the TRANSFER_COMPLETE message from the receiver

      // If we don't get the completion message within a timeout, consider it complete anyway
      Timer(Duration(seconds: 10), () {
        if (_isSending && _progress >= 0.99) {
          setState(() {
            _isSending = false;
            _transferComplete = true;
            _progress = 1.0;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white),
                  SizedBox(width: 10),
                  Text('File sent successfully!'),
                ],
              ),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
        }
      });
    } catch (e) {
      setState(() {
        _isSending = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.error, color: Colors.white),
              SizedBox(width: 10),
              Text('Error sending file: $e'),
            ],
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  Widget _buildFilePreview() {
    IconData iconData;
    Color iconColor;

    if (_fileType.startsWith('image/')) {
      iconData = Icons.image_rounded;
      iconColor = Colors.blue;
    } else if (_fileType.startsWith('video/')) {
      iconData = Icons.video_file_rounded;
      iconColor = Colors.red;
    } else if (_fileType.startsWith('audio/')) {
      iconData = Icons.audio_file_rounded;
      iconColor = Colors.purple;
    } else if (_fileType.contains('pdf')) {
      iconData = Icons.picture_as_pdf_rounded;
      iconColor = Colors.red;
    } else if (_fileType.contains('word') || _fileType.contains('document')) {
      iconData = Icons.description_rounded;
      iconColor = Colors.blue;
    } else if (_fileType.contains('excel') || _fileType.contains('sheet')) {
      iconData = Icons.table_chart_rounded;
      iconColor = Colors.green;
    } else if (_fileType.contains('presentation') ||
        _fileType.contains('powerpoint')) {
      iconData = Icons.slideshow_rounded;
      iconColor = Colors.orange;
    } else if (_fileType.contains('zip') || _fileType.contains('compressed')) {
      iconData = Icons.folder_zip_rounded;
      iconColor = Colors.amber;
    } else {
      iconData = Icons.insert_drive_file_rounded;
      iconColor = Colors.grey;
    }

    return ScaleTransition(
      scale: _scaleAnimation,
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: iconColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(iconData, size: 36, color: iconColor),
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
                  IconButton(
                    icon: Icon(Icons.close_rounded),
                    onPressed: () {
                      setState(() {
                        _fileSelected = false;
                        _selectedFile = null;
                        _transferComplete = false;
                      });
                    },
                    tooltip: 'Remove',
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.grey.withOpacity(0.1),
                    ),
                  ),
                ],
              ),
              if (_isSending || _transferComplete) ...[
                SizedBox(height: 20),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: _progress,
                    backgroundColor: Colors.grey[200],
                    valueColor: AlwaysStoppedAnimation<Color>(
                      _transferComplete ? Color(0xFF2AB673) : Color(0xFF4E6AF3),
                    ),
                    minHeight: 8,
                  ),
                ),
                SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${(_progress * 100).toStringAsFixed(1)}%',
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.bold,
                        color: _transferComplete ? Color(0xFF2AB673) : Color(0xFF4E6AF3),
                      ),
                    ),
                    AnimatedSwitcher(
                      duration: Duration(milliseconds: 300),
                      child: _transferComplete
                          ? Row(
                              key: ValueKey('complete'),
                              children: [
                                Icon(Icons.check_circle, color: Color(0xFF2AB673), size: 16),
                                SizedBox(width: 4),
                                Text(
                                  'Complete',
                                  style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF2AB673),
                                  ),
                                ),
                              ],
                            )
                          : Row(
                              key: ValueKey('sending'),
                              children: [
                                SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF4E6AF3)),
                                  ),
                                ),
                                SizedBox(width: 6),
                                Text(
                                  'Sending...',
                                  style: GoogleFonts.poppins(
                                    fontStyle: FontStyle.italic,
                                    color: Color(0xFF4E6AF3),
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
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
          
          // Play animation
          _controller.reset();
          _controller.forward();
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
          borderRadius: BorderRadius.circular(16),
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
                Lottie.asset(
                  'assets/file_upload_animation.json',
                  height: 120,
                  animate: _isHovering,
                ),
                SizedBox(height: 16),
                Text(
                  _isHovering ? 'Release to Upload' : 'Drop Files Here',
                  style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: _isHovering ? Color(0xFF4E6AF3) : Colors.grey[700],
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'or',
                  style: GoogleFonts.poppins(
                    color: Colors.grey[600],
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
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Get screen size for responsive design
    final Size screenSize = MediaQuery.of(context).size;
    final bool isSmallScreen = screenSize.width < 1000;
    final bool isMediumScreen = screenSize.width >= 1000 && screenSize.width < 1400;
    
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
                          'Select files and a receiver to start sending',
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

              // Main content area
              Expanded(
                child: isSmallScreen
                    ? _buildMobileLayout()
                    : _buildDesktopLayout(isMediumScreen),
              ),

              // Bottom section: Send button
              SizedBox(height: 16),
              FadeInUp(
                duration: Duration(milliseconds: 500),
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
        ),
      ),
    );
  }
  
  Widget _buildMobileLayout() {
    return Column(
      children: [
        // File section
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
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Selected File',
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Color(0xFF4E6AF3),
                      ),
                    ),
                    SizedBox(height: 12),

                    // File area
                    Expanded(
                      child: _fileSelected
                          ? _buildFilePreview()
                          : _buildFileDropArea(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        SizedBox(height: 16),

        // Receiver section
        Expanded(
          flex: 4,
          child: FadeInRight(
            duration: Duration(milliseconds: 600),
            child: Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Available Receivers',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Color(0xFF4E6AF3),
                          ),
                        ),
                        if (isScanning)
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF4E6AF3)),
                            ),
                          ),
                      ],
                    ),
                    SizedBox(height: 12),

                    // Receiver list
                    Expanded(
                      child: availableReceivers.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Lottie.asset(
                                    'assets/searching_animation.json',
                                    height: 120,
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
                                ],
                              ),
                            )
                          : ListView.builder(
                              itemCount: availableReceivers.length,
                              itemBuilder: (context, index) {
                                final receiver = availableReceivers[index];
                                final isSelected = _selectedReceiverIndex == index;

                                return FadeInUp(
                                  duration: Duration(milliseconds: 200 + (index * 50)),
                                  child: Card(
                                    elevation: isSelected ? 4 : 0,
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
                                        : null,
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
                                              ),
                                              child: Icon(
                                                Icons.computer_rounded,
                                                color: isSelected
                                                    ? Color(0xFF4E6AF3)
                                                    : Colors.grey[700],
                                              ),
                                            ),
                                            SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    receiver.name,
                                                    style: GoogleFonts.poppins(
                                                      fontWeight: FontWeight.bold,
                                                      color: isSelected
                                                          ? Color(0xFF4E6AF3)
                                                          : Colors.grey[900],
                                                    ),
                                                  ),
                                                  SizedBox(height: 4),
                                                  Text(
                                                    receiver.ip,
                                                    style: GoogleFonts.poppins(
                                                      fontSize: 12,
                                                      color: Colors.grey[600],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            AnimatedOpacity(
                                              opacity: isSelected ? 1.0 : 0.0,
                                              duration: Duration(milliseconds: 200),
                                              child: Icon(
                                                Icons.check_circle_rounded,
                                                color: Color(0xFF4E6AF3),
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

                    SizedBox(height: 12),

                    // Refresh button
                    ElevatedButton.icon(
                      onPressed: isScanning ? null : startScanning,
                      icon: Icon(Icons.refresh_rounded),
                      label: Text('Refresh'),
                      style: ElevatedButton.styleFrom(
                        foregroundColor: Color(0xFF4E6AF3),
                        backgroundColor: Color(0xFF4E6AF3).withOpacity(0.1),
                        elevation: 0,
                        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        disabledForegroundColor: Colors.grey.withOpacity(0.4),
                        disabledBackgroundColor: Colors.grey.withOpacity(0.1),
                      ),
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
  
  Widget _buildDesktopLayout(bool isMediumScreen) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Left side: File selection
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
                    Text(
                      'Selected File',
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: Color(0xFF4E6AF3),
                      ),
                    ),
                    SizedBox(height: 20),

                    // File area
                    Expanded(
                      child: _fileSelected
                          ? _buildFilePreview()
                          : _buildFileDropArea(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        SizedBox(width: 20),

        // Right side: Receiver selection
        Expanded(
          flex: isMediumScreen ? 2 : 2,
          child: FadeInRight(
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
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Available Receivers',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: Color(0xFF4E6AF3),
                          ),
                        ),
                        if (isScanning)
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF4E6AF3)),
                            ),
                          ),
                      ],
                    ),
                    SizedBox(height: 20),

                    // Receiver list
                    Expanded(
                      child: availableReceivers.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Lottie.asset(
                                    'assets/searching_animation.json',
                                    height: 150,
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
                                ],
                              ),
                            )
                          : ListView.builder(
                              itemCount: availableReceivers.length,
                              itemBuilder: (context, index) {
                                final receiver = availableReceivers[index];
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
                                        padding: EdgeInsets.all(16),
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
                                              child: Icon(
                                                Icons.computer_rounded,
                                                color: isSelected
                                                    ? Color(0xFF4E6AF3)
                                                    : Colors.grey[700],
                                                size: 24,
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
                                                          : Colors.grey[900],
                                                    ),
                                                  ),
                                                  SizedBox(height: 4),
                                                  Text(
                                                    receiver.ip,
                                                    style: GoogleFonts.poppins(
                                                      fontSize: 13,
                                                      color: Colors.grey[600],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            AnimatedContainer(
                                              duration: Duration(milliseconds: 200),
                                              padding: EdgeInsets.all(isSelected ? 8 : 0),
                                              decoration: BoxDecoration(
                                                color: isSelected ? Color(0xFF4E6AF3).withOpacity(0.1) : Colors.transparent,
                                                shape: BoxShape.circle,
                                              ),
                                              child: AnimatedOpacity(
                                                opacity: isSelected ? 1.0 : 0.0,
                                                duration: Duration(milliseconds: 200),
                                                child: Icon(
                                                  Icons.check_circle_rounded,
                                                  color: Color(0xFF4E6AF3),
                                                  size: 24,
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
                    ),

                    SizedBox(height: 16),

                    // Refresh button
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
                        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
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
              ),
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