import 'package:flutter/material.dart';
import 'package:speedshare/FileSenderScreen.dart';
import 'package:speedshare/ReceiveScreen.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:animate_do/animate_do.dart';
import 'package:lottie/lottie.dart';
import 'package:speedshare/SettingScreen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen>
    with SingleTickerProviderStateMixin {
  int _selectedIndex = -1;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  final List<Map<String, dynamic>> _sidebarOptions = [
    {
      'title': 'Send',
      'icon': Icons.send_rounded,
      'description': 'Send Files',
      'color': Color(0xFF4E6AF3)
    },
    {
      'title': 'Receive',
      'icon': Icons.download_rounded,
      'description': 'Receive Files',
      'color': Color(0xFF2AB673)
    },
    {
      'title': 'Settings',
      'icon': Icons.settings_rounded,
      'description': 'Configure preferences',
      'color': Color(0xFF8B54D3)
    },
    // Add more options here in the future
    // {
    //   'title': 'History',
    //   'icon': Icons.history_rounded,
    //   'description': 'View your file transfer history',
    //   'color': Colors.purple
    // },
  ];

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 500),
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

  @override
  Widget build(BuildContext context) {
    // Get screen size for responsive design
    final Size screenSize = MediaQuery.of(context).size;
    final bool isSmallScreen = screenSize.width < 1000;

    return Scaffold(
      // Use a responsive layout that changes based on screen size
      body: isSmallScreen ? _buildMobileLayout() : _buildDesktopLayout(),
    );
  }

  Widget _buildDesktopLayout() {
    return Row(
      children: [
        // Left sidebar with animation
        FadeInLeft(
          duration: Duration(milliseconds: 600),
          child: Container(
            width: 280,
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 15,
                  offset: Offset(2, 0),
                ),
              ],
            ),
            child: Column(
              children: [
                // Logo/Title section with animation
                FadeInDown(
                  duration: Duration(milliseconds: 800),
                  child: Container(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Column(
                      children: [
                        Container(
                          padding: EdgeInsets.all(14),
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
                            size: 42,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(height: 16),
                        Text(
                          'SpeedShare',
                          style: GoogleFonts.poppins(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            background: Paint()
                              ..shader = LinearGradient(
                                colors: [Color(0xFF4E6AF3), Color(0xFF2AB673)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ).createShader(Rect.fromLTWH(0, 0, 200, 70)),
                          ),
                        ),
                        Text(
                          'Fast File Transfers',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            color: Colors.grey[600],
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Divider(
                    height: 1,
                    thickness: 1,
                    color: Colors.grey.withOpacity(0.1)),

                // Menu options with staggered animation
                Expanded(
                  child: ListView.builder(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    itemCount: _sidebarOptions.length,
                    itemBuilder: (context, index) {
                      final option = _sidebarOptions[index];
                      final isSelected = _selectedIndex == index;

                      return FadeInLeft(
                        delay: Duration(milliseconds: 100 * index),
                        duration: Duration(milliseconds: 400),
                        child: Container(
                          margin:
                              EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            gradient: isSelected
                                ? LinearGradient(
                                    colors: [
                                      option['color'].withOpacity(0.15),
                                      option['color'].withOpacity(0.05),
                                    ],
                                    begin: Alignment.centerLeft,
                                    end: Alignment.centerRight,
                                  )
                                : null,
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: option['color'].withOpacity(0.1),
                                      blurRadius: 10,
                                      offset: Offset(0, 3),
                                    ),
                                  ]
                                : null,
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              splashColor: option['color'].withOpacity(0.1),
                              highlightColor: option['color'].withOpacity(0.05),
                              onTap: () {
                                setState(() {
                                  _selectedIndex = index;
                                  // Reset animation controller and forward it again
                                  _animationController.reset();
                                  _animationController.forward();
                                });
                              },
                              child: Padding(
                                padding: EdgeInsets.symmetric(
                                    vertical: 12, horizontal: 16),
                                child: Row(
                                  children: [
                                    AnimatedContainer(
                                      duration: Duration(milliseconds: 300),
                                      padding: EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? option['color'].withOpacity(0.2)
                                            : Colors.grey.withOpacity(0.08),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Icon(
                                        option['icon'],
                                        color: isSelected
                                            ? option['color']
                                            : Colors.grey[700],
                                        size: 22,
                                      ),
                                    ),
                                    SizedBox(width: 12),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          option['title'],
                                          style: GoogleFonts.poppins(
                                            fontWeight: isSelected
                                                ? FontWeight.bold
                                                : FontWeight.normal,
                                            color: isSelected
                                                ? option['color']
                                                : Colors.grey[800],
                                            fontSize: 15,
                                          ),
                                        ),
                                        Text(
                                          option['description'],
                                          style: GoogleFonts.poppins(
                                            fontSize: 12,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (isSelected) Spacer(),
                                    if (isSelected)
                                      Icon(
                                        Icons.arrow_forward_ios_rounded,
                                        size: 14,
                                        color: option['color'],
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),

                // Version/User info at bottom with animation
                FadeInUp(
                  duration: Duration(milliseconds: 800),
                  child: Container(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Divider(
                            thickness: 1, color: Colors.grey.withOpacity(0.1)),
                        SizedBox(height: 12),
                        Row(
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
                                radius: 18,
                                backgroundColor:
                                    Color(0xFF4E6AF3).withOpacity(0.1),
                                child: Text(
                                  'N',
                                  style: GoogleFonts.poppins(
                                    color: Color(0xFF4E6AF3),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'navin280123',
                                  style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                                Text(
                                  '2025-05-15',
                                  style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                            Spacer(),
                            IconButton(
                              icon: Icon(Icons.settings_rounded,
                                  color: Colors.grey[600], size: 22),
                              onPressed: () {
                                setState(() {
                                  _selectedIndex =
                                      2; // Index of settings in the sidebar options
                                  _animationController.reset();
                                  _animationController.forward();
                                });
                              },
                              tooltip: 'Settings',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Right content area with animation
        Expanded(
          child: AnimatedSwitcher(
            duration: Duration(milliseconds: 400),
            transitionBuilder: (Widget child, Animation<double> animation) {
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: Offset(0.05, 0),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              );
            },
            child: _buildRightPanel(),
          ),
        ),
      ],
    );
  }

  Widget _buildMobileLayout() {
    return Column(
      children: [
        // App bar for mobile
        AppBar(
          title: Row(
            children: [
              Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF4E6AF3), Color(0xFF2AB673)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.swap_horiz_rounded,
                  size: 24,
                  color: Colors.white,
                ),
              ),
              SizedBox(width: 12),
              Text(
                'SpeedShare',
                style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          elevation: 0,
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF4E6AF3),
        ),

        // Content area
        Expanded(
          child: _selectedIndex == -1
              ? _buildMobileWelcomeScreen()
              : AnimatedSwitcher(
                  duration: Duration(milliseconds: 300),
                  child: _buildRightPanel(),
                ),
        ),

        // Bottom navigation
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: Offset(0, -2),
              ),
            ],
          ),
          child: SafeArea(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(_sidebarOptions.length, (index) {
                  final option = _sidebarOptions[index];
                  final isSelected = _selectedIndex == index;

                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedIndex = index;
                        _animationController.reset();
                        _animationController.forward();
                      });
                    },
                    child: AnimatedContainer(
                      duration: Duration(milliseconds: 300),
                      padding:
                          EdgeInsets.symmetric(vertical: 8, horizontal: 24),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? option['color'].withOpacity(0.1)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            option['icon'],
                            color:
                                isSelected ? option['color'] : Colors.grey[700],
                            size: 26,
                          ),
                          SizedBox(height: 4),
                          Text(
                            option['title'],
                            style: GoogleFonts.poppins(
                              color: isSelected
                                  ? option['color']
                                  : Colors.grey[700],
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMobileWelcomeScreen() {
    return FadeIn(
      duration: Duration(milliseconds: 600),
      child: Container(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Lottie.asset(
              'assets/logo.json',
              height: 200,
              repeat: true,
            ),
            SizedBox(height: 32),
            Text(
              'Welcome to SpeedShare',
              style: GoogleFonts.poppins(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Color(0xFF4E6AF3),
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 16),
            Text(
              'Share files between devices quickly and easily. No internet required - just connect to the same network.',
              style: GoogleFonts.poppins(
                fontSize: 16,
                color: Colors.grey[700],
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _featureItemMobile(
                    Icons.wifi_off_rounded, 'No Internet Needed'),
                _featureItemMobile(Icons.speed_rounded, 'Fast Transfers'),
                _featureItemMobile(Icons.security_rounded, 'Secure'),
              ],
            ),
            SizedBox(height: 40),
            Text(
              'Select an option below to begin',
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              color: Colors.grey[600],
              size: 24,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRightPanel() {
    // If no option is selected, show the welcome screen
    if (_selectedIndex == -1) {
      return FadeTransition(
        opacity: _fadeAnimation,
        child: Container(
          decoration: BoxDecoration(
            image: DecorationImage(
              image: AssetImage('assets/bg.jpg'),
              fit: BoxFit.cover,
              colorFilter: ColorFilter.mode(
                Colors.black.withOpacity(0.4),
                BlendMode.darken,
              ),
            ),
          ),
          child: Center(
            child: ZoomIn(
              duration: Duration(milliseconds: 600),
              child: Container(
                width: 550,
                padding: EdgeInsets.all(48),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.95),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.15),
                      blurRadius: 30,
                      offset: Offset(0, 15),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      height: 120,
                      width: 120,
                      child: Lottie.asset(
                        'assets/logo.json',
                        repeat: true,
                      ),
                    ),
                    SizedBox(height: 32),
                    Text(
                      'Welcome to SpeedShare',
                      style: GoogleFonts.poppins(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        foreground: Paint()
                          ..shader = LinearGradient(
                            colors: [Color(0xFF4E6AF3), Color(0xFF2AB673)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ).createShader(Rect.fromLTWH(0, 0, 350, 70)),
                      ),
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Share files between devices quickly and easily. '
                      'No internet required - just connect to the same network.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        color: Colors.grey[700],
                        height: 1.6,
                      ),
                    ),
                    SizedBox(height: 40),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _featureItem(
                            Icons.wifi_off_rounded, 'No Internet Needed'),
                        SizedBox(width: 48),
                        _featureItem(Icons.speed_rounded, 'Fast Transfers'),
                        SizedBox(width: 48),
                        _featureItem(Icons.security_rounded, 'Secure'),
                      ],
                    ),
                    SizedBox(height: 40),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _actionButton(
                          'Send Files',
                          Icons.send_rounded,
                          Color(0xFF4E6AF3),
                          () {
                            setState(() {
                              _selectedIndex = 0;
                              _animationController.reset();
                              _animationController.forward();
                            });
                          },
                        ),
                        SizedBox(width: 16),
                        _actionButton(
                          'Receive Files',
                          Icons.download_rounded,
                          Color(0xFF2AB673),
                          () {
                            setState(() {
                              _selectedIndex = 1;
                              _animationController.reset();
                              _animationController.forward();
                            });
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    // Show the selected screen
    // Show the selected screen
    switch (_selectedIndex) {
      case 0:
        return FileSenderScreen();
      case 1:
        return ReceiveScreen();
      case 2:
        return SettingsScreen();
      default:
        return Container(); // Fallback, should never happen
    }
  }

  Widget _featureItem(IconData icon, String text) {
    return Column(
      children: [
        Container(
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color(0xFF4E6AF3).withOpacity(0.1),
                Color(0xFF2AB673).withOpacity(0.1)
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            color: Color(0xFF4E6AF3),
            size: 28,
          ),
        ),
        SizedBox(height: 12),
        Text(
          text,
          style: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.normal,
            color: Colors.grey[800],
          ),
        ),
      ],
    );
  }

  Widget _featureItemMobile(IconData icon, String text) {
    return Column(
      children: [
        Container(
          padding: EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color(0xFF4E6AF3).withOpacity(0.1),
                Color(0xFF2AB673).withOpacity(0.1)
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            color: Color(0xFF4E6AF3),
            size: 20,
          ),
        ),
        SizedBox(height: 8),
        Text(
          text,
          style: GoogleFonts.poppins(
            fontSize: 11,
            fontWeight: FontWeight.normal,
            color: Colors.grey[800],
          ),
        ),
      ],
    );
  }

  Widget _actionButton(
      String text, IconData icon, Color color, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 14, horizontal: 24),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.3),
                blurRadius: 12,
                offset: Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: Colors.white,
                size: 20,
              ),
              SizedBox(width: 8),
              Text(
                text,
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
