import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:intl/intl.dart';
import 'package:open_file/open_file.dart';
import 'package:url_launcher/url_launcher.dart';

class ReceiveScreen extends StatefulWidget {
  @override
  _ReceiveScreenState createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends State<ReceiveScreen> {
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

  @override
  void initState() {
    super.initState();
    _getIpAddress();
    _getComputerName();
    _getDownloadsDirectory();
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
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ready to receive files'),
          backgroundColor: Colors.green,
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
                  content: Text('File received: $receivedFileName'),
                  backgroundColor: Colors.green,
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
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
      setState(() {
        isReceiving = false;
      });
    }
  }

  // Stop receiving files
  void stopReceiving() {
    serverSocket?.close();
    _discoverySocket?.close();
    
    setState(() {
      isReceiving = false;
      progress = 0.0;
      receivedFileName = '';
      fileSize = 0;
      bytesReceived = 0;
      receivedFile = null;
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Stopped receiving files'),
        backgroundColor: Colors.orange,
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
            content: Text('Could not open file: ${result.message}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error opening file: $e'),
          backgroundColor: Colors.red,
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
            content: Text('Path copied to clipboard: $downloadDirectoryPath'),
            backgroundColor: Colors.blue,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not open folder: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Copy IP address to clipboard
  void _copyIpToClipboard() async {
    await Clipboard.setData(ClipboardData(text: ipAddress));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('IP address copied to clipboard'),
        backgroundColor: Colors.blue,
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
    serverSocket?.close();
    _discoverySocket?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.grey[50],
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header section
          Text(
            'Receive Files',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.green,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Start receiving to allow others to send you files',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 14,
            ),
          ),
          SizedBox(height: 24),
          
          // Main content
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Left side: Device info and status
                Expanded(
                  flex: 2,
                  child: Column(
                    children: [
                      // Device info card
                      Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Device Information',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                ),
                              ),
                              SizedBox(height: 16),
                              
                              // Computer name
                              Row(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: Colors.green.withOpacity(0.1),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.computer,
                                      color: Colors.green,
                                    ),
                                  ),
                                  SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Device Name',
                                          style: TextStyle(
                                            color: Colors.grey[600],
                                            fontSize: 12,
                                          ),
                                        ),
                                        Text(
                                          computerName,
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              
                              SizedBox(height: 16),
                              
                              // IP Address
                              Row(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: Colors.green.withOpacity(0.1),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.wifi,
                                      color: Colors.green,
                                    ),
                                  ),
                                  SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'IP Address',
                                          style: TextStyle(
                                            color: Colors.grey[600],
                                            fontSize: 12,
                                          ),
                                        ),
                                        Row(
                                          children: [
                                            isLoadingIp 
                                                ? SizedBox(
                                                    width: 14,
                                                    height: 14,
                                                    child: CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
                                                    ),
                                                  )
                                                : Text(
                                                    ipAddress,
                                                    style: TextStyle(
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                            SizedBox(width: 8),
                                            if (!isLoadingIp)
                                              InkWell(
                                                onTap: _copyIpToClipboard,
                                                child: Tooltip(
                                                  message: 'Copy IP Address',
                                                  child: Icon(
                                                    Icons.copy,
                                                    size: 16,
                                                    color: Colors.grey[600],
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
                              
                              SizedBox(height: 16),
                              
                              // Port
                              Row(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: Colors.green.withOpacity(0.1),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.router,
                                      color: Colors.green,
                                    ),
                                  ),
                                  SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Port',
                                          style: TextStyle(
                                            color: Colors.grey[600],
                                            fontSize: 12,
                                          ),
                                        ),
                                        Text(
                                          '8080',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
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
                      
                      SizedBox(height: 16),
                      
                      // Status card
                      Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Status',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                ),
                              ),
                              SizedBox(height: 16),
                              
                              // Status indicator
                              Row(
                                children: [
                                  Container(
                                    width: 16,
                                    height: 16,
                                    decoration: BoxDecoration(
                                      color: isReceiving ? Colors.green : Colors.grey,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  SizedBox(width: 12),
                                  Text(
                                    isReceiving ? 'Listening for files' : 'Not receiving',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: isReceiving ? Colors.green : Colors.grey[700],
                                    ),
                                  ),
                                ],
                              ),
                              
                              SizedBox(height: 24),
                              
                              // Control buttons
                              Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: isReceiving ? null : startReceiving,
                                      icon: Icon(Icons.play_arrow),
                                      label: Text('Start'),
                                      style: ElevatedButton.styleFrom(
                                        foregroundColor: Colors.white,
                                        backgroundColor: Colors.green,
                                        padding: EdgeInsets.symmetric(vertical: 12),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: isReceiving ? stopReceiving : null,
                                      icon: Icon(Icons.stop),
                                      label: Text('Stop'),
                                      style: ElevatedButton.styleFrom(
                                        foregroundColor: Colors.white,
                                        backgroundColor: Colors.red,
                                        padding: EdgeInsets.symmetric(vertical: 12),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(8),
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
                      
                      // Current transfer
                      if (receivedFileName.isNotEmpty) 
                        Expanded(
                          child: Card(
                            elevation: 2,
                            margin: EdgeInsets.only(top: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Padding(
                              padding: EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Current Transfer',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green,
                                    ),
                                  ),
                                  SizedBox(height: 16),
                                  
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.insert_drive_file,
                                        size: 40,
                                        color: Colors.blue,
                                      ),
                                      SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              receivedFileName,
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            SizedBox(height: 8),
                                            Text(
                                              '${_formatFileSize(bytesReceived)} of ${_formatFileSize(fileSize)}',
                                              style: TextStyle(
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
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
                                      minHeight: 8,
                                    ),
                                  ),
                                  
                                  SizedBox(height: 8),
                                  
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        '${(progress * 100).toStringAsFixed(1)}%',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.green,
                                        ),
                                      ),
                                      Text(
                                        'Receiving...',
                                        style: TextStyle(
                                          fontStyle: FontStyle.italic,
                                          color: Colors.green,
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
                  ),
                ),
                
                SizedBox(width: 16),
                
                // Right side: Received files history
                Expanded(
                  flex: 3,
                  child: Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Received Files',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                          SizedBox(height: 16),
                          
                          // Files list
                          Expanded(
                            child: receivedFiles.isEmpty
                                ? Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.inbox,
                                          size: 64,
                                          color: Colors.grey[400],
                                        ),
                                        SizedBox(height: 16),
                                        Text(
                                          'No files received yet',
                                          style: TextStyle(
                                            color: Colors.grey[600],
                                            fontSize: 16,
                                          ),
                                        ),
                                        SizedBox(height: 8),
                                        Text(
                                          'Files you receive will appear here',
                                          style: TextStyle(
                                            color: Colors.grey[500],
                                            fontSize: 14,
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
                                      
                                      IconData iconData;
                                      Color iconColor;
                                      
                                      if (fileName.endsWith('.jpg') || 
                                          fileName.endsWith('.jpeg') || 
                                          fileName.endsWith('.png') || 
                                          fileName.endsWith('.gif')) {
                                        iconData = Icons.image;
                                        iconColor = Colors.blue;
                                      } else if (fileName.endsWith('.mp4') || 
                                                fileName.endsWith('.avi') || 
                                                fileName.endsWith('.mov')) {
                                        iconData = Icons.video_file;
                                        iconColor = Colors.red;
                                      } else if (fileName.endsWith('.mp3') || 
                                                fileName.endsWith('.wav') || 
                                                fileName.endsWith('.flac')) {
                                        iconData = Icons.audio_file;
                                        iconColor = Colors.purple;
                                      } else if (fileName.endsWith('.pdf')) {
                                        iconData = Icons.picture_as_pdf;
                                        iconColor = Colors.red;
                                      } else if (fileName.endsWith('.doc') || 
                                                fileName.endsWith('.docx') || 
                                                fileName.endsWith('.txt')) {
                                        iconData = Icons.description;
                                        iconColor = Colors.blue;
                                      } else if (fileName.endsWith('.xls') || 
                                                fileName.endsWith('.xlsx') || 
                                                fileName.endsWith('.csv')) {
                                        iconData = Icons.table_chart;
                                        iconColor = Colors.green;
                                      } else if (fileName.endsWith('.ppt') || 
                                                fileName.endsWith('.pptx')) {
                                        iconData = Icons.slideshow;
                                        iconColor = Colors.orange;
                                      } else if (fileName.endsWith('.zip') || 
                                                fileName.endsWith('.rar') || 
                                                fileName.endsWith('.7z')) {
                                        iconData = Icons.folder_zip;
                                        iconColor = Colors.amber;
                                      } else {
                                        iconData = Icons.insert_drive_file;
                                        iconColor = Colors.grey;
                                      }
                                      
                                      return Card(
                                        elevation: 1,
                                        margin: EdgeInsets.only(bottom: 8),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: ListTile(
                                          leading: Icon(
                                            iconData,
                                            color: iconColor,
                                            size: 32,
                                          ),
                                          title: Text(
                                            fileName,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          subtitle: Text(
                                            '${_formatFileSize(file['size'])} • ${_formatDate(file['date'])}',
                                            style: TextStyle(
                                              fontSize: 12,
                                            ),
                                          ),
                                          trailing: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              IconButton(
                                                icon: Icon(Icons.open_in_new, size: 20),
                                                onPressed: () {
                                                  _openFile(file['path']);
                                                },
                                                tooltip: 'Open',
                                              ),
                                              IconButton(
                                                icon: Icon(Icons.folder, size: 20),
                                                onPressed: () {
                                                  _openDownloadsFolder();
                                                },
                                                tooltip: 'Show in folder',
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                          ),
                          
                          // Open folder button
                          if (receivedFiles.isNotEmpty) 
                            Padding(
                              padding: EdgeInsets.only(top: 16),
                              child: ElevatedButton.icon(
                                onPressed: _openDownloadsFolder,
                                icon: Icon(Icons.folder_open),
                                label: Text('Open Downloads Folder'),
                                style: ElevatedButton.styleFrom(
                                  foregroundColor: Colors.green,
                                  backgroundColor: Colors.green.withOpacity(0.1),
                                  elevation: 0,
                                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}