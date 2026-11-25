import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:styled_widget/styled_widget.dart';

import '../core/theme.dart';
import '../widgets/common.dart';
import 'accounts_page.dart';
import 'dashboard_page.dart';
import 'inbox_page.dart';
import 'orders_page.dart';
import 'shipments_page.dart';

/// 应用主壳：底部五个主 Tab（工作概览 / 待认领池 / 订单列表 / 转寄批次 / 账号台账）。
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  /// 上一次在工作概览按返回键的时间，用于双击退出判定。
  DateTime? _lastBackAt;

  /// 处理系统返回键：非工作概览先切回工作概览；工作概览需 2 秒内连按两次退出。
  void _handleBack() {
    if (_index != 0) {
      setState(() => _index = 0);
      return;
    }
    final now = DateTime.now();
    final last = _lastBackAt;
    if (last == null || now.difference(last) > const Duration(seconds: 2)) {
      _lastBackAt = now;
      showToast(context, '再按一次退出应用');
      return;
    }
    SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
        body: IndexedStack(
          index: _index,
          children: [
            DashboardPage(onGoTab: (i) => setState(() => _index = i)),
            const InboxPage(),
            const OrdersPage(),
            const ShipmentsPage(),
            const AccountsPage(),
          ],
        ),
        bottomNavigationBar:
            NavigationBar(
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
                  icon: Icon(Icons.receipt_long_outlined),
                  selectedIcon: Icon(Icons.receipt_long),
                  label: '订单列表',
                ),
                NavigationDestination(
                  icon: Icon(Icons.local_shipping_outlined),
                  selectedIcon: Icon(Icons.local_shipping),
                  label: '转寄',
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
      ),
    );
  }
}
