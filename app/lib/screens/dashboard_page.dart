import 'package:flutter/material.dart';
import 'package:styled_widget/styled_widget.dart';

import '../core/app_events.dart';
import '../core/db.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import 'order_form_page.dart';
import 'products_page.dart';
import 'backup_sheet.dart';
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
  List<OrderView> _pendingOrders = const [];
  BusinessSummary? _summary;
  _Range _range = _Range.thisMonth;

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

  /// 加载首页统计、经营概览、待补单号与最近包裹。
  Future<void> _load() async {
    final db = AppDatabase.instance;
    final stats = await db.stats();
    final recent = await db.recentParcels();
    final summary = await db.orderSummary(_range.start(DateTime.now()));
    final pendingOrders = await db.pendingTrackingOrders(limit: 5);
    if (!mounted) return;
    setState(() {
      _stats = stats;
      _recent = recent;
      _summary = summary;
      _pendingOrders = pendingOrders;
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

  /// 打开商品库。
  Future<void> _openProducts() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ProductsPage()),
    );
  }

  /// 为订单补录物流单号（已有同号包裹会同步归属）。
  ///
  /// 参数：[view] 待补单号的订单。
  Future<void> _fillTracking(OrderView view) async {
    final controller = TextEditingController();
    final submitted = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('补录物流单号'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: appInput(
            hint: '粘贴或扫码填入物流单号',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (submitted == null || submitted.isEmpty) {
      controller.dispose();
      return;
    }
    await AppDatabase.instance.updateOrderTracking(
      orderId: view.order.id,
      trackingNo: submitted,
    );
    controller.dispose();
    if (!mounted) return;
    bumpDbRevision();
    showToast(context, '物流单号已补录，包裹到货扫码后自动合并');
  }

  /// 经营概览时间范围标签。
  ///
  /// 参数：[range] 该标签代表的时间范围。
  Widget _buildRangeChip(_Range range) {
    final active = _range == range;
    return Text(range.label)
        .fontSize(12)
        .fontWeight(FontWeight.w600)
        .textColor(active ? Colors.white : AppColors.ink2)
        .center()
        .padding(horizontal: 14)
        .ripple(
          customBorder: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(999)),
          ),
        )
        .gestures(onTap: () {
          if (_range == range) return;
          setState(() => _range = range);
          _load();
        })
        .clipRRect(all: 999)
        .decorated(
          color: active ? AppColors.brand : AppColors.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: active ? AppColors.brand : AppColors.line),
        )
        .padding(right: 8);
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
            tooltip: '商品库',
            onPressed: _openProducts,
            icon: const Icon(Icons.inventory_2_outlined),
          ),
          IconButton(
            tooltip: '数据备份',
            onPressed: () => showBackupSheet(context),
            icon: const Icon(Icons.backup_outlined),
          ),
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
            Text('$greeting，李主管')
                .fontSize(24)
                .fontWeight(FontWeight.w700)
                .textColor(AppColors.ink)
                .letterSpacing(-0.2),
            Text(
              stats == null
                  ? '正在读取本地数据…'
                  : '今日已完成 ${stats.todayScanned} 次扫描，${stats.pending} 件等待认领',
            )
                .fontSize(13)
                .textColor(AppColors.ink3)
                .padding(top: 4),
            _StatsGrid(stats: stats).padding(top: 18),
            const SectionHeader(title: '经营概览'),
            Row(
              children: [
                for (final range in _Range.values) _buildRangeChip(range),
              ],
            ),
            _BusinessCard(summary: _summary).padding(top: 10),
            const SectionHeader(title: '快捷操作'),
            Row(
              children: [
                _QuickAction(
                  icon: Icons.qr_code_scanner,
                  label: '扫码入库',
                  highlight: true,
                  onTap: _openScan,
                ).expanded(),
                const SizedBox(width: 10),
                _QuickAction(
                  icon: Icons.document_scanner_outlined,
                  label: '面单识别',
                  onTap: _openWaybill,
                ).expanded(),
                const SizedBox(width: 10),
                _QuickAction(
                  icon: Icons.receipt_long_outlined,
                  label: '代下单',
                  onTap: _openOrder,
                ).expanded(),
              ],
            ),
            SectionHeader(
              title: '待补单号',
              trailing: _pendingOrders.isEmpty
                  ? null
                  : Text('${_pendingOrders.length} 笔')
                      .fontSize(12)
                      .textColor(AppColors.ink3),
            ),
            if (_pendingOrders.isEmpty)
              AppCard(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                child: Text('暂无待补单号的订单')
                    .fontSize(13)
                    .textColor(AppColors.ink3),
              )
            else
              ..._pendingOrders.map(
                (view) => AppCard(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            view.order.title.isEmpty
                                ? '未命名订单'
                                : view.order.title,
                          )
                              .fontSize(14)
                              .fontWeight(FontWeight.w600)
                              .textColor(AppColors.ink),
                          Text(
                            '${view.accountTitle} · ${view.order.route.label} · '
                            '${formatTime(view.order.orderedAt)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          )
                              .fontSize(12)
                              .textColor(AppColors.ink3)
                              .padding(top: 3),
                        ],
                      ).expanded(),
                      TextButton(
                        onPressed: () => _fillTracking(view),
                        child: const Text('补单号', maxLines: 1, softWrap: false),
                      ),
                    ],
                  ),
                ).padding(bottom: 8),
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
                (parcel) => AppCard(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  onTap: () => widget.onGoTab(1),
                  child: Row(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(parcel.trackingNo)
                              .fontSize(14)
                              .fontWeight(FontWeight.w600)
                              .textColor(AppColors.ink)
                              .letterSpacing(0.3),
                          Text(
                            '${parcel.carrier.isEmpty ? '未知快递' : parcel.carrier} · '
                            '${parcel.source.label} · ${formatTime(parcel.scannedAt)}',
                          )
                              .fontSize(12)
                              .textColor(AppColors.ink3)
                              .padding(top: 4),
                        ],
                      ).expanded(),
                      StatusChip(status: parcel.status, dense: true),
                    ],
                  ),
                ).padding(bottom: 8),
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
            _MetricCard(item: items[0]).expanded(),
            const SizedBox(width: 10),
            _MetricCard(item: items[1]).expanded(),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _MetricCard(item: items[2]).expanded(),
            const SizedBox(width: 10),
            _MetricCard(item: items[3]).expanded(),
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
              Text(item.$1)
                  .fontSize(12)
                  .textColor(AppColors.ink2)
                  .padding(left: 6),
            ],
          ),
          Text('${item.$2}')
              .fontSize(26)
              .fontWeight(FontWeight.w700)
              .textColor(AppColors.ink)
              .textStyle(const TextStyle(height: 1))
              .padding(top: 10),
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
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)
              .fontSize(12)
              .fontWeight(FontWeight.w600)
              .textColor(fg)
              .padding(top: 8),
        ],
      ),
    );
  }
}

/// 经营概览时间范围。
enum _Range {
  thisMonth('本月'),
  lastThreeMonths('近3月'),
  thisYear('本年');

  const _Range(this.label);

  /// 中文展示名。
  final String label;

  /// 计算统计起点（含）。
  DateTime start(DateTime now) {
    switch (this) {
      case _Range.thisMonth:
        return DateTime(now.year, now.month, 1);
      case _Range.lastThreeMonths:
        return DateTime(now.year, now.month - 2, 1);
      case _Range.thisYear:
        return DateTime(now.year, 1, 1);
    }
  }
}

/// 经营概览卡片：订单数、销售额、成本与利润。
class _BusinessCard extends StatelessWidget {
  const _BusinessCard({required this.summary});

  final BusinessSummary? summary;

  /// 金额格式化，空值显示占位符。
  String _money(double? value) => value == null ? '—' : value.toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    final profit = summary?.profit ?? 0;
    final items = <(String, String, Color)>[
      ('订单', '${summary?.orderCount ?? 0}', AppColors.ink),
      ('销售额', '¥${_money(summary?.sales)}', AppColors.ink),
      ('成本', '¥${_money(summary?.cost)}', AppColors.ink),
      ('利润', '¥${_money(summary?.profit)}',
          profit >= 0 ? AppColors.brandDeep : AppColors.danger),
    ];
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 14),
      child: Row(
        children: [
          for (final item in items)
            Column(
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(item.$2)
                      .fontSize(17)
                      .fontWeight(FontWeight.w700)
                      .textColor(item.$3)
                      .textStyle(const TextStyle(height: 1.2)),
                ),
                Text(item.$1)
                    .fontSize(11)
                    .textColor(AppColors.ink3)
                    .padding(top: 4),
              ],
            ).expanded(),
        ],
      ),
    );
  }
}
