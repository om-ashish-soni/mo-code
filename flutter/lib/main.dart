import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'api/daemon.dart';
import 'theme/colors.dart';
import 'screens/agent_screen.dart';
import 'screens/files_screen.dart';
import 'screens/sessions_screen.dart';
import 'screens/tasks_screen.dart';
import 'screens/config_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  Animate.restartOnHotReload = true;
  runApp(const MoCodeApp());
}

class MoCodeApp extends StatelessWidget {
  const MoCodeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Provider<OpenCodeAPI>(
      create: (_) => OpenCodeAPI(),
      dispose: (_, api) => api.dispose(),
      child: MaterialApp(
        title: 'mo-code',
        theme: AppTheme.dark,
        debugShowCheckedModeBanner: false,
        home: const MainScreen(),
      ),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  final _screens = const [
    AgentScreen(),
    FilesScreen(),
    TasksScreen(),
    ConfigScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true, // content extends behind bottom nav for blur effect
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, animation) {
          return FadeTransition(opacity: animation, child: child);
        },
        child: KeyedSubtree(
          key: ValueKey(_currentIndex),
          child: _screens[_currentIndex],
        ),
      ),
      bottomNavigationBar: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.panel.withAlpha(200),
              border: const Border(
                top: BorderSide(color: AppColors.border, width: 0.5),
              ),
            ),
            child: NavigationBar(
              selectedIndex: _currentIndex,
              onDestinationSelected: (index) =>
                  setState(() => _currentIndex = index),
              backgroundColor: Colors.transparent,
              indicatorColor: AppColors.purpleDim,
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.chat_bubble_outline, color: AppColors.textMuted),
                  selectedIcon: Icon(Icons.chat_bubble, color: AppColors.purple),
                  label: 'Agent',
                ),
                NavigationDestination(
                  icon: Icon(Icons.folder_outlined, color: AppColors.textMuted),
                  selectedIcon: Icon(Icons.folder, color: AppColors.purple),
                  label: 'Files',
                ),
                NavigationDestination(
                  icon: Icon(Icons.list_alt_outlined, color: AppColors.textMuted),
                  selectedIcon: Icon(Icons.list_alt, color: AppColors.purple),
                  label: 'Tasks',
                ),
                NavigationDestination(
                  icon: Icon(Icons.settings_outlined, color: AppColors.textMuted),
                  selectedIcon: Icon(Icons.settings, color: AppColors.purple),
                  label: 'Config',
                ),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: _currentIndex == 0
          ? Padding(
              padding: const EdgeInsets.only(bottom: 72),
              child: FloatingActionButton.small(
                backgroundColor: AppColors.surface,
                elevation: 8,
                onPressed: _openSessions,
                tooltip: 'Session history',
                child: const Icon(Icons.history, color: AppColors.purple, size: 20),
              ),
            )
          : null,
    );
  }

  void _openSessions() {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => Provider.value(
          value: context.read<OpenCodeAPI>(),
          child: const SessionsScreen(),
        ),
        transitionsBuilder: (_, animation, __, child) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            )),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 350),
      ),
    ).then((result) {
      if (result is Map && result['action'] == 'resume') {
        setState(() => _currentIndex = 0);
      }
    });
  }
}
