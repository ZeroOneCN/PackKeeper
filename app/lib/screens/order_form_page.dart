import 'package:flutter/material.dart';

import '../core/app_events.dart';
import '../core/db.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import 'accounts_page.dart';

/// 代下单登记：先建订单，物流单号可在平台下单后补录。
class OrderFormPage extends StatefulWidget {
  const OrderFormPage({super.key});

  @override
  State<OrderFormPage> createState() => _OrderFormPageState();
}

class _OrderFormPageState extends State<OrderFormPage> {
  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _orderNoCtrl = TextEditingController();
  final TextEditingController _amountCtrl = TextEditingController();
  final TextEditingController _addressCtrl = TextEditingController();
  final TextEditingController _trackingCtrl = TextEditingController();

  List<AccountView> _accounts = const [];
  String? _accountId;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _orderNoCtrl.dispose();
    _amountCtrl.dispose();
    _addressCtrl.dispose();
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

  /// 选择归属账号。
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
                    leading: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: Color(view.platform.color),
                        shape: BoxShape.circle,
                      ),
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

  /// 保存订单；若单号已存在包裹则自动关联。
  Future<void> _save() async {
    if (_accountId == null) {
      showToast(context, '请先选择下单账号');
      return;
    }
    setState(() => _saving = true);
    final db = AppDatabase.instance;
    final tracking = _trackingCtrl.text.trim();
    ParcelModel? existing;
    if (tracking.isNotEmpty) {
      existing = await db.findByTracking(tracking);
    }
    await db.addOrder(
      accountId: _accountId!,
      title: _titleCtrl.text,
      amount: double.tryParse(_amountCtrl.text.trim()),
      platformOrderNo: _orderNoCtrl.text,
      addressText: _addressCtrl.text,
      trackingNo: tracking,
    );
    if (!mounted) return;
    bumpDbRevision();
    setState(() => _saving = false);
    showToast(
      context,
      existing != null
          ? '订单已创建，并自动关联到已入库包裹'
          : tracking.isEmpty
              ? '订单已创建，可稍后补录物流单号'
              : '订单已创建，包裹到货扫码后自动合并',
    );
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final account = _accounts
        .where((view) => view.account.id == _accountId)
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('代下单登记')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _accounts.isEmpty
              ? EmptyState(
                  icon: Icons.badge_outlined,
                  title: '还没有可下单的账号',
                  description: '代下单需要先有平台账号台账，请先在台账页添加。',
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
                              size: 20, color: AppColors.brandDeep),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              account.isEmpty ? '请选择平台账号' : account.first.title,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: account.isEmpty
                                    ? AppColors.ink3
                                    : AppColors.ink,
                              ),
                            ),
                          ),
                          const Icon(Icons.expand_more,
                              size: 20, color: AppColors.ink3),
                        ],
                      ),
                    ),
                    const SectionHeader(title: '商品与订单'),
                    TextField(
                      controller: _titleCtrl,
                      decoration: appInput(
                        label: '商品标题',
                        hint: '便于后续按商品反查包裹',
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _orderNoCtrl,
                            decoration: appInput(label: '平台订单号', hint: '可留空'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _amountCtrl,
                            keyboardType:
                                const TextInputType.numberWithOptions(decimal: true),
                            decoration: appInput(label: '金额（元）', hint: '仅记录'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _addressCtrl,
                      maxLines: 2,
                      decoration: appInput(
                        label: '收货地址',
                        hint: '第三方仓库或收件地址',
                      ),
                    ),
                    const SectionHeader(title: '物流单号'),
                    TextField(
                      controller: _trackingCtrl,
                      textCapitalization: TextCapitalization.characters,
                      decoration: appInput(
                        label: '物流单号',
                        hint: '平台发货后复制或扫码填入，可留空',
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '填入的单号如果已经存在包裹，会自动建立归属；否则会在包裹到货扫码时自动合并。',
                      style: TextStyle(fontSize: 11, color: AppColors.ink3, height: 1.5),
                    ),
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _saving ? null : _save,
                        child: Text(_saving ? '保存中…' : '保存订单'),
                      ),
                    ),
                  ],
                ),
    );
  }
}
