import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:styled_widget/styled_widget.dart';

import '../core/app_events.dart';
import '../core/db.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import 'shipment_detail_page.dart';
import 'shipment_form_page.dart';

/// 转寄批次：把一个快递单寄出的多个包裹记成一批，并统计快递费。
class ShipmentsPage extends StatefulWidget {
  const ShipmentsPage({super.key});

  @override
  State<ShipmentsPage> createState() => _ShipmentsPageState();
}

class _ShipmentsPageState extends State<ShipmentsPage> {
  final TextEditingController _searchCtrl = TextEditingController();

  List<ShipmentView> _items = const [];
  bool _loading = true;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    dbRevision.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    dbRevision.removeListener(_load);
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  /// 按关键词加载转寄批次。
  Future<void> _load() async {
    final items = await AppDatabase.instance.shipments(
      keyword: _searchCtrl.text,
    );
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  /// 搜索输入（300ms 防抖）。
  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _load);
  }

  /// 打开新建/编辑批次页。
  Future<void> _openForm({ShipmentView? editing}) async {
    final done = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ShipmentFormPage(editing: editing),
      ),
    );
    if (done == true) _load();
  }

  /// 删除批次二次确认；包裹会保留并恢复为已入库。
  Future<void> _delete(ShipmentView view) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除转寄批次'),
        content: Text(
          '确认删除这批 ${view.parcelCount} 件包裹的转寄记录？'
          '包裹会保留并恢复为已入库，快递费统计会同步扣除。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await AppDatabase.instance.deleteShipment(view.shipment.id);
    } catch (_) {
      if (!mounted) return;
      showToast(context, '删除失败，请重试');
      return;
    }
    if (!mounted) return;
    showToast(context, '批次已删除');
    bumpDbRevision();
  }

  /// 日期展示文案。
  String _date(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }

  /// 打开批次详情。
  Future<void> _openDetail(ShipmentView view) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => ShipmentDetailPage(view: view)),
    );
    if (mounted) _load();
  }

  /// 批次卡片：点击查看详情，左滑编辑/删除。
  Widget _buildCard(ShipmentView view) {
    final shipment = view.shipment;
    return SlideActionCard(
      slideKey: ValueKey(shipment.id),
      groupTag: 'shipments',
      extentRatio: 0.38,
      actions: [
        SlidableAction(
          onPressed: (_) => _openForm(editing: view),
          backgroundColor: AppColors.brand,
          foregroundColor: Colors.white,
          icon: Icons.edit_outlined,
          label: '编辑',
          labelStyle: const TextStyle(fontSize: 12),
        ),
        SlidableAction(
          onPressed: (_) => _delete(view),
          backgroundColor: AppColors.danger,
          foregroundColor: Colors.white,
          icon: Icons.delete_outline,
          label: '删除',
          labelStyle: const TextStyle(fontSize: 12),
        ),
      ],
      child: AppCard(
        seamless: true,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Text(shipment.carrier.isEmpty ? '快递' : shipment.carrier)
                .fontSize(13)
                .fontWeight(FontWeight.w700)
                .textColor(AppColors.brandDeep)
                .center()
                .constrained(width: 52, height: 40)
                .decorated(
                  color: AppColors.brandSoft,
                  borderRadius: BorderRadius.circular(10),
                )
                .padding(right: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  shipment.trackingNo.isEmpty ? '未填写运单号' : shipment.trackingNo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ).fontSize(14).fontWeight(FontWeight.w600).textColor(AppColors.ink),
                Text(
                  [
                    '${view.parcelCount} 件包裹',
                    if (view.orderCount > 0) '${view.orderCount} 个订单',
                    _date(shipment.shippedAt),
                    if (shipment.note.isNotEmpty) shipment.note,
                  ].join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ).fontSize(11).textColor(AppColors.ink3).padding(top: 3),
              ],
            ).expanded(),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('¥${shipment.fee.toStringAsFixed(2)}')
                    .fontSize(15)
                    .fontWeight(FontWeight.w700)
                    .textColor(AppColors.ink),
                const Text('快递费')
                    .fontSize(10)
                    .textColor(AppColors.ink3)
                    .padding(top: 2),
              ],
            ).padding(left: 10),
          ],
        ),
      ).gestures(onTap: () => _openDetail(view)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final keyword = _searchCtrl.text.trim();
    return Scaffold(
      appBar: AppBar(
        title: const Text('转寄批次'),
        actions: [
          IconButton(
            tooltip: '新建转寄批次',
            onPressed: () => _openForm(),
            icon: const Icon(Icons.add),
          ),
          IconButton(
            tooltip: '刷新',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          TextField(
            controller: _searchCtrl,
            onChanged: _onSearchChanged,
            decoration: appInput(
              hint: '搜索快递公司、运单号或备注',
              prefix: const Icon(
                Icons.search,
                size: 20,
                color: AppColors.ink3,
              ),
            ),
          ).padding(left: 16, right: 16, bottom: 8),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                ? EmptyState(
                    icon: Icons.local_shipping_outlined,
                    title: keyword.isEmpty ? '还没有转寄批次' : '没有匹配的批次',
                    description: '一次寄件建一个批次，勾选本次寄出的包裹并填写快递费，费用会自动计入经营统计。',
                    action: FilledButton(
                      onPressed: () => _openForm(),
                      child: const Text('新建转寄批次'),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: SlidableAutoCloseBehavior(
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                        itemCount: _items.length,
                        itemBuilder: (context, index) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _buildCard(_items[index]),
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
