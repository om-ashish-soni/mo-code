import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'api/daemon.dart';
import 'theme/colors.dart';
import 'screens/agent_screen.dart';
import 'screens/files_screen.dart';
import 'screens/tasks_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        backgroundColor: AppColors.panel,
        indicatorColor: AppColors.purple.withAlpha(50),
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
        ],
      ),
    );
  }
}
