import 'dart:io';
import 'package:flutter/material.dart';
import 'package:speedshare/FileSenderScreen.dart';
import 'package:speedshare/ReceiveScreen.dart';
import 'package:speedshare/SettingScreen.dart';
import 'package:animate_do/animate_do.dart';
import 'package:lottie/lottie.dart';
import 'package:intl/intl.dart';
import 'package:speedshare/SyncScreen.dart';
import 'package:speedshare/main.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen>
    with SingleTickerProviderStateMixin {
  int _selectedIndex = 0;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  String computerName = '';

  final List<Map<String, dynamic>> _sidebarOptions = [
    {
      'title': 'Home',
      'icon': Icons.home_rounded,
      'description': 'Dashboard',
      'color': const Color(0xFF4E6AF3)
    },
    {
      'title': 'Send',
      'icon': Icons.send_rounded,
      'description': 'Send Files',
      'color': const Color(0xFF4E6AF3)
    },
    {
      'title': 'Receive',
      'icon': Icons.download_rounded,
      'description': 'Receive Files',
      'color': const Color(0xFF2AB673)
    },
    {
      'title': 'Sync',
      'icon': Icons.sync_rounded,
      'description': 'Sync Files',
      'color': const Color(0xFF4E6AF3)
    },
    {
      'title': 'Settings',
      'icon': Icons.settings_rounded,
      'description': 'Configure preferences',
      'color': const Color(0xFF8B54D3)
    },
  ];

  @override
  void initState() {
    super.initState();
    _getComputerName();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOut,
      ),
    );

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // App bar for mobile and tablet
      appBar: ResponsiveContext(context).isMobile ||
              ResponsiveContext(context).isTablet
          ? _buildAppBar()
          : null,

      // Drawer (removed from mobile since we use BottomTabBar now)
      drawer: null,

      body: _buildBody(),

      // Bottom tab bar for mobile
      bottomNavigationBar: ResponsiveContext(context).isMobile
          ? _buildBottomNavigationBar()
          : null,
    );
  }

  Widget _buildBottomNavigationBar() {
    return BottomNavigationBar(
      currentIndex:
          _selectedIndex >= 0 && _selectedIndex < _sidebarOptions.length
              ? _selectedIndex
              : 0,
      onTap: _selectOption,
      type: BottomNavigationBarType.fixed,
      selectedItemColor:
          _selectedIndex >= 0 && _selectedIndex < _sidebarOptions.length
              ? _sidebarOptions[_selectedIndex]['color']
              : Theme.of(context).primaryColor,
      unselectedItemColor: Colors.grey.withValues(alpha: 0.6),
      showSelectedLabels: true,
      showUnselectedLabels: true,
      items: _sidebarOptions.map((option) {
        return BottomNavigationBarItem(
          icon: Icon(option['icon']),
          label: option['title'],
        );
      }).toList(),
    );
  }

  AppBar? _buildAppBar() {
    if (!ResponsiveContext(context).isMobile &&
        !ResponsiveContext(context).isTablet) return null;

    return AppBar(
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF4E6AF3), Color(0xFF2AB673)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.swap_horiz_rounded,
              size: 20,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 8),
          ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              colors: [Color(0xFF4E6AF3), Color(0xFF2AB673)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ).createShader(bounds),
            child: Text(
              'SpeedShare',
              style: TextStyle(
                fontSize: ResponsiveContext(context).isMobile ? 18 : 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
      actions:
          ResponsiveContext(context).isTablet ? _buildTabletActions() : null,
      elevation: 2,
    );
  }

  List<Widget> _buildTabletActions() {
    return _sidebarOptions.asMap().entries.map((entry) {
      int index = entry.key;
      Map<String, dynamic> option = entry.value;
      bool isSelected = _selectedIndex == index;

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: IconButton(
          onPressed: () => _selectOption(index),
          icon: Icon(option['icon']),
          color: isSelected ? option['color'] : null,
          tooltip: option['title'],
        ),
      );
    }).toList();
  }

  Widget _buildBody() {
    if (ResponsiveContext(context).isMobile) {
      return _buildMobileLayout();
    } else if (ResponsiveContext(context).isTablet) {
      return _buildTabletLayout();
    } else {
      return _buildDesktopLayout();
    }
  }

  Widget _buildMobileLayout() {
    return Container(
      padding: ResponsiveContext(context).responsivePadding,
      child: _buildRightPanel(),
    );
  }

  Widget _buildTabletLayout() {
    return Container(
      padding: ResponsiveContext(context).responsivePadding,
      child: _buildRightPanel(),
    );
  }

  Widget _buildDesktopLayout() {
    return Row(
      children: [
        // Left sidebar
        Container(
          width: _calculateSidebarWidth(),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
              ),
            ],
          ),
          child: _buildSidebarContent(),
        ),
        // Right content area
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _buildRightPanel(),
          ),
        ),
      ],
    );
  }

  double _calculateSidebarWidth() {
    if (ResponsiveContext(context).isDesktop) return 220;
    if (ResponsiveContext(context).isLargeDesktop) return 280;
    return 200;
  }

  Widget _buildSidebarContent() {
    return Column(
      children: [
        // Logo/Title section - only show in desktop sidebar
        if (ResponsiveContext(context).isDesktop ||
            ResponsiveContext(context).isLargeDesktop)
          _buildLogoSection(),

        if (ResponsiveContext(context).isDesktop ||
            ResponsiveContext(context).isLargeDesktop)
          const Divider(height: 1),

        // Menu options
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.symmetric(
              vertical: ResponsiveContext(context).isMobile ? 16 : 8,
              horizontal: ResponsiveContext(context).isMobile ? 16 : 8,
            ),
            itemCount: _sidebarOptions.length,
            itemBuilder: (context, index) => _buildMenuOption(index),
          ),
        ),

        // Device info - only show in desktop sidebar
        if (ResponsiveContext(context).isDesktop ||
            ResponsiveContext(context).isLargeDesktop)
          _buildDeviceInfo(),
      ],
    );
  }

  Widget _buildLogoSection() {
    return Container(
      padding: EdgeInsets.symmetric(
        vertical: context.isLargeDesktop ? 24 : 16,
      ),
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.all(context.isLargeDesktop ? 12 : 10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF4E6AF3), Color(0xFF2AB673)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF4E6AF3).withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(
              Icons.swap_horiz_rounded,
              size: context.isLargeDesktop ? 32 : 28,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 10),
          ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              colors: [Color(0xFF4E6AF3), Color(0xFF2AB673)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ).createShader(bounds),
            child: Text(
              'SpeedShare',
              style: TextStyle(
                fontSize: context.isLargeDesktop ? 24 : 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Fast File Transfers',
            style: TextStyle(
              fontSize: context.isLargeDesktop ? 13 : 11,
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.grey[400]
                  : Colors.grey[600],
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildMenuOption(int index) {
    final option = _sidebarOptions[index];
    final isSelected = _selectedIndex == index;

    return Container(
      margin: EdgeInsets.only(
        bottom: ResponsiveContext(context).isMobile ? 8 : 6,
      ),
      decoration: BoxDecoration(
        borderRadius:
            BorderRadius.circular(ResponsiveContext(context).isMobile ? 12 : 8),
        color:
            isSelected ? option['color'].withOpacity(0.1) : Colors.transparent,
      ),
      child: ListTile(
        dense: !ResponsiveContext(context).isMobile,
        visualDensity: ResponsiveContext(context).isMobile
            ? VisualDensity.standard
            : VisualDensity.compact,
        contentPadding: EdgeInsets.symmetric(
          horizontal: ResponsiveContext(context).isMobile ? 16 : 8,
          vertical: ResponsiveContext(context).isMobile ? 8 : 2,
        ),
        leading: Container(
          padding: EdgeInsets.all(ResponsiveContext(context).isMobile ? 8 : 6),
          decoration: BoxDecoration(
            color: isSelected
                ? option['color'].withOpacity(0.2)
                : Theme.of(context).brightness == Brightness.dark
                    ? Colors.grey[800]
                    : Colors.grey[200],
            borderRadius: BorderRadius.circular(
                ResponsiveContext(context).isMobile ? 8 : 6),
          ),
          child: Icon(
            option['icon'],
            color: isSelected ? option['color'] : Colors.grey[600],
            size: ResponsiveContext(context).isMobile ? 20 : 16,
          ),
        ),
        title: Text(
          option['title'],
          style: TextStyle(
            fontSize: ResponsiveContext(context).isMobile ? 16 : 13,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? option['color'] : null,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: ResponsiveContext(context).isMobile
            ? null
            : Text(
                option['description'],
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.grey[400]
                      : Colors.grey[600],
                ),
                overflow: TextOverflow.ellipsis,
              ),
        trailing: isSelected && !ResponsiveContext(context).isMobile
            ? Icon(Icons.arrow_forward_ios, size: 12, color: option['color'])
            : null,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
              ResponsiveContext(context).isMobile ? 12 : 8),
        ),
        onTap: () => _selectOption(index),
      ),
    );
  }

  Widget _buildDeviceInfo() {
    return Container(
      padding: EdgeInsets.all(context.isLargeDesktop ? 16 : 12),
      child: Column(
        children: [
          const Divider(),
          const SizedBox(height: 6),
          Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF4E6AF3).withOpacity(0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: CircleAvatar(
                  radius: context.isLargeDesktop ? 16 : 14,
                  backgroundColor: const Color(0xFF4E6AF3),
                  child: Icon(
                    Icons.devices,
                    color: Colors.white,
                    size: context.isLargeDesktop ? 16 : 14,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      computerName,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: context.isLargeDesktop ? 14 : 12,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    StreamBuilder<String>(
                      stream: Stream.periodic(
                        const Duration(seconds: 1),
                        (_) => DateFormat('MMM dd, HH:mm:ss')
                            .format(DateTime.now()),
                      ),
                      initialData:
                          DateFormat('MMM dd, HH:mm:ss').format(DateTime.now()),
                      builder: (context, snapshot) {
                        return Text(
                          snapshot.data!,
                          style: TextStyle(
                            fontSize: context.isLargeDesktop ? 11 : 10,
                            color:
                                Theme.of(context).brightness == Brightness.dark
                                    ? Colors.grey[400]
                                    : Colors.grey[600],
                          ),
                          overflow: TextOverflow.ellipsis,
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _selectOption(int index) {
    setState(() {
      _selectedIndex = index;
      _animationController.reset();
      _animationController.forward();
    });

    // Close drawer on mobile after selection
    if (ResponsiveContext(context).isMobile && Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  Widget _buildRightPanel() {
    // Show the selected screen
    switch (_selectedIndex) {
      case 0:
        return _buildWelcomeScreen();
      case 1:
        return FileSenderScreen();
      case 2:
        return ReceiveScreen();
      case 3:
        return SyncScreen();
      case 4:
        return SettingsScreen();
      default:
        return _buildWelcomeScreen();
    }
  }

  Widget _buildWelcomeScreen() {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: Container(
        padding: ResponsiveContext(context).responsivePadding,
        child: Center(
          child: SingleChildScrollView(
            child: FadeIn(
              child: Card(
                elevation: 3,
                shadowColor: Colors.black.withOpacity(0.3),
                child: Padding(
                  padding: ResponsiveContext(context).responsivePadding,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: ResponsiveContext(context).maxContentWidth,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Lottie.asset(
                          'assets/logo.json',
                          height: _calculateLottieHeight(),
                          fit: BoxFit.contain,
                        ),
                        SizedBox(
                            height:
                                ResponsiveContext(context).isMobile ? 16 : 20),
                        ShaderMask(
                          shaderCallback: (bounds) => const LinearGradient(
                            colors: [Color(0xFF4E6AF3), Color(0xFF2AB673)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ).createShader(bounds),
                          child: Text(
                            'Welcome to SpeedShare',
                            style: TextStyle(
                              fontSize: _calculateWelcomeFontSize(),
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        SizedBox(
                            height:
                                ResponsiveContext(context).isMobile ? 8 : 12),
                        Text(
                          'Share files between devices quickly and easily.\nNo internet required - just connect to the same network.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: _calculateSubtitleFontSize(),
                            height: 1.4,
                          ),
                        ),
                        SizedBox(
                            height:
                                ResponsiveContext(context).isMobile ? 20 : 24),

                        // Feature items
                        _buildFeatureItems(),

                        SizedBox(
                            height:
                                ResponsiveContext(context).isMobile ? 20 : 24),

                        // Action buttons
                        _buildActionButtons(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  double _calculateLottieHeight() {
    if (ResponsiveContext(context).isMobile) return 100;
    if (ResponsiveContext(context).isTablet) return 120;
    if (ResponsiveContext(context).isDesktop) return 140;
    return 160; // Large desktop
  }

  double _calculateWelcomeFontSize() {
    if (ResponsiveContext(context).isMobile) return 20;
    if (ResponsiveContext(context).isTablet) return 24;
    if (ResponsiveContext(context).isDesktop) return 28;
    return 32; // Large desktop
  }

  double _calculateSubtitleFontSize() {
    if (ResponsiveContext(context).isMobile) return 12;
    if (ResponsiveContext(context).isTablet) return 13;
    if (ResponsiveContext(context).isDesktop) return 14;
    return 16; // Large desktop
  }

  Widget _buildFeatureItems() {
    final features = [
      {'icon': Icons.wifi_off_rounded, 'text': 'No Internet'},
      {'icon': Icons.speed_rounded, 'text': 'Fast Transfers'},
      {'icon': Icons.security_rounded, 'text': 'Secure'},
    ];

    if (ResponsiveContext(context).isMobile) {
      return Column(
        children: features
            .map((feature) => Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _buildFeatureItem(
                      feature['icon'] as IconData, feature['text'] as String),
                ))
            .toList(),
      );
    }

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: ResponsiveContext(context).isMobile ? 16 : 20,
      runSpacing: 16,
      children: features
          .map((feature) => _buildFeatureItem(
              feature['icon'] as IconData, feature['text'] as String))
          .toList(),
    );
  }

  Widget _buildFeatureItem(IconData icon, String text) {
    return SizedBox(
      width: ResponsiveContext(context).isMobile ? double.infinity : 90,
      child: ResponsiveContext(context).isMobile
          ? Row(
              children: [
                Container(
                  padding: EdgeInsets.all(
                      ResponsiveContext(context).isMobile ? 12 : 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4E6AF3).withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    color: const Color(0xFF4E6AF3),
                    size: ResponsiveContext(context).isMobile ? 20 : 18,
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  text,
                  style: TextStyle(
                    fontSize: ResponsiveContext(context).isMobile ? 14 : 12,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.grey[300]
                        : Colors.grey[700],
                  ),
                ),
              ],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4E6AF3).withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    color: const Color(0xFF4E6AF3),
                    size: 18,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  text,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.grey[300]
                        : Colors.grey[700],
                  ),
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
    );
  }

  Widget _buildActionButtons() {
    final buttons = [
      {
        'text': 'Send Files',
        'icon': Icons.send_rounded,
        'color': const Color(0xFF4E6AF3),
        'index': 1,
      },
      {
        'text': 'Receive Files',
        'icon': Icons.download_rounded,
        'color': const Color(0xFF2AB673),
        'index': 2,
      },
    ];

    if (ResponsiveContext(context).isMobile) {
      return Column(
        children: buttons
            .map((button) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: _buildActionButton(
                      button['text'] as String,
                      button['icon'] as IconData,
                      button['color'] as Color,
                      () => _selectOption(button['index'] as int),
                    ),
                  ),
                ))
            .toList(),
      );
    }

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 12,
      runSpacing: 12,
      children: buttons
          .map((button) => _buildActionButton(
                button['text'] as String,
                button['icon'] as IconData,
                button['color'] as Color,
                () => _selectOption(button['index'] as int),
              ))
          .toList(),
    );
  }

  Widget _buildActionButton(
      String text, IconData icon, Color color, VoidCallback onTap) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: ResponsiveContext(context).isMobile ? 18 : 16),
      label: Text(
        text,
        style:
            TextStyle(fontSize: ResponsiveContext(context).isMobile ? 14 : 13),
      ),
      style: ElevatedButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: color,
        padding: EdgeInsets.symmetric(
          horizontal: ResponsiveContext(context).isMobile ? 24 : 16,
          vertical: ResponsiveContext(context).isMobile ? 16 : 12,
        ),
        elevation: 2,
        shadowColor: color.withAlpha((0.4 * 255).toInt()),
        minimumSize: Size(
            ResponsiveContext(context).isMobile ? double.infinity : 120, 0),
      ),
    );
  }
}
