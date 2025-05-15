import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:intl/intl.dart';
import 'package:open_file/open_file.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:animate_do/animate_do.dart';
import 'package:lottie/lottie.dart';

class ReceiveScreen extends StatefulWidget {
  @override
  _ReceiveScreenState createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends State<ReceiveScreen> with SingleTickerProviderStateMixin {
  ServerSocket? serverSocket;
  RawDatagramSocket? _discoverySocket;
  String receivedFileName = '';
  double progress = 0.0;
  String ipAddress = '';
  String computerName = '';
  int fileSize = 0;
  int bytesReceived = 0;
  File? receivedFile;
  bool isReceiving = false;
  List<Map<String, dynamic>> receivedFiles = [];
  String downloadDirectoryPath = '';
  bool isLoadingIp = true;
  bool isReceivingAnimation = false;
  
  // Animation controller
  late AnimationController _animationController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _getIpAddress();
    _getComputerName();
    _getDownloadsDirectory();
    
    // Initialize animation controller
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeInOut,
      ),
    );
    
    _animationController.repeat(reverse: true);
  }

  // Get the downloads directory
  void _getDownloadsDirectory() async {
    try {
      Directory? downloadsDirectory = await getDownloadsDirectory();
      String speedsharePath = '${downloadsDirectory!.path}/speedshare';
      Directory speedshareDirectory = Directory(speedsharePath);
      
      // Create the speedshare directory if it doesn't exist
      if (!await speedshareDirectory.exists()) {
        await speedshareDirectory.create(recursive: true);
      }
      
      setState(() {
        downloadDirectoryPath = speedsharePath;
      });
      
      // Load previously received files
      _loadReceivedFiles(speedshareDirectory);
    } catch (e) {
      print('Error getting downloads directory: $e');
    }
  }

  // Load previously received files from the directory
  void _loadReceivedFiles(Directory directory) async {
    try {
      List<FileSystemEntity> files = await directory.list().toList();
      files.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
      
      List<Map<String, dynamic>> filesList = [];
      
      for (var file in files) {
        if (file is File) {
          filesList.add({
            'name': p.basename(file.path),
            'path': file.path,
            'size': file.lengthSync(),
            'date': file.statSync().modified.toString(),
          });
        }
      }
      
      setState(() {
        receivedFiles = filesList;
      });
    } catch (e) {
      print('Error loading received files: $e');
    }
  }

  // Get the device's IP Address
  void _getIpAddress() async {
    setState(() {
      isLoadingIp = true;
    });
    
    try {
      for (var interface in await NetworkInterface.list()) {
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && 
              !addr.address.startsWith('127.') &&
              !addr.address.startsWith('0.')) {
            setState(() {
              ipAddress = addr.address;
              isLoadingIp = false;
            });
            return;
          }
        }
      }
    } catch (e) {
      print('Error getting IP address: $e');
    }
    
    setState(() {
      ipAddress = 'Not available';
      isLoadingIp = false;
    });
  }

  // Get computer/device name
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

  // Start receiving files
  void startReceiving() async {
    try {
      // Start the server socket for file transfers
      serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, 8080);
      
      // Set up discovery response
      _discoverySocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 8081);
      _discoverySocket!.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = _discoverySocket!.receive();
          if (datagram != null) {
            final message = utf8.decode(datagram.data);
            
            if (message == 'SPEEDSHARE_DISCOVERY') {
              // Send back device info
              final responseMessage = utf8.encode('SPEEDSHARE_RESPONSE:$computerName:READY');
              _discoverySocket!.send(responseMessage, datagram.address, datagram.port);
            }
          }
        }
      });
      
      setState(() {
        isReceiving = true;
        isReceivingAnimation = true;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle_rounded, color: Colors.white),
              SizedBox(width: 10),
              Text(
                'Ready to receive files',
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

      serverSocket!.listen((client) {
        // Protocol state variables
        bool receivingMetadata = true;
        bool receivingHeaderSize = true;
        int metadataSize = 0;
        List<int> headerBuffer = [];
        
        client.listen((data) async {
          if (receivingMetadata) {
            if (receivingHeaderSize) {
              // First 4 bytes indicate metadata size
              if (data.length >= 4) {
                ByteData byteData = ByteData.sublistView(Uint8List.fromList(data.sublist(0, 4)));
                metadataSize = byteData.getInt32(0);
                
                // Any remaining data is part of the metadata
                if (data.length > 4) {
                  headerBuffer.addAll(data.sublist(4));
                }
                
                receivingHeaderSize = false;
                
                // If we already have the complete metadata
                if (headerBuffer.length >= metadataSize) {
                  final metadataJson = utf8.decode(headerBuffer.sublist(0, metadataSize));
                  final metadata = json.decode(metadataJson) as Map<String, dynamic>;
                  
                  // Process metadata
                  receivedFileName = sanitizeFileName(p.basename(metadata['fileName']));
                  fileSize = metadata['fileSize'];
                  bytesReceived = 0;
                  
                  // Prepare for file data
                  receivedFile = File('$downloadDirectoryPath/$receivedFileName');
                  if (await receivedFile!.exists()) {
                    await receivedFile!.delete(); // Overwrite existing file
                  }
                  
                  // Switch to file data mode
                  receivingMetadata = false;
                  
                  // If there's more data beyond metadata, it's file content
                  if (headerBuffer.length > metadataSize) {
                    final fileData = headerBuffer.sublist(metadataSize);
                    receivedFile!.writeAsBytesSync(fileData, mode: FileMode.append);
                    bytesReceived += fileData.length;
                    
                    // Update progress
                    setState(() {
                      progress = bytesReceived / fileSize;
                    });
                  }
                }
              } else {
                // We received less than 4 bytes, keep accumulating
                headerBuffer.addAll(data);
              }
            } else {
              // We're collecting metadata bytes
              headerBuffer.addAll(data);
              
              if (headerBuffer.length >= metadataSize) {
                final metadataJson = utf8.decode(headerBuffer.sublist(0, metadataSize));
                final metadata = json.decode(metadataJson) as Map<String, dynamic>;
                
                // Process metadata
                receivedFileName = sanitizeFileName(p.basename(metadata['fileName']));
                fileSize = metadata['fileSize'];
                bytesReceived = 0;
                
                // Prepare for file data
                receivedFile = File('$downloadDirectoryPath/$receivedFileName');
                if (await receivedFile!.exists()) {
                  await receivedFile!.delete(); // Overwrite existing file
                }
                
                // Switch to file data mode
                receivingMetadata = false;
                
                // Send ready signal to sender
                client.write('READY_FOR_FILE_DATA');
                
                // If there's more data beyond metadata, it's file content
                if (headerBuffer.length > metadataSize) {
                  final fileData = headerBuffer.sublist(metadataSize);
                  receivedFile!.writeAsBytesSync(fileData, mode: FileMode.append);
                  bytesReceived += fileData.length;
                  
                  // Update progress
                  setState(() {
                    progress = bytesReceived / fileSize;
                  });
                }
              }
            }
          } else {
            // This is file data
            receivedFile!.writeAsBytesSync(data, mode: FileMode.append);
            bytesReceived += data.length;

            // Update progress
            setState(() {
              progress = bytesReceived / fileSize;
            });

            // File transfer complete
            if (bytesReceived >= fileSize) {
              // Add to received files list
              receivedFiles.insert(0, {
                'name': receivedFileName,
                'size': fileSize,
                'path': receivedFile!.path,
                'date': DateTime.now().toString(),
              });
              
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Row(
                    children: [
                      Icon(Icons.check_circle_rounded, color: Colors.white),
                      SizedBox(width: 10),
                      Text(
                        'File received: $receivedFileName',
                        style: GoogleFonts.poppins(),
                      ),
                    ],
                  ),
                  backgroundColor: Color(0xFF2AB673),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  margin: EdgeInsets.all(20),
                  action: SnackBarAction(
                    label: 'Open',
                    textColor: Colors.white,
                    onPressed: () {
                      _openFile(receivedFile!.path);
                    },
                  ),
                ),
              );
              
              // Send confirmation to the sender
              client.write('TRANSFER_COMPLETE');
              
              // Reset for next file
              receivedFile = null;
              receivingMetadata = true;
              receivingHeaderSize = true;
              headerBuffer = [];
              
              setState(() {
                receivedFileName = '';
                fileSize = 0;
                bytesReceived = 0;
                progress = 0.0;
              });
            }
          }
        });
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.error_rounded, color: Colors.white),
              SizedBox(width: 10),
              Text(
                'Error: $e',
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
      setState(() {
        isReceiving = false;
        isReceivingAnimation = false;
      });
    }
  }

  // Stop receiving files
  void stopReceiving() {
    serverSocket?.close();
    _discoverySocket?.close();
    
    setState(() {
      isReceiving = false;
      isReceivingAnimation = false;
      progress = 0.0;
      receivedFileName = '';
      fileSize = 0;
      bytesReceived = 0;
      receivedFile = null;
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.info_rounded, color: Colors.white),
            SizedBox(width: 10),
            Text(
              'Stopped receiving files',
              style: GoogleFonts.poppins(),
            ),
          ],
        ),
        backgroundColor: Colors.orange,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: EdgeInsets.all(20),
      ),
    );
  }

  // Open a received file
  void _openFile(String filePath) async {
    try {
      final result = await OpenFile.open(filePath);
      if (result.type != ResultType.done) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.error_rounded, color: Colors.white),
                SizedBox(width: 10),
                Text(
                  'Could not open file: ${result.message}',
                  style: GoogleFonts.poppins(),
                ),
              ],
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.error_rounded, color: Colors.white),
              SizedBox(width: 10),
              Text(
                'Error opening file: $e',
                style: GoogleFonts.poppins(),
              ),
            ],
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  // Open the download directory
  void _openDownloadsFolder() async {
    try {
      if (Platform.isWindows) {
        Process.run('explorer', [downloadDirectoryPath]);
      } else if (Platform.isMacOS) {
        Process.run('open', [downloadDirectoryPath]);
      } else if (Platform.isLinux) {
        Process.run('xdg-open', [downloadDirectoryPath]);
      } else {
        // For other platforms, at least copy the path
        await Clipboard.setData(ClipboardData(text: downloadDirectoryPath));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.info_rounded, color: Colors.white),
                SizedBox(width: 10),
                Text(
                  'Path copied to clipboard: $downloadDirectoryPath',
                  style: GoogleFonts.poppins(),
                ),
              ],
            ),
            backgroundColor: Color(0xFF4E6AF3),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.error_rounded, color: Colors.white),
              SizedBox(width: 10),
              Text(
                'Could not open folder: $e',
                style: GoogleFonts.poppins(),
              ),
            ],
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  // Copy IP address to clipboard
  void _copyIpToClipboard() async {
    await Clipboard.setData(ClipboardData(text: ipAddress));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.white),
            SizedBox(width: 10),
            Text(
              'IP address copied to clipboard',
              style: GoogleFonts.poppins(),
            ),
          ],
        ),
        backgroundColor: Color(0xFF4E6AF3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // Sanitize file names to remove invalid characters
  String sanitizeFileName(String fileName) {
    return fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String _formatDate(String dateString) {
    DateTime date = DateTime.parse(dateString);
    return DateFormat('dd MMM yyyy, HH:mm').format(date);
  }

  @override
  void dispose() {
    _animationController.dispose();
    serverSocket?.close();
    _discoverySocket?.close();
    super.dispose();
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
                        color: Color(0xFF2AB673).withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.download_rounded,
                        size: 24,
                        color: Color(0xFF2AB673),
                      ),
                    ),
                    SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Receive Files',
                          style: GoogleFonts.poppins(
                            fontSize: isSmallScreen ? 20 : 24,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF2AB673),
                          ),
                        ),
                        Text(
                          'Start receiving to allow others to send you files',
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
                child: isSmallScreen
                    ? _buildMobileLayout()
                    : _buildDesktopLayout(),
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
        // Device info and status
        FadeInLeft(
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
                    children: [
                      Container(
                        padding: EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Color(0xFF2AB673).withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.info_rounded,
                          color: Color(0xFF2AB673),
                          size: 20,
                        ),
                      ),
                      SizedBox(width: 12),
                      Text(
                        'Device Information',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2AB673),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 16),
                  
                  // Device info items
                  _buildInfoItem(
                    Icons.computer_rounded, 
                    'Device Name', 
                    computerName,
                    null,
                  ),
                  
                  SizedBox(height: 12),
                  
                  _buildInfoItem(
                    Icons.wifi_rounded, 
                    'IP Address', 
                    isLoadingIp ? 'Loading...' : ipAddress,
                    isLoadingIp ? null : _copyIpToClipboard,
                  ),
                  
                  SizedBox(height: 12),
                  
                  _buildInfoItem(
                    Icons.router_rounded, 
                    'Port', 
                    '8080',
                    null,
                  ),
                  
                  SizedBox(height: 12),
                  
                  // Status
                  Row(
                    children: [
                      Container(
                        padding: EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: (isReceiving ? Color(0xFF2AB673) : Colors.grey).withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: isReceivingAnimation && isReceiving
                            ? ScaleTransition(
                                scale: _pulseAnimation,
                                child: Container(
                                  width: 14,
                                  height: 14,
                                  decoration: BoxDecoration(
                                    color: Color(0xFF2AB673),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              )
                            : Icon(
                                isReceiving ? Icons.podcasts_rounded : Icons.pause_circle_filled_rounded,
                                color: isReceiving ? Color(0xFF2AB673) : Colors.grey,
                                size: 20,
                              ),
                      ),
                      SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Status',
                            style: GoogleFonts.poppins(
                              color: Colors.grey[600],
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            isReceiving ? 'Listening for files' : 'Not receiving',
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.bold,
                              color: isReceiving ? Color(0xFF2AB673) : Colors.grey[700],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  
                  SizedBox(height: 16),
                  
                  // Controls
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: isReceiving ? null : startReceiving,
                          icon: Icon(Icons.play_arrow_rounded),
                          label: Text('Start'),
                          style: ElevatedButton.styleFrom(
                            foregroundColor: Colors.white,
                            backgroundColor: Color(0xFF2AB673),
                            disabledBackgroundColor: Colors.grey[300],
                            padding: EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                            textStyle: GoogleFonts.poppins(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: isReceiving ? stopReceiving : null,
                          icon: Icon(Icons.stop_rounded),
                          label: Text('Stop'),
                          style: ElevatedButton.styleFrom(
                            foregroundColor: Colors.white,
                            backgroundColor: Colors.red[400],
                            disabledBackgroundColor: Colors.grey[300],
                            padding: EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                            textStyle: GoogleFonts.poppins(
                              fontWeight: FontWeight.bold,
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
        ),
        
        // Current transfer
        if (receivedFileName.isNotEmpty)
          FadeInUp(
            duration: Duration(milliseconds: 600),
            child: Container(
              margin: EdgeInsets.only(top: 16),
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
                        children: [
                          Container(
                            padding: EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Color(0xFF4E6AF3).withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.downloading_rounded,
                              color: Color(0xFF4E6AF3),
                              size: 20,
                            ),
                          ),
                          SizedBox(width: 12),
                          Text(
                            'Current Transfer',
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF4E6AF3),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 16),
                      
                      Row(
                        children: [
                          _getFileIcon(receivedFileName, 36),
                          SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  receivedFileName,
                                  style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                SizedBox(height: 4),
                                Text(
                                  '${_formatFileSize(bytesReceived)} of ${_formatFileSize(fileSize)}',
                                  style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      
                      SizedBox(height: 16),
                      
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: progress,
                          backgroundColor: Colors.grey[200],
                          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF4E6AF3)),
                          minHeight: 8,
                        ),
                      ),
                      
                      SizedBox(height: 8),
                      
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${(progress * 100).toStringAsFixed(1)}%',
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF4E6AF3),
                            ),
                          ),
                          Row(
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
                                'Receiving...',
                                style: GoogleFonts.poppins(
                                  fontStyle: FontStyle.italic,
                                  color: Color(0xFF4E6AF3),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          
        SizedBox(height: 16),
          
        // Received files
        Expanded(
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
                        Row(
                          children: [
                            Container(
                              padding: EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Color(0xFF4E6AF3).withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.folder_rounded,
                                color: Color(0xFF4E6AF3),
                                size: 20,
                              ),
                            ),
                            SizedBox(width: 12),
                            Text(
                              'Received Files',
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF4E6AF3),
                              ),
                            ),
                          ],
                        ),
                        if (receivedFiles.isNotEmpty)
                          IconButton(
                            icon: Icon(Icons.folder_open_rounded, color: Color(0xFF4E6AF3)),
                            onPressed: _openDownloadsFolder,
                            tooltip: 'Open Downloads Folder',
                            style: IconButton.styleFrom(
                              backgroundColor: Color(0xFF4E6AF3).withOpacity(0.1),
                              padding: EdgeInsets.all(8),
                            ),
                          ),
                      ],
                    ),
                    SizedBox(height: 12),
                    
                    // Files list
                    Expanded(
                      child: receivedFiles.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Lottie.asset(
                                    'assets/empty_folder_animation.json',
                                    height: 120,
                                  ),
                                  SizedBox(height: 16),
                                  Text(
                                    'No files received yet',
                                    style: GoogleFonts.poppins(
                                      color: Colors.grey[700],
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    'Files you receive will appear here',
                                    style: GoogleFonts.poppins(
                                      color: Colors.grey[500],
                                      fontSize: 14,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              itemCount: receivedFiles.length,
                              itemBuilder: (context, index) {
                                final file = receivedFiles[index];
                                final fileName = file['name'] as String;
                                
                                return FadeInUp(
                                  duration: Duration(milliseconds: 300 + (index * 50)),
                                  delay: Duration(milliseconds: 200),
                                  child: Card(
                                    elevation: 1,
                                    margin: EdgeInsets.only(bottom: 8),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: ListTile(
                                      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                      leading: _getFileIcon(fileName, 32),
                                      title: Text(
                                        fileName,
                                        style: GoogleFonts.poppins(
                                          fontWeight: FontWeight.normal,
                                          fontSize: 14,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      subtitle: Text(
                                        '${_formatFileSize(file['size'])} • ${_formatDate(file['date'])}',
                                        style: GoogleFonts.poppins(
                                          fontSize: 12,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: Icon(Icons.open_in_new_rounded, size: 20),
                                            onPressed: () {
                                              _openFile(file['path']);
                                            },
                                            tooltip: 'Open',
                                            style: IconButton.styleFrom(
                                              backgroundColor: Color(0xFF4E6AF3).withOpacity(0.1),
                                              foregroundColor: Color(0xFF4E6AF3),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
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
  
  Widget _buildDesktopLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Left side: Device info and status
        Expanded(
          flex: 2,
          child: Column(
            children: [
              // Device info card
              FadeInLeft(
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
                                color: Color(0xFF2AB673).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                Icons.info_rounded,
                                color: Color(0xFF2AB673),
                                size: 24,
                              ),
                            ),
                            SizedBox(width: 16),
                            Text(
                              'Device Information',
                              style: GoogleFonts.poppins(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF2AB673),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 24),
                        
                        // Computer name
                        _buildInfoItem(
                          Icons.computer_rounded, 
                          'Device Name', 
                          computerName,
                          null,
                          large: true,
                        ),
                        
                        SizedBox(height: 20),
                        
                        // IP Address
                        _buildInfoItem(
                          Icons.wifi_rounded, 
                          'IP Address', 
                          isLoadingIp ? 'Loading...' : ipAddress,
                          isLoadingIp ? null : _copyIpToClipboard,
                          large: true,
                        ),
                        
                        SizedBox(height: 20),
                        
                        // Port
                        _buildInfoItem(
                          Icons.router_rounded, 
                          'Port', 
                          '8080',
                          null,
                          large: true,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              
              SizedBox(height: 20),
              
              // Status card
              FadeInLeft(
                duration: Duration(milliseconds: 600),
                delay: Duration(milliseconds: 200),
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
                                color: Color(0xFF2AB673).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                Icons.sensors_rounded,
                                color: Color(0xFF2AB673),
                                size: 24,
                              ),
                            ),
                            SizedBox(width: 16),
                            Text(
                              'Status',
                              style: GoogleFonts.poppins(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF2AB673),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 24),
                        
                        // Status indicator
                        Row(
                          children: [
                            if (isReceivingAnimation && isReceiving)
                              ScaleTransition(
                                scale: _pulseAnimation,
                                child: Container(
                                  width: 20,
                                  height: 20,
                                  decoration: BoxDecoration(
                                    color: Color(0xFF2AB673),
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Color(0xFF2AB673).withOpacity(0.3),
                                        blurRadius: 10,
                                        spreadRadius: 2,
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            else
                              Container(
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(
                                  color: isReceiving ? Color(0xFF2AB673) : Colors.grey,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            SizedBox(width: 16),
                            Text(
                              isReceiving ? 'Listening for files' : 'Not receiving',
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: isReceiving ? Color(0xFF2AB673) : Colors.grey[700],
                              ),
                            ),
                          ],
                        ),
                        
                        SizedBox(height: 28),
                        
                        // Control buttons
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: isReceiving ? null : startReceiving,
                                icon: Icon(Icons.play_arrow_rounded),
                                label: Text('Start'),
                                style: ElevatedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  backgroundColor: Color(0xFF2AB673),
                                  disabledBackgroundColor: Colors.grey[300],
                                  padding: EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  elevation: 2,
                                  shadowColor: Color(0xFF2AB673).withOpacity(0.3),
                                  textStyle: GoogleFonts.poppins(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(width: 16),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: isReceiving ? stopReceiving : null,
                                icon: Icon(Icons.stop_rounded),
                                label: Text('Stop'),
                                style: ElevatedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  backgroundColor: Colors.red[400],
                                  disabledBackgroundColor: Colors.grey[300],
                                  padding: EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  elevation: 2,
                                  shadowColor: Colors.red.withOpacity(0.3),
                                  textStyle: GoogleFonts.poppins(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
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
              ),
              
              // Current transfer
              if (receivedFileName.isNotEmpty) 
                Expanded(
                  child: FadeInUp(
                    duration: Duration(milliseconds: 600),
                    child: Container(
                      margin: EdgeInsets.only(top: 20),
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
                                      Icons.downloading_rounded,
                                      color: Color(0xFF4E6AF3),
                                      size: 24,
                                    ),
                                  ),
                                  SizedBox(width: 16),
                                  Text(
                                    'Current Transfer',
                                    style: GoogleFonts.poppins(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF4E6AF3),
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 24),
                              
                              Row(
                                children: [
                                  _getFileIcon(receivedFileName, 48),
                                  SizedBox(width: 20),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          receivedFileName,
                                          style: GoogleFonts.poppins(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        SizedBox(height: 8),
                                        Text(
                                          '${_formatFileSize(bytesReceived)} of ${_formatFileSize(fileSize)}',
                                          style: GoogleFonts.poppins(
                                            fontSize: 14,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              
                              SizedBox(height: 24),
                              
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: LinearProgressIndicator(
                                  value: progress,
                                  backgroundColor: Colors.grey[200],
                                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF4E6AF3)),
                                  minHeight: 10,
                                ),
                              ),
                              
                              SizedBox(height: 12),
                              
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '${(progress * 100).toStringAsFixed(1)}%',
                                    style: GoogleFonts.poppins(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: Color(0xFF4E6AF3),
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF4E6AF3)),
                                        ),
                                      ),
                                      SizedBox(width: 8),
                                      Text(
                                        'Receiving...',
                                        style: GoogleFonts.poppins(
                                          fontStyle: FontStyle.italic,
                                          color: Color(0xFF4E6AF3),
                                          fontSize: 15,
                                        ),
                                      ),
                                    ],
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
            ],
          ),
        ),
        
        SizedBox(width: 20),
        
        // Right side: Received files history
        Expanded(
          flex: 3,
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
                              'Received Files',
                              style: GoogleFonts.poppins(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF4E6AF3),
                              ),
                            ),
                          ],
                        ),
                        if (receivedFiles.isNotEmpty)
                          ElevatedButton.icon(
                            onPressed: _openDownloadsFolder,
                            icon: Icon(Icons.folder_open_rounded),
                            label: Text('Open Folder'),
                            style: ElevatedButton.styleFrom(
                              foregroundColor: Color(0xFF4E6AF3),
                              backgroundColor: Color(0xFF4E6AF3).withOpacity(0.1),
                              elevation: 0,
                              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
                    SizedBox(height: 20),
                    
                    // Files list
                    Expanded(
                      child: receivedFiles.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Lottie.asset(
                                    'assets/empty_folder_animation.json',
                                    height: 180,
                                  ),
                                  SizedBox(height: 24),
                                  Text(
                                    'No files received yet',
                                    style: GoogleFonts.poppins(
                                      color: Colors.grey[700],
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  SizedBox(height: 12),
                                  Text(
                                    'Files you receive will appear here',
                                    style: GoogleFonts.poppins(
                                      color: Colors.grey[600],
                                      fontSize: 16,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              itemCount: receivedFiles.length,
                              itemBuilder: (context, index) {
                                final file = receivedFiles[index];
                                final fileName = file['name'] as String;
                                
                                return FadeInUp(
                                  duration: Duration(milliseconds: 300 + (index * 50)),
                                  delay: Duration(milliseconds: 100),
                                  child: Card(
                                    elevation: 1,
                                    margin: EdgeInsets.only(bottom: 12),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Padding(
                                      padding: EdgeInsets.all(16),
                                      child: Row(
                                        children: [
                                          _getFileIcon(fileName, 42),
                                          SizedBox(width: 20),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  fileName,
                                                  style: GoogleFonts.poppins(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 16,
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                                SizedBox(height: 4),
                                                Text(
                                                  '${_formatFileSize(file['size'])} • ${_formatDate(file['date'])}',
                                                  style: GoogleFonts.poppins(
                                                    fontSize: 13,
                                                    color: Colors.grey[600],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Row(
                                            children: [
                                              _buildActionButton(
                                                Icons.open_in_new_rounded, 
                                                'Open', 
                                                Color(0xFF4E6AF3),
                                                () => _openFile(file['path']),
                                              ),
                                              SizedBox(width: 8),
                                              _buildActionButton(
                                                Icons.folder_open_rounded, 
                                                'Show in folder', 
                                                Color(0xFF2AB673),
                                                _openDownloadsFolder,
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
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
  
  Widget _buildInfoItem(IconData icon, String label, String value, Function? onTap, {bool large = false}) {
    return Row(
      children: [
        Container(
          width: large ? 46 : 40,
          height: large ? 46 : 40,
          decoration: BoxDecoration(
            color: Color(0xFF2AB673).withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            color: Color(0xFF2AB673),
            size: large ? 22 : 20,
          ),
        ),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.poppins(
                  color: Colors.grey[600],
                  fontSize: large ? 13 : 12,
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      value,
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.bold,
                        fontSize: large ? 16 : 14,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (onTap != null)
                    InkWell(
                      onTap: () => onTap(),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Color(0xFF2AB673).withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Tooltip(
                          message: 'Copy to clipboard',
                          child: Icon(
                            Icons.copy_rounded,
                            size: 16,
                            color: Color(0xFF2AB673),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
  
  Widget _buildActionButton(IconData icon, String tooltip, Color color, VoidCallback onPressed) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: color,
              size: 22,
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _getFileIcon(String fileName, double size) {
    IconData iconData;
    Color iconColor;
    
    if (fileName.endsWith('.jpg') || 
        fileName.endsWith('.jpeg') || 
        fileName.endsWith('.png') || 
        fileName.endsWith('.gif')) {
      iconData = Icons.image_rounded;
      iconColor = Colors.blue;
    } else if (fileName.endsWith('.mp4') || 
              fileName.endsWith('.avi') || 
              fileName.endsWith('.mov')) {
      iconData = Icons.video_file_rounded;
      iconColor = Colors.red;
    } else if (fileName.endsWith('.mp3') || 
              fileName.endsWith('.wav') || 
              fileName.endsWith('.flac')) {
      iconData = Icons.audio_file_rounded;
      iconColor = Colors.purple;
    } else if (fileName.endsWith('.pdf')) {
      iconData = Icons.picture_as_pdf_rounded;
      iconColor = Colors.red;
    } else if (fileName.endsWith('.doc') || 
              fileName.endsWith('.docx') || 
              fileName.endsWith('.txt')) {
      iconData = Icons.description_rounded;
      iconColor = Colors.blue;
    } else if (fileName.endsWith('.xls') || 
              fileName.endsWith('.xlsx') || 
              fileName.endsWith('.csv')) {
      iconData = Icons.table_chart_rounded;
      iconColor = Color(0xFF2AB673);
    } else if (fileName.endsWith('.ppt') || 
              fileName.endsWith('.pptx')) {
      iconData = Icons.slideshow_rounded;
      iconColor = Colors.orange;
    } else if (fileName.endsWith('.zip') || 
              fileName.endsWith('.rar') || 
              fileName.endsWith('.7z')) {
      iconData = Icons.folder_zip_rounded;
      iconColor = Colors.amber;
    } else {
      iconData = Icons.insert_drive_file_rounded;
      iconColor = Colors.grey;
    }
    
    return Container(
      padding: EdgeInsets.all(size * 0.25),
      decoration: BoxDecoration(
        color: iconColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        iconData,
        color: iconColor,
        size: size * 0.7,
      ),
    );
  }
}