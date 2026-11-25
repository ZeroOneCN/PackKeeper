import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:styled_widget/styled_widget.dart';

import '../core/app_events.dart';
import '../core/db.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import 'assign_sheet.dart';

/// 待认领池：筛选、搜索、多选、批量分配与标记异常。
class InboxPage extends StatefulWidget {
  const InboxPage({super.key});

  @override
  State<InboxPage> createState() => _InboxPageState();
}

class _InboxPageState extends State<InboxPage> {
  final TextEditingController _searchCtrl = TextEditingController();
  final Set<String> _selected = <String>{};

  List<ParcelModel> _items = const [];
  Map<String, String> _accountNames = const {};
  ParcelStatus? _filter;
  bool _loading = true;
  bool _selectionMode = false;
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

  /// 按当前筛选条件与关键词加载包裹列表。
  Future<void> _load() async {
    final db = AppDatabase.instance;
    final items = await db.parcels(status: _filter, keyword: _searchCtrl.text);
    final accounts = await db.accountViews();
    if (!mounted) return;
    setState(() {
      _items = items;
      _accountNames = {
        for (final view in accounts) view.account.id: view.account.alias,
      };
      _loading = false;
      _selected.removeWhere((id) => !items.any((p) => p.id == id));
    });
  }

  /// 搜索输入（300ms 防抖）。
  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _load);
  }

  /// 切换某个包裹的选中状态。
  void _toggle(ParcelModel parcel) {
    setState(() {
      _selectionMode = true;
      if (_selected.contains(parcel.id)) {
        _selected.remove(parcel.id);
      } else {
        _selected.add(parcel.id);
      }
      if (_selected.isEmpty) _selectionMode = false;
    });
  }

  /// 退出多选。
  void _exitSelection() {
    setState(() {
      _selected.clear();
      _selectionMode = false;
    });
  }

  /// 打开分配面板；成功后刷新。
  Future<void> _openAssign(List<String> ids) async {
    if (ids.isEmpty) return;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AssignSheet(parcelIds: ids),
    );
    if (ok == true) {
      _exitSelection();
      bumpDbRevision();
    }
  }

  /// 标记异常件并刷新。
  Future<void> _markException() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('标记为异常件'),
        content: Text('确认将选中的 ${_selected.length} 件包裹标记为异常件？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认标记'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await AppDatabase.instance.markException(_selected.toList());
    if (!mounted) return;
    showToast(context, '已标记 ${_selected.length} 件异常件');
    _exitSelection();
    bumpDbRevision();
  }

  /// 删除一条误扫包裹（二次确认）。
  ///
  /// 参数：[parcel] 目标包裹。
  Future<void> _deleteParcel(ParcelModel parcel) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除包裹'),
        content: Text('确认从待认领池删除运单 ${parcel.trackingNo}？删除后不可恢复。'),
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
    if (confirmed != true) return;
    await AppDatabase.instance.deleteParcel(parcel.id);
    if (!mounted) return;
    setState(() => _selected.remove(parcel.id));
    showToast(context, '已删除 ${parcel.trackingNo}');
    bumpDbRevision();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('待认领池'),
        actions: [
          if (_selectionMode)
            TextButton(onPressed: _exitSelection, child: const Text('取消'))
          else
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
              hint: '搜索运单号',
              prefix: const Icon(Icons.search, size: 20, color: AppColors.ink3),
              suffix: _searchCtrl.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        _searchCtrl.clear();
                        _load();
                        setState(() {});
                      },
                    ),
            ),
          ).padding(left: 16, right: 16, bottom: 8),
          ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              _buildFilterChip('全部', null),
              _buildFilterChip('待认领', ParcelStatus.pending),
              _buildFilterChip('已分配', ParcelStatus.assigned),
              _buildFilterChip('异常件', ParcelStatus.exception),
            ],
          ).height(40),
          const SizedBox(height: 4),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                    ? EmptyState(
                        icon: Icons.inbox_outlined,
                        title: _searchCtrl.text.isEmpty ? '暂无包裹' : '没有匹配的包裹',
                        description: '扫码入库或拍照识别后，包裹会出现在这里等待认领。',
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: SlidableAutoCloseBehavior(
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                            itemCount: _items.length,
                            itemBuilder: (context, index) =>
                                _buildItem(_items[index]),
                          ),
                        ),
                      ),
          ),
        ],
      ),
      bottomNavigationBar: _selectionMode ? _buildSelectionBar() : null,
    );
  }

  /// 状态筛选标签。
  Widget _buildFilterChip(String label, ParcelStatus? status) {
    final active = _filter == status;
    return Text(label)
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
          setState(() => _filter = status);
          _loading = true;
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

  /// 单个包裹卡片：左滑出现「删除」，动作按钮裁剪在卡片圆角内。
  Widget _buildItem(ParcelModel parcel) {
    final selected = _selected.contains(parcel.id);
    final accountName = parcel.accountId == null
        ? ''
        : _accountNames[parcel.accountId!] ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SlideActionCard(
        slideKey: ValueKey(parcel.id),
        groupTag: 'inbox',
        extentRatio: 0.24,
        actions: [
          SlidableAction(
            onPressed: (_) => _deleteParcel(parcel),
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
        borderColor: selected ? AppColors.brand : AppColors.line,
        onTap: () => _toggle(parcel),
        child: Row(
          children: [
            if (_selectionMode)
              Icon(
                selected ? Icons.check_circle : Icons.circle_outlined,
                size: 20,
                color: selected ? AppColors.brand : AppColors.ink3,
              ).padding(right: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(parcel.trackingNo)
                    .fontSize(14)
                    .fontWeight(FontWeight.w600)
                    .textColor(AppColors.ink)
                    .letterSpacing(0.3),
                Text(
                  [
                    parcel.carrier.isEmpty ? '未知快递' : parcel.carrier,
                    parcel.source.label,
                    formatTime(parcel.scannedAt),
                    if (accountName.isNotEmpty) accountName,
                  ].join(' · '),
                ).fontSize(12).textColor(AppColors.ink3).padding(top: 4),
                if (parcel.receiverTail.isNotEmpty)
                  Text('收件人尾号 ${parcel.receiverTail}')
                      .fontSize(11)
                      .textColor(AppColors.ink3)
                      .padding(top: 2),
              ],
            ).expanded(),
            StatusChip(status: parcel.status, dense: true),
          ],
        ),
      ),
      ),
    );
  }

  /// 多选状态下的底部操作栏。
  Widget _buildSelectionBar() {
    return Row(
      children: [
        Text('已选 ${_selected.length} 件')
            .fontSize(13)
            .fontWeight(FontWeight.w600)
            .textColor(AppColors.ink),
        const SizedBox(width: 12),
        TextButton(
          onPressed: _markException,
          style: TextButton.styleFrom(
            foregroundColor: AppColors.danger,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: const Size(0, 44),
          ),
          child: const Text('标记异常', maxLines: 1, softWrap: false),
        ).expanded(),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: () => _openAssign(_selected.toList()),
          child: const Text('分配归属', maxLines: 1, softWrap: false),
        ).expanded(),
      ],
    )
        .padding(left: 16, top: 10, right: 16, bottom: 10)
        .safeArea(top: false)
        .decorated(
          color: AppColors.surface,
          border: const Border(top: BorderSide(color: AppColors.line)),
        );
  }
}
