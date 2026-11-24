import 'package:flutter/material.dart';
import 'package:styled_widget/styled_widget.dart';

import '../core/app_events.dart';
import '../core/db.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../core/tracking.dart';
import '../widgets/common.dart';
import 'accounts_page.dart';

/// 订单批量录入：按行粘贴物流单号，一次性为同一账号建单。
class BatchOrderPage extends StatefulWidget {
  const BatchOrderPage({super.key});

  @override
  State<BatchOrderPage> createState() => _BatchOrderPageState();
}

class _BatchOrderPageState extends State<BatchOrderPage> {
  final TextEditingController _trackingCtrl = TextEditingController();

  List<AccountView> _accounts = const [];
  String? _accountId;
  OrderRoute _route = OrderRoute.warehouse;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _trackingCtrl.dispose();
    super.dispose();
  }

  /// 加载可选账号。
  Future<void> _load() async {
    final accounts = await AppDatabase.instance.accountViews();
    if (!mounted) return;
    setState(() {
      _accounts = accounts;
      _loading = false;
    });
  }

  /// 选择下单账号。
  Future<void> _pickAccount() async {
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
                '选择下单账号',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _accounts.length,
                itemBuilder: (_, index) {
                  final view = _accounts[index];
                  return ListTile(
                    leading: const SizedBox(width: 8, height: 8).decorated(
                      color: Color(view.platform.color),
                      shape: BoxShape.circle,
                    ),
                    title: Text(view.title),
                    subtitle: view.account.owner.isEmpty
                        ? null
                        : Text('归属 ${view.account.owner}'),
                    trailing: _accountId == view.account.id
                        ? const Icon(Icons.check, color: AppColors.brand, size: 20)
                        : null,
                    onTap: () => Navigator.pop(ctx, view.account.id),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    if (picked != null) setState(() => _accountId = picked);
  }

  /// 逐行创建订单，并汇总成功、重复与无效行数。
  Future<void> _submit() async {
    if (_accountId == null) {
      showToast(context, '请先选择下单账号');
      return;
    }
    final lines = _trackingCtrl.text
        .split(RegExp(r'[\r\n]+'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.isEmpty) {
      showToast(context, '请至少粘贴一行物流单号');
      return;
    }

    setState(() => _saving = true);
    final db = AppDatabase.instance;
    final seen = <String>{};
    var created = 0;
    var duplicated = 0;
    var invalid = 0;
    for (final line in lines) {
      final info = parseTracking(line);
      if (info.normalized.isEmpty) {
        invalid++;
        continue;
      }
      if (!seen.add(info.normalized)) {
        duplicated++;
        continue;
      }
      final exists = await db.orderCountByTracking(info.normalized);
      if (exists > 0) {
        duplicated++;
        continue;
      }
      await db.addOrder(
        accountId: _accountId!,
        trackingNo: info.normalized,
        route: _route,
      );
      created++;
    }
    if (!mounted) return;
    bumpDbRevision();
    setState(() => _saving = false);
    final detail = [
      '成功 $created 笔',
      if (duplicated > 0) '重复 $duplicated 笔',
      if (invalid > 0) '无效 $invalid 行',
    ].join('，');
    showToast(context, '批量录单完成：$detail');
    Navigator.of(context).pop(true);
  }

  /// 履约路径选项卡片。
  ///
  /// 参数：[route] 该卡片代表的路径。
  Widget _buildRouteCard(OrderRoute route) {
    final active = _route == route;
    return AppCard(
      onTap: () => setState(() => _route = route),
      color: active ? AppColors.brandSoft : AppColors.surface,
      borderColor: active ? AppColors.brand : AppColors.line,
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        children: [
          Text(route.label)
              .fontSize(13)
              .fontWeight(FontWeight.w600)
              .textColor(active ? AppColors.brandDeep : AppColors.ink2),
          Text(
            route == OrderRoute.warehouse ? '先入仓再转发' : '平台直接寄给收件人',
          )
              .fontSize(11)
              .textColor(AppColors.ink3)
              .padding(top: 3),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final account = _accounts
        .where((view) => view.account.id == _accountId)
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('批量录单')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _accounts.isEmpty
              ? EmptyState(
                  icon: Icons.badge_outlined,
                  title: '还没有可下单的账号',
                  description: '批量录单需要先有平台账号台账，请先在台账页添加。',
                  action: FilledButton(
                    onPressed: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const AccountsPage()),
                      );
                      _load();
                    },
                    child: const Text('去添加账号'),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                  children: [
                    const SectionHeader(title: '下单账号'),
                    AppCard(
                      onTap: _pickAccount,
                      child: Row(
                        children: [
                          const Icon(Icons.badge_outlined,
                                  size: 20, color: AppColors.brandDeep)
                              .padding(right: 10),
                          Text(
                            account.isEmpty ? '请选择平台账号' : account.first.title,
                          )
                              .fontSize(14)
                              .fontWeight(FontWeight.w500)
                              .textColor(
                                account.isEmpty ? AppColors.ink3 : AppColors.ink,
                              )
                              .expanded(),
                          const Icon(Icons.expand_more,
                              size: 20, color: AppColors.ink3),
                        ],
                      ),
                    ),
                    const SectionHeader(title: '履约路径'),
                    Row(
                      children: [
                        Expanded(child: _buildRouteCard(OrderRoute.warehouse)),
                        const SizedBox(width: 10),
                        Expanded(child: _buildRouteCard(OrderRoute.direct)),
                      ],
                    ),
                    SectionHeader(
                      title: '物流单号',
                      trailing: Text('每行一个')
                          .fontSize(12)
                          .textColor(AppColors.ink3),
                    ),
                    TextField(
                      controller: _trackingCtrl,
                      keyboardType: TextInputType.multiline,
                      textCapitalization: TextCapitalization.characters,
                      minLines: 7,
                      maxLines: 12,
                      decoration: appInput(
                        hint: 'SF1234567890\nJD0123456789\n…',
                      ),
                    ),
                    const Text('重复或已存在订单的单号会自动跳过，不会重复建单。')
                        .fontSize(11)
                        .textColor(AppColors.ink3)
                        .textStyle(const TextStyle(height: 1.5))
                        .padding(top: 8),
                    FilledButton(
                      onPressed: _saving ? null : _submit,
                      child: Text(_saving ? '正在创建…' : '批量创建订单'),
                    ).width(double.infinity).padding(top: 22),
                  ],
                ),
    );
  }
}
