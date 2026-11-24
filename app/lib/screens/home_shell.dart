import 'package:flutter/material.dart';
import 'package:styled_widget/styled_widget.dart';

import '../core/theme.dart';
import 'accounts_page.dart';
import 'dashboard_page.dart';
import 'inbox_page.dart';

/// 应用主壳：底部三个主 Tab（工作概览 / 待认领池 / 账号台账）。
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          DashboardPage(onGoTab: (i) => setState(() => _index = i)),
          const InboxPage(),
          const AccountsPage(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view_rounded),
            label: '工作概览',
          ),
          NavigationDestination(
            icon: Icon(Icons.inbox_outlined),
            selectedIcon: Icon(Icons.inbox),
            label: '待认领池',
          ),
          NavigationDestination(
            icon: Icon(Icons.badge_outlined),
            selectedIcon: Icon(Icons.badge),
            label: '账号台账',
          ),
        ],
      ).decorated(
        color: AppColors.surface,
        border: const Border(top: BorderSide(color: AppColors.line)),
      ),
    );
  }
}
