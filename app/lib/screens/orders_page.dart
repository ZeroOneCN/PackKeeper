import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:styled_widget/styled_widget.dart';

import '../core/app_events.dart';
import '../core/db.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import '../widgets/parcel_picker.dart';
import 'order_form_page.dart';

/// 订单列表：检索、平台筛选与补录物流单号。
class OrdersPage extends StatefulWidget {
  const OrdersPage({super.key});

  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> {
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _trackingCtrl = TextEditingController();

  List<ShopPlatform> _platforms = const [];
  List<OrderView> _items = const [];
  String? _platformId;
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
    _trackingCtrl.dispose();
    super.dispose();
  }

  /// 按当前筛选条件与关键词加载订单。
  Future<void> _load() async {
    final db = AppDatabase.instance;
    final platforms = await db.platforms();
    final items = await db.orderList(
      keyword: _searchCtrl.text,
      platformId: _platformId,
    );
    if (!mounted) return;
    setState(() {
      _platforms = platforms;
      _items = items;
      _loading = false;
    });
  }

  /// 搜索输入（300ms 防抖）。
  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _load);
  }

  /// 平台筛选下拉入口。
  Widget _buildPlatformFilter() {
    final active = _platforms.where((p) => p.id == _platformId).toList();
    final name = active.isEmpty ? '全部平台' : active.first.name;
    final color = active.isEmpty ? AppColors.ink3 : Color(active.first.color);
    return SizedBox(
      width: 150,
      child:
          InputDecorator(
                decoration: appInput(),
                child: Row(
                  children: [
                    SizedBox(width: 8, height: 8)
                        .decorated(color: color, shape: BoxShape.circle)
                        .padding(right: 6),
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ).fontSize(13).textColor(AppColors.ink).expanded(),
                    const Icon(
                      Icons.expand_more,
                      size: 18,
                      color: AppColors.ink3,
                    ),
                  ],
                ),
              )
              .ripple(
                customBorder: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                ),
              )
              .gestures(onTap: _pickFilterPlatform),
    );
  }

  /// 平台筛选底部弹层（含「全部平台」）。
  Future<void> _pickFilterPlatform() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '筛选平台',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  ListTile(
                    leading: const Icon(
                      Icons.apps,
                      size: 20,
                      color: AppColors.ink2,
                    ),
                    title: const Text('全部平台'),
                    trailing: _platformId == null
                        ? const Icon(
                            Icons.check,
                            size: 20,
                            color: AppColors.brand,
                          )
                        : null,
                    onTap: () => Navigator.pop(ctx, ''),
                  ),
                  for (final platform in _platforms)
                    ListTile(
                      leading: const SizedBox(width: 10, height: 10).decorated(
                        color: Color(platform.color),
                        shape: BoxShape.circle,
                      ),
                      title: Text(platform.name),
                      trailing: _platformId == platform.id
                          ? const Icon(
                              Icons.check,
                              size: 20,
                              color: AppColors.brand,
                            )
                          : null,
                      onTap: () => Navigator.pop(ctx, platform.id),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _platformId = picked.isEmpty ? null : picked;
      _loading = true;
    });
    _load();
  }

  /// 补录物流单号弹窗。
  ///
  /// 参数：[view] 目标订单；单号已存在包裹时数据层会自动建立归属。
  Future<void> _fillTracking(OrderView view) async {
    _trackingCtrl.text = view.order.trackingNo;
    var saving = false;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('补录物流单号'),
          content: TextField(
            controller: _trackingCtrl,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            decoration: appInput(hint: '粘贴或输入物流单号'),
          ),
          actions: [
            TextButton.icon(
              onPressed: saving
                  ? null
                  : () async {
                      final picked = await showParcelPicker(ctx);
                      if (picked == null) return;
                      _trackingCtrl.text = picked.trackingNo;
                      setDialogState(() {});
                    },
              icon: const Icon(Icons.inbox_outlined, size: 16),
              label: const Text('从池子选择'),
            ),
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      final value = _trackingCtrl.text.trim();
                      if (value.isEmpty) {
                        showToast(ctx, '请填写物流单号');
                        return;
                      }
                      setDialogState(() => saving = true);
                      try {
                        await AppDatabase.instance.updateOrderTracking(
                          orderId: view.order.id,
                          trackingNo: value,
                        );
                        if (ctx.mounted) Navigator.pop(ctx, true);
                      } catch (_) {
                        if (ctx.mounted) {
                          setDialogState(() => saving = false);
                          showToast(ctx, '保存失败，请重试');
                        }
                      }
                    },
              child: Text(saving ? '保存中…' : '保存'),
            ),
          ],
        ),
      ),
    );
    if (saved != true || !mounted) return;
    showToast(context, '物流单号已更新');
    bumpDbRevision();
  }

  /// 打开代下单登记页，保存后刷新列表。
  Future<void> _openCreate() async {
    final done = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const OrderFormPage()),
    );
    if (done == true) _load();
  }

  /// 订单卡片：左滑出现「补单号」（仅未回填单号的订单）。
  Widget _buildOrderCard(OrderView view) {
    final order = view.order;
    final pending = order.trackingNo.isEmpty;
    final card = AppCard(
      seamless: true,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                order.title.isEmpty ? '未填写商品标题' : order.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ).fontSize(14).fontWeight(FontWeight.w600).textColor(AppColors.ink),
              Text(view.accountTitle)
                  .fontSize(12)
                  .textColor(AppColors.ink3)
                  .padding(top: 3),
              Text(
                [
                  formatTime(order.orderedAt),
                  if (pending) '待补物流单号' else '运单 ${order.trackingNo}',
                ].join(' · '),
              )
                  .fontSize(12)
                  .textColor(pending ? AppColors.warn : AppColors.ink3)
                  .padding(top: 3),
            ],
          ).expanded(),
          Text('¥${(order.amount ?? 0).toStringAsFixed(2)}')
              .fontSize(14)
              .fontWeight(FontWeight.w700)
              .textColor(AppColors.ink)
              .padding(left: 10),
        ],
      ),
    );
    return SlideActionCard(
      slideKey: ValueKey(order.id),
      groupTag: 'orders',
      extentRatio: pending ? 0.38 : 0.24,
      actions: [
        if (pending)
          SlidableAction(
            onPressed: (_) => _fillTracking(view),
            backgroundColor: AppColors.brand,
            foregroundColor: Colors.white,
            icon: Icons.local_shipping_outlined,
            label: '补单号',
            labelStyle: const TextStyle(fontSize: 12),
          ),
        SlidableAction(
          onPressed: (_) => _confirmDelete(view),
          backgroundColor: AppColors.danger,
          foregroundColor: Colors.white,
          icon: Icons.delete_outline,
          label: '删除',
          labelStyle: const TextStyle(fontSize: 12),
        ),
      ],
      child: card,
    );
  }

  /// 删除订单二次确认；已关联包裹会保留并解除关联。
  ///
  /// 参数：[view] 目标订单。
  Future<void> _confirmDelete(OrderView view) async {
    final name = view.order.title.isEmpty
        ? '这笔订单'
        : '「${view.order.title}」';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除订单'),
        content: Text('确认删除$name？已关联的包裹会保留，删除后不可恢复。'),
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
      await AppDatabase.instance.deleteOrder(view.order.id);
    } catch (_) {
      if (!mounted) return;
      showToast(context, '删除失败，请重试');
      return;
    }
    if (!mounted) return;
    showToast(context, '订单已删除');
    bumpDbRevision();
  }

  @override
  Widget build(BuildContext context) {
    final keyword = _searchCtrl.text.trim();
    return Scaffold(
      appBar: AppBar(
        title: const Text('订单列表'),
        actions: [
          IconButton(
            tooltip: '新增订单',
            onPressed: _openCreate,
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
          Row(
            children: [
              TextField(
                controller: _searchCtrl,
                onChanged: _onSearchChanged,
                decoration: appInput(
                  hint: '搜索标题或单号',
                  prefix: const Icon(
                    Icons.search,
                    size: 20,
                    color: AppColors.ink3,
                  ),
                ),
              ).expanded(),
              const SizedBox(width: 10),
              _buildPlatformFilter(),
            ],
          ).padding(left: 16, right: 16, bottom: 8),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                ? EmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: keyword.isEmpty && _platformId == null
                        ? '还没有订单'
                        : '没有匹配的订单',
                    description: '代下单登记后，订单会出现在这里，可左滑补录物流单号。',
                    action: FilledButton(
                      onPressed: _openCreate,
                      child: const Text('新增订单'),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: SlidableAutoCloseBehavior(
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                        itemCount: _items.length,
                        itemBuilder: (context, index) =>
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _buildOrderCard(_items[index]),
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
