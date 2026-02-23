import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:intl/intl.dart';
import 'package:open_file/open_file.dart';
import 'package:lottie/lottie.dart';
import 'package:speedshare/main.dart';

class ReceiveScreen extends StatefulWidget {
  @override
  _ReceiveScreenState createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends State<ReceiveScreen>
    with SingleTickerProviderStateMixin {
  // Constants
  static const int SERVER_PORT = 8080;
  static const int DISCOVERY_PORT = 8081;
  static const int MAX_FILE_SIZE =
      10 * 1024 * 1024 * 1024; // 10GB receive limit

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

  // Dynamic values instead of hardcoded
  String get currentDateTime =>
      DateFormat('dd MMM yyyy, HH:mm').format(DateTime.now());
  String get userLogin => Platform.localHostname;

  @override
  void initState() {
    super.initState();
    _getIpAddress();
    _getComputerName();
    _getDownloadsDirectory();

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

  void _getDownloadsDirectory() async {
    try {
      Directory? downloadsDirectory = await getDownloadsDirectory();
      String speedsharePath = '${downloadsDirectory!.path}/speedshare';
      Directory speedshareDirectory = Directory(speedsharePath);
      if (!await speedshareDirectory.exists()) {
        await speedshareDirectory.create(recursive: true);
      }
      setState(() {
        downloadDirectoryPath = speedsharePath;
      });
      _loadReceivedFiles(speedshareDirectory);
    } catch (e) {
      print('Error getting downloads directory: $e');
      _showSnackBar(
        'Error accessing downloads directory: $e',
        Icons.error_rounded,
        Colors.red,
      );
    }
  }

  void _loadReceivedFiles(Directory directory) async {
    try {
      List<FileSystemEntity> files = await directory.list().toList();
      files.sort(
          (a, b) => b.statSync().modified.compareTo(a.statSync().modified));
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

  void _getComputerName() async {
    try {
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

  void startReceiving() async {
    try {
      // Close existing sockets if any
      await serverSocket?.close();
      _discoverySocket?.close();

      serverSocket =
          await ServerSocket.bind(InternetAddress.anyIPv4, SERVER_PORT);

      // FIXED: UDP discovery response protocol - matches sender expectation
      _discoverySocket =
          await RawDatagramSocket.bind(InternetAddress.anyIPv4, DISCOVERY_PORT);
      _discoverySocket!.broadcastEnabled = true;
      _discoverySocket!.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = _discoverySocket!.receive();
          if (datagram != null) {
            final message = utf8.decode(datagram.data);
            if (message == 'SPEEDSHARE_DISCOVERY') {
              // FIXED: Send response in format sender expects: "SPEEDSHARE_RESPONSE:deviceName:"
              final responseMessage =
                  utf8.encode('SPEEDSHARE_RESPONSE:$computerName:');
              _discoverySocket!
                  .send(responseMessage, datagram.address, datagram.port);
            }
          }
        }
      }, onError: (error) {
        print('UDP Discovery stream error: $error');
      });

      setState(() {
        isReceiving = true;
        isReceivingAnimation = true;
      });

      _showSnackBar(
        'Ready to receive files on port $SERVER_PORT',
        Icons.check_circle_rounded,
        Color(0xFF2AB673),
      );

      serverSocket!.listen((client) {
        _handleClientConnection(client);
      });
    } catch (e) {
      _showSnackBar(
        'Error starting receiver: $e',
        Icons.error_rounded,
        Colors.red,
      );
      setState(() {
        isReceiving = false;
        isReceivingAnimation = false;
      });
    }
  }

  void _handleClientConnection(Socket client) {
    // Protocol state variables
    bool receivingMetadata = true;
    bool receivingHeaderSize = true;
    int metadataSize = 0;
    List<int> headerBuffer = [];
    int expectedFileSize = 0;
    String expectedFileName = '';
    File? fileForWrite;
    int writtenFileBytes = 0;

    client.listen((data) async {
      try {
        if (receivingMetadata) {
          if (receivingHeaderSize) {
            // First 4 bytes indicate metadata size
            if (data.length >= 4) {
              ByteData byteData =
                  ByteData.sublistView(Uint8List.fromList(data.sublist(0, 4)));
              metadataSize = byteData.getInt32(0);
              if (data.length > 4) {
                headerBuffer.addAll(data.sublist(4));
              }
              receivingHeaderSize = false;
              if (headerBuffer.length >= metadataSize) {
                final metadataResult =
                    await _processMetadata(headerBuffer, metadataSize);
                expectedFileName = metadataResult['fileName']!;
                expectedFileSize = metadataResult['fileSize']!;
                receivingMetadata = false;
                fileForWrite = File('$downloadDirectoryPath/$expectedFileName');
                if (await fileForWrite!.exists()) {
                  await fileForWrite!.delete();
                }
                client.write('READY_FOR_FILE_DATA');
                if (headerBuffer.length > metadataSize) {
                  final fileData = headerBuffer.sublist(metadataSize);
                  await _writeFileData(fileForWrite!, fileData);
                  writtenFileBytes += fileData.length;
                  _updateProgress(writtenFileBytes, expectedFileSize);
                }
              }
            } else {
              headerBuffer.addAll(data);
            }
          } else {
            headerBuffer.addAll(data);
            if (headerBuffer.length >= metadataSize) {
              final metadataResult =
                  await _processMetadata(headerBuffer, metadataSize);
              expectedFileName = metadataResult['fileName']!;
              expectedFileSize = metadataResult['fileSize']!;
              receivingMetadata = false;
              fileForWrite = File('$downloadDirectoryPath/$expectedFileName');
              if (await fileForWrite!.exists()) {
                await fileForWrite!.delete();
              }
              client.write('READY_FOR_FILE_DATA');
              if (headerBuffer.length > metadataSize) {
                final fileData = headerBuffer.sublist(metadataSize);
                await _writeFileData(fileForWrite!, fileData);
                writtenFileBytes += fileData.length;
                _updateProgress(writtenFileBytes, expectedFileSize);
              }
            }
          }
        } else {
          // This is file data - write incrementally to avoid memory issues
          await _writeFileData(fileForWrite!, data);
          writtenFileBytes += data.length;
          _updateProgress(writtenFileBytes, expectedFileSize);

          // File transfer complete
          if (writtenFileBytes >= expectedFileSize) {
            await _completeFileTransfer(
                fileForWrite!, expectedFileName, expectedFileSize, client);

            // Reset for next file
            receivingMetadata = true;
            receivingHeaderSize = true;
            headerBuffer = [];
            writtenFileBytes = 0;
          }
        }
      } catch (e) {
        _showSnackBar(
          'Error receiving file: $e',
          Icons.error_rounded,
          Colors.red,
        );
        client.close();
      }
    }, onError: (error) {
      _showSnackBar(
        'Connection error: $error',
        Icons.error_rounded,
        Colors.red,
      );
    }, onDone: () {
      if (mounted) {
        setState(() {
          receivedFileName = '';
          fileSize = 0;
          bytesReceived = 0;
          progress = 0.0;
        });
      }
    });
  }

  // Helper methods for file handling
  Future<Map<String, dynamic>> _processMetadata(
      List<int> buffer, int size) async {
    final metadataJson = utf8.decode(buffer.sublist(0, size));
    final metadata = json.decode(metadataJson) as Map<String, dynamic>;
    final expectedFileName = sanitizeFileName(p.basename(metadata['fileName']));
    final expectedFileSize = metadata['fileSize'];

    // Validate file size
    if (expectedFileSize > MAX_FILE_SIZE) {
      throw Exception(
          'File too large. Maximum size is ${_formatFileSize(MAX_FILE_SIZE)}');
    }

    if (mounted) {
      setState(() {
        receivedFileName = expectedFileName;
        fileSize = expectedFileSize;
        bytesReceived = 0;
        progress = 0.0;
      });
    }
    return {'fileName': expectedFileName, 'fileSize': expectedFileSize};
  }

  Future<void> _writeFileData(File file, List<int> data) async {
    await file.writeAsBytes(data, mode: FileMode.append);
  }

  void _updateProgress(int written, int total) {
    if (mounted) {
      setState(() {
        bytesReceived = written;
        progress = total > 0 ? written / total : 0.0;
      });
    }
  }

  Future<void> _completeFileTransfer(
      File file, String fileName, int size, Socket client) async {
    if (mounted) {
      setState(() {
        receivedFiles.insert(0, {
          'name': fileName,
          'size': size,
          'path': file.path,
          'date': DateTime.now().toString(),
        });
      });
    }

    _showSnackBar(
      'File received: $fileName',
      Icons.check_circle_rounded,
      const Color(0xFF2AB673),
      action: SnackBarAction(
        label: 'Open',
        textColor: Colors.white,
        onPressed: () => _openFile(file.path),
      ),
    );

    client.write('TRANSFER_COMPLETE');

    if (mounted) {
      setState(() {
        receivedFileName = '';
        fileSize = 0;
        bytesReceived = 0;
        progress = 0.0;
      });
    }
  }

  void stopReceiving() async {
    try {
      await serverSocket?.close();
      _discoverySocket?.close();
      serverSocket = null;
      _discoverySocket = null;

      setState(() {
        isReceiving = false;
        isReceivingAnimation = false;
        progress = 0.0;
        receivedFileName = '';
        fileSize = 0;
        bytesReceived = 0;
        receivedFile = null;
      });

      _showSnackBar(
        'Stopped receiving files',
        Icons.info_rounded,
        Colors.orange,
      );
    } catch (e) {
      _showSnackBar(
        'Error stopping receiver: $e',
        Icons.error_rounded,
        Colors.red,
      );
    }
  }

  void _openFile(String filePath) async {
    try {
      final result = await OpenFile.open(filePath);
      if (result.type != ResultType.done) {
        _showSnackBar(
          'Could not open file: ${result.message}',
          Icons.error_rounded,
          Colors.red,
        );
      }
    } catch (e) {
      _showSnackBar(
        'Error opening file: $e',
        Icons.error_rounded,
        Colors.red,
      );
    }
  }

  void _openDownloadsFolder() async {
    try {
      if (Platform.isWindows) {
        await Process.run('explorer', [downloadDirectoryPath]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [downloadDirectoryPath]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [downloadDirectoryPath]);
      } else {
        await Clipboard.setData(ClipboardData(text: downloadDirectoryPath));
        _showSnackBar(
          'Path copied to clipboard',
          Icons.info_rounded,
          Color(0xFF4E6AF3),
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

  void _copyIpToClipboard() async {
    await Clipboard.setData(ClipboardData(text: ipAddress));
    _showSnackBar(
      'IP address copied to clipboard',
      Icons.check_circle_rounded,
      Color(0xFF4E6AF3),
    );
  }

  String sanitizeFileName(String fileName) {
    return fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024)
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String _formatDate(String dateString) {
    DateTime date = DateTime.parse(dateString);
    return DateFormat('dd MMM yyyy, HH:mm').format(date);
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

  @override
  void dispose() {
    _animationController.dispose();
    serverSocket?.close();
    _discoverySocket?.close();
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

            // Main content - Responsive layout
            Expanded(
              child: _buildMainContent(),
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
            color: const Color(0xFF2AB673).withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.download_rounded,
            size: context.isMobile ? 18 : 22,
            color: Color(0xFF2AB673),
          ),
        ),
        SizedBox(width: context.isMobile ? 8 : 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Receive Files',
                style: TextStyle(
                  fontSize:
                      (context.isMobile ? 16 : 18) * context.fontSizeMultiplier,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2AB673),
                ),
              ),
              Text(
                'Start receiving files from other devices',
                style: TextStyle(
                  fontSize:
                      (context.isMobile ? 11 : 12) * context.fontSizeMultiplier,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.grey[400]
                      : Colors.grey[600],
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMainContent() {
    if (context.isMobile) {
      return _buildMobileLayout();
    } else if (context.isTablet) {
      return _buildTabletLayout();
    } else {
      return _buildDesktopLayout();
    }
  }

  Widget _buildMobileLayout() {
    return SingleChildScrollView(
      child: Column(
        children: [
          // Device info & status
          _buildDeviceInfoCard(),
          SizedBox(height: context.isMobile ? 10 : 12),

          // Current transfer if any
          if (receivedFileName.isNotEmpty) ...[
            _buildCurrentTransferCard(),
            SizedBox(height: context.isMobile ? 10 : 12),
          ],

          // Received files
          _buildReceivedFilesCard(),
        ],
      ),
    );
  }

  Widget _buildTabletLayout() {
    return SingleChildScrollView(
      child: Column(
        children: [
          // Top row: Device info and current transfer (if any)
          if (receivedFileName.isNotEmpty)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: _buildDeviceInfoCard(),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: _buildCurrentTransferCard(),
                ),
              ],
            )
          else
            _buildDeviceInfoCard(),

          const SizedBox(height: 16),

          // Received files (full width)
          _buildReceivedFilesCard(),
        ],
      ),
    );
  }

  Widget _buildDesktopLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left column: Device info and current transfer
        Expanded(
          flex: 2,
          child: Column(
            children: [
              _buildDeviceInfoCard(),
              if (receivedFileName.isNotEmpty) ...[
                const SizedBox(height: 16),
                _buildCurrentTransferCard(),
              ],
            ],
          ),
        ),

        const SizedBox(width: 20),

        // Right column: Received files
        Expanded(
          flex: 3,
          child: _buildReceivedFilesCard(),
        ),
      ],
    );
  }

  Widget _buildDeviceInfoCard() {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: context.responsivePadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Device Info section header
            Row(
              children: [
                Container(
                  padding: EdgeInsets.all(context.isMobile ? 4 : 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2AB673).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.info_outline_rounded,
                    color: Color(0xFF2AB673),
                    size: context.isMobile ? 12 : 14,
                  ),
                ),
                SizedBox(width: context.isMobile ? 6 : 8),
                Text(
                  'Device Info',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: (context.isMobile ? 12 : 14) *
                        context.fontSizeMultiplier,
                  ),
                ),
              ],
            ),

            SizedBox(height: context.isMobile ? 10 : 12),

            // Device info items - Responsive layout
            _buildDeviceInfoItems(),

            Divider(height: context.isMobile ? 20 : 24),

            // Status section
            _buildStatusSection(),

            SizedBox(height: context.isMobile ? 10 : 12),

            // Control buttons - Responsive
            _buildControlButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceInfoItems() {
    if (context.isMobile) {
      return Column(
        children: [
          _buildInfoItem(
            'Device Name',
            computerName,
            Icons.computer_rounded,
            null,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildInfoItem(
                  'IP Address',
                  isLoadingIp ? 'Loading...' : ipAddress,
                  Icons.wifi_rounded,
                  isLoadingIp ? null : _copyIpToClipboard,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildInfoItem(
                  'Port',
                  SERVER_PORT.toString(),
                  Icons.router_rounded,
                  null,
                ),
              ),
            ],
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          child: _buildInfoItem(
            'Device Name',
            computerName,
            Icons.computer_rounded,
            null,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildInfoItem(
            'IP Address',
            isLoadingIp ? 'Loading...' : ipAddress,
            Icons.wifi_rounded,
            isLoadingIp ? null : _copyIpToClipboard,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildInfoItem(
            'Port',
            SERVER_PORT.toString(),
            Icons.router_rounded,
            null,
          ),
        ),
      ],
    );
  }

  Widget _buildStatusSection() {
    return Row(
      children: [
        if (isReceivingAnimation && isReceiving)
          ScaleTransition(
            scale: _pulseAnimation,
            child: Container(
              width: context.isMobile ? 12 : 14,
              height: context.isMobile ? 12 : 14,
              decoration: BoxDecoration(
                color: const Color(0xFF2AB673),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF2AB673).withOpacity(0.3),
                    blurRadius: 8,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
          )
        else
          Container(
            width: context.isMobile ? 12 : 14,
            height: context.isMobile ? 12 : 14,
            decoration: BoxDecoration(
              color: isReceiving ? const Color(0xFF2AB673) : Colors.grey,
              shape: BoxShape.circle,
            ),
          ),
        SizedBox(width: context.isMobile ? 6 : 8),
        Expanded(
          child: Text(
            isReceiving ? 'Listening for files' : 'Not receiving',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize:
                  (context.isMobile ? 12 : 14) * context.fontSizeMultiplier,
              color: isReceiving ? const Color(0xFF2AB673) : null,
            ),
          ),
        ),
        // User info badge
        Container(
          padding: EdgeInsets.symmetric(
              horizontal: context.isMobile ? 6 : 8,
              vertical: context.isMobile ? 3 : 4),
          decoration: BoxDecoration(
            color: const Color(0xFF2AB673).withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.person_rounded,
                size: context.isMobile ? 10 : 12,
                color: Color(0xFF2AB673),
              ),
              SizedBox(width: context.isMobile ? 3 : 4),
              Text(
                computerName,
                style: TextStyle(
                  fontSize:
                      (context.isMobile ? 10 : 12) * context.fontSizeMultiplier,
                  color: Color(0xFF2AB673),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildControlButtons() {
    if (context.isMobile) {
      return Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: isReceiving ? null : startReceiving,
              icon: Icon(Icons.play_arrow_rounded,
                  size: context.isMobile ? 14 : 16),
              label: Text('Start Receiving',
                  style: TextStyle(
                      fontSize: (context.isMobile ? 12 : 13) *
                          context.fontSizeMultiplier)),
              style: ElevatedButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: const Color(0xFF2AB673),
                disabledBackgroundColor: Colors.grey[400],
                padding:
                    EdgeInsets.symmetric(vertical: context.isMobile ? 12 : 14),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: isReceiving ? stopReceiving : null,
              icon: Icon(Icons.stop_rounded, size: context.isMobile ? 14 : 16),
              label: Text('Stop Receiving',
                  style: TextStyle(
                      fontSize: (context.isMobile ? 12 : 13) *
                          context.fontSizeMultiplier)),
              style: ElevatedButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: Colors.red[400],
                disabledBackgroundColor: Colors.grey[400],
                padding:
                    EdgeInsets.symmetric(vertical: context.isMobile ? 12 : 14),
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
            onPressed: isReceiving ? null : startReceiving,
            icon: Icon(Icons.play_arrow_rounded,
                size: context.isMobile ? 14 : 16),
            label: Text('Start',
                style: TextStyle(
                    fontSize: (context.isMobile ? 12 : 13) *
                        context.fontSizeMultiplier)),
            style: ElevatedButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: const Color(0xFF2AB673),
              disabledBackgroundColor: Colors.grey[400],
              padding:
                  EdgeInsets.symmetric(vertical: context.isMobile ? 8 : 10),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: isReceiving ? stopReceiving : null,
            icon: Icon(Icons.stop_rounded, size: context.isMobile ? 14 : 16),
            label: Text('Stop',
                style: TextStyle(
                    fontSize: (context.isMobile ? 12 : 13) *
                        context.fontSizeMultiplier)),
            style: ElevatedButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: Colors.red[400],
              disabledBackgroundColor: Colors.grey[400],
              padding:
                  EdgeInsets.symmetric(vertical: context.isMobile ? 8 : 10),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoItem(
      String label, String value, IconData icon, VoidCallback? onTap) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              icon,
              size: context.isMobile ? 10 : 12,
              color: const Color(0xFF2AB673),
            ),
            SizedBox(width: context.isMobile ? 3 : 4),
            Text(
              label,
              style: TextStyle(
                fontSize:
                    (context.isMobile ? 9 : 11) * context.fontSizeMultiplier,
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.grey[400]
                    : Colors.grey[600],
              ),
            ),
          ],
        ),
        SizedBox(height: context.isMobile ? 1 : 2),
        Row(
          children: [
            Expanded(
              child: Text(
                value,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize:
                      (context.isMobile ? 10 : 12) * context.fontSizeMultiplier,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (onTap != null)
              InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  padding: EdgeInsets.all(context.isMobile ? 1 : 2),
                  child: Icon(
                    Icons.copy,
                    size: context.isMobile ? 10 : 12,
                    color: Color(0xFF2AB673),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildCurrentTransferCard() {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: context.responsivePadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section header
            Row(
              children: [
                Container(
                  padding: EdgeInsets.all(context.isMobile ? 4 : 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4E6AF3).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.downloading_rounded,
                    color: Color(0xFF4E6AF3),
                    size: context.isMobile ? 12 : 14,
                  ),
                ),
                SizedBox(width: context.isMobile ? 6 : 8),
                Text(
                  'Current Transfer',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: (context.isMobile ? 12 : 14) *
                        context.fontSizeMultiplier,
                  ),
                ),
              ],
            ),

            SizedBox(height: context.isMobile ? 10 : 12),

            // File info and progress
            Row(
              children: [
                _getFileTypeIcon(receivedFileName),
                SizedBox(width: context.isMobile ? 8 : 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        receivedFileName,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: (context.isMobile ? 11 : 13) *
                              context.fontSizeMultiplier,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${_formatFileSize(bytesReceived)} of ${_formatFileSize(fileSize)}',
                        style: TextStyle(
                          fontSize: (context.isMobile ? 9 : 11) *
                              context.fontSizeMultiplier,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.grey[400]
                              : Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            SizedBox(height: context.isMobile ? 8 : 10),

            // Progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: Theme.of(context).brightness == Brightness.dark
                    ? Colors.grey[700]
                    : Colors.grey[300],
                valueColor:
                    const AlwaysStoppedAnimation<Color>(Color(0xFF4E6AF3)),
                minHeight: context.isMobile ? 4 : 6,
              ),
            ),

            SizedBox(height: context.isMobile ? 6 : 8),

            // Progress percentage and status
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${(progress * 100).toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: (context.isMobile ? 10 : 12) *
                        context.fontSizeMultiplier,
                    color: Color(0xFF4E6AF3),
                  ),
                ),
                Row(
                  children: [
                    Container(
                      width: context.isMobile ? 8 : 10,
                      height: context.isMobile ? 8 : 10,
                      child: const CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Color(0xFF4E6AF3)),
                      ),
                    ),
                    SizedBox(width: context.isMobile ? 4 : 6),
                    Text(
                      'Receiving...',
                      style: TextStyle(
                        fontSize: (context.isMobile ? 9 : 11) *
                            context.fontSizeMultiplier,
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
    );
  }

  Widget _buildReceivedFilesCard() {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: context.responsivePadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(context.isMobile ? 4 : 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4E6AF3).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.folder_rounded,
                        color: Color(0xFF4E6AF3),
                        size: context.isMobile ? 12 : 14,
                      ),
                    ),
                    SizedBox(width: context.isMobile ? 6 : 8),
                    Text(
                      'Received Files',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: (context.isMobile ? 12 : 14) *
                            context.fontSizeMultiplier,
                      ),
                    ),
                  ],
                ),
                if (receivedFiles.isNotEmpty)
                  TextButton.icon(
                    onPressed: _openDownloadsFolder,
                    icon: Icon(Icons.folder_open_rounded,
                        size: context.isMobile ? 12 : 14),
                    label: Text('Open Folder',
                        style: TextStyle(
                            fontSize: (context.isMobile ? 10 : 12) *
                                context.fontSizeMultiplier)),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF4E6AF3),
                      padding: EdgeInsets.symmetric(
                          horizontal: context.isMobile ? 6 : 8,
                          vertical: context.isMobile ? 2 : 4),
                    ),
                  ),
              ],
            ),

            SizedBox(height: context.isMobile ? 6 : 8),

            // Files list
            _buildFilesList(),
          ],
        ),
      ),
    );
  }

  Widget _buildFilesList() {
    if (receivedFiles.isEmpty) {
      return Container(
        height: context.isMobile ? 120 : 180,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Lottie.asset(
                'assets/empty_folder_animation.json',
                height: context.isMobile ? 50 : 80,
                errorBuilder: (context, error, stackTrace) {
                  return Icon(
                    Icons.folder_open,
                    size: context.isMobile ? 30 : 40,
                    color: Colors.grey[300],
                  );
                },
              ),
              SizedBox(height: context.isMobile ? 8 : 12),
              Text(
                'No files received yet',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize:
                      (context.isMobile ? 12 : 14) * context.fontSizeMultiplier,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.grey[400]
                      : Colors.grey[600],
                ),
              ),
              SizedBox(height: context.isMobile ? 2 : 4),
              Text(
                'Files you receive will appear here',
                style: TextStyle(
                  fontSize:
                      (context.isMobile ? 10 : 12) * context.fontSizeMultiplier,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.grey[500]
                      : Colors.grey[500],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      constraints: BoxConstraints(
        maxHeight: context.isMobile ? 200 : 300,
      ),
      child: ListView.builder(
        shrinkWrap: true,
        physics: const ClampingScrollPhysics(),
        itemCount: receivedFiles.length,
        itemBuilder: (context, index) {
          final file = receivedFiles[index];
          return Card(
            margin: EdgeInsets.only(bottom: context.isMobile ? 4 : 6),
            child: ListTile(
              dense: context.isMobile,
              contentPadding: EdgeInsets.symmetric(
                  horizontal: context.isMobile ? 8 : 10,
                  vertical: context.isMobile ? 2 : 4),
              leading: _getFileTypeIcon(file['name']),
              title: Text(
                file['name'],
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: (context.isMobile ? 11 : 13) *
                        context.fontSizeMultiplier),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${_formatFileSize(file['size'])} • ${_formatDate(file['date'])}',
                style: TextStyle(
                    fontSize: (context.isMobile ? 9 : 11) *
                        context.fontSizeMultiplier),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: IconButton(
                icon: Icon(Icons.open_in_new, size: context.isMobile ? 14 : 16),
                onPressed: () => _openFile(file['path']),
                tooltip: 'Open',
                iconSize: context.isMobile ? 14 : 16,
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFF4E6AF3).withOpacity(0.1),
                  foregroundColor: const Color(0xFF4E6AF3),
                  padding: EdgeInsets.all(context.isMobile ? 4 : 6),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _getFileTypeIcon(String fileName) {
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
    } else if (fileName.endsWith('.ppt') || fileName.endsWith('.pptx')) {
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
      padding: EdgeInsets.all(context.isMobile ? 4 : 6),
      decoration: BoxDecoration(
        color: iconColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(
        iconData,
        color: iconColor,
        size: context.isMobile ? 12 : 16,
      ),
    );
  }
}
