import 'package:flutter/material.dart';

import '../core/app_events.dart';
import '../core/db.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import 'order_form_page.dart';
import 'scan_page.dart';
import 'waybill_page.dart';

/// 工作台：今日概况、快捷入口与最近入库。
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key, required this.onGoTab});

  /// 切换底部 Tab 的回调。
  final ValueChanged<int> onGoTab;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  DashboardStats? _stats;
  List<ParcelModel> _recent = const [];

  @override
  void initState() {
    super.initState();
    dbRevision.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    dbRevision.removeListener(_load);
    super.dispose();
  }

  /// 加载首页统计数据与最近包裹。
  Future<void> _load() async {
    final db = AppDatabase.instance;
    final stats = await db.stats();
    final recent = await db.recentParcels();
    if (!mounted) return;
    setState(() {
      _stats = stats;
      _recent = recent;
    });
  }

  /// 打开扫码页。
  Future<void> _openScan() async {
    final created = await Navigator.of(context).push<int>(
      MaterialPageRoute(builder: (_) => const ScanPage()),
    );
    if (created != null && created > 0 && mounted) {
      showToast(context, '已入库 $created 件，进入待认领池');
      bumpDbRevision();
    }
  }

  /// 打开面单识别页。
  Future<void> _openWaybill() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const WaybillPage()),
    );
  }

  /// 打开代下单登记的页面。
  Future<void> _openOrder() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const OrderFormPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? '上午好'
        : hour < 18
            ? '下午好'
            : '晚上好';
    final stats = _stats;

    return Scaffold(
      appBar: AppBar(
        title: const Text('包裹管家'),
        actions: [
          IconButton(
            tooltip: '扫码入库',
            onPressed: _openScan,
            icon: const Icon(Icons.qr_code_scanner),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            Text(
              '$greeting，李主管',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              stats == null
                  ? '正在读取本地数据…'
                  : '今日已完成 ${stats.todayScanned} 次扫描，${stats.pending} 件等待认领',
              style: const TextStyle(fontSize: 13, color: AppColors.ink3),
            ),
            const SizedBox(height: 18),
            _StatsGrid(stats: stats),
            const SectionHeader(title: '快捷操作'),
            Row(
              children: [
                Expanded(
                  child: _QuickAction(
                    icon: Icons.qr_code_scanner,
                    label: '扫码入库',
                    highlight: true,
                    onTap: _openScan,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _QuickAction(
                    icon: Icons.document_scanner_outlined,
                    label: '面单识别',
                    onTap: _openWaybill,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _QuickAction(
                    icon: Icons.receipt_long_outlined,
                    label: '代下单',
                    onTap: _openOrder,
                  ),
                ),
              ],
            ),
            SectionHeader(
              title: '最近入库',
              trailing: TextButton(
                onPressed: () => widget.onGoTab(1),
                child: const Text('全部'),
              ),
            ),
            if (_recent.isEmpty)
              const EmptyState(
                icon: Icons.inventory_2_outlined,
                title: '还没有包裹',
                description: '点击「扫码入库」开始登记，或在工作台右上角快速扫码。',
              )
            else
              ..._recent.map(
                (parcel) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: AppCard(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    onTap: () => widget.onGoTab(1),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                parcel.trackingNo,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.ink,
                                  letterSpacing: 0.3,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${parcel.carrier.isEmpty ? '未知快递' : parcel.carrier} · '
                                '${parcel.source.label} · ${formatTime(parcel.scannedAt)}',
                                style: const TextStyle(fontSize: 12, color: AppColors.ink3),
                              ),
                            ],
                          ),
                        ),
                        StatusChip(status: parcel.status, dense: true),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 2×2 指标卡。
class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.stats});

  final DashboardStats? stats;

  @override
  Widget build(BuildContext context) {
    final items = [
      ('今日扫描', stats?.todayScanned ?? 0, Icons.qr_code_scanner, AppColors.brand),
      ('待认领', stats?.pending ?? 0, Icons.inbox_outlined, AppColors.warn),
      ('已分配', stats?.assigned ?? 0, Icons.assignment_turned_in_outlined, const Color(0xFF1D4ED8)),
      ('账号数', stats?.accountCount ?? 0, Icons.badge_outlined, const Color(0xFF6D28D9)),
    ];
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _MetricCard(item: items[0])),
            const SizedBox(width: 10),
            Expanded(child: _MetricCard(item: items[1])),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _MetricCard(item: items[2])),
            const SizedBox(width: 10),
            Expanded(child: _MetricCard(item: items[3])),
          ],
        ),
      ],
    );
  }
}

/// 单个指标卡。
class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.item});

  final (String, int, IconData, Color) item;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(item.$3, size: 16, color: item.$4),
              const SizedBox(width: 6),
              Text(
                item.$1,
                style: const TextStyle(fontSize: 12, color: AppColors.ink2),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${item.$2}',
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

/// 快捷操作方块。
class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.highlight = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final fg = highlight ? Colors.white : AppColors.ink;
    return AppCard(
      onTap: onTap,
      color: highlight ? AppColors.brand : AppColors.surface,
      borderColor: highlight ? AppColors.brand : AppColors.line,
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          Icon(icon, size: 22, color: highlight ? Colors.white : AppColors.brandDeep),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}
