import 'package:flutter/material.dart';
import 'package:styled_widget/styled_widget.dart';

import '../core/app_events.dart';
import '../core/db.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import 'accounts_page.dart';
import 'batch_order_page.dart';

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
  final TextEditingController _costCtrl = TextEditingController();

  List<AccountView> _accounts = const [];
  List<ProductModel> _products = const [];
  String? _accountId;
  String? _productId;
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
    _titleCtrl.dispose();
    _orderNoCtrl.dispose();
    _amountCtrl.dispose();
    _addressCtrl.dispose();
    _trackingCtrl.dispose();
    _costCtrl.dispose();
    super.dispose();
  }

  /// 加载可选账号与商品。
  Future<void> _load() async {
    final accounts = await AppDatabase.instance.accountViews();
    final products = await AppDatabase.instance.products();
    if (!mounted) return;
    setState(() {
      _accounts = accounts;
      _products = products;
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
                    leading: const SizedBox(width: 8, height: 8).decorated(
                      color: Color(view.platform.color),
                      shape: BoxShape.circle,
                    ),
                    title: Text(view.title),
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

  /// 选择关联商品；选中后带出标题、成本与售价（已填写的内容不覆盖）。
  Future<void> _pickProduct() async {
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
                '选择商品',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  ListTile(
                    leading: const Icon(Icons.block, size: 20, color: AppColors.ink3),
                    title: const Text('不关联商品'),
                    trailing: _productId == null
                        ? const Icon(Icons.check, color: AppColors.brand, size: 20)
                        : null,
                    onTap: () => Navigator.pop(ctx, ''),
                  ),
                  for (final product in _products)
                    ListTile(
                      leading: const Icon(
                        Icons.inventory_2_outlined,
                        size: 20,
                        color: AppColors.brandDeep,
                      ),
                      title: Text(product.name),
                      subtitle: Text(
                        [
                          if (product.spec.isNotEmpty) product.spec,
                          '成本 ¥${product.cost?.toStringAsFixed(2) ?? '—'}',
                          '售价 ¥${product.price?.toStringAsFixed(2) ?? '—'}',
                        ].join(' · '),
                      ),
                      trailing: _productId == product.id
                          ? const Icon(Icons.check, color: AppColors.brand, size: 20)
                          : null,
                      onTap: () => Navigator.pop(ctx, product.id),
                    ),
                  if (_products.isEmpty)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: Text(
                        '商品库为空，可先在「工作概览 → 商品库」添加。',
                        style: TextStyle(fontSize: 12, color: AppColors.ink3),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    setState(() {
      _productId = picked.isEmpty ? null : picked;
      if (_productId != null) {
        final product = _products.firstWhere((p) => p.id == _productId);
        if (_titleCtrl.text.trim().isEmpty) _titleCtrl.text = product.name;
        if (_costCtrl.text.trim().isEmpty && product.cost != null) {
          _costCtrl.text = product.cost!.toStringAsFixed(2);
        }
        if (_amountCtrl.text.trim().isEmpty && product.price != null) {
          _amountCtrl.text = product.price!.toStringAsFixed(2);
        }
      }
    });
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
      productId: _productId,
      cost: double.tryParse(_costCtrl.text.trim()),
      route: _route,
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
    final product =
        _products.where((item) => item.id == _productId).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('代下单登记'),
        actions: [
          IconButton(
            tooltip: '批量录单',
            onPressed: () async {
              final done = await Navigator.of(context).push<bool>(
                MaterialPageRoute(builder: (_) => const BatchOrderPage()),
              );
              if (done == true && context.mounted) _load();
            },
            icon: const Icon(Icons.playlist_add),
          ),
          const SizedBox(width: 4),
        ],
      ),
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
                                  size: 20, color: AppColors.brandDeep)
                              .padding(right: 10),
                          Text(
                            account.isEmpty ? '请选择平台账号' : account.first.title,
                          )
                              .fontSize(14)
                              .fontWeight(FontWeight.w500)
                              .textColor(account.isEmpty
                                  ? AppColors.ink3
                                  : AppColors.ink)
                              .expanded(),
                          const Icon(Icons.expand_more,
                              size: 20, color: AppColors.ink3),
                        ],
                      ),
                    ),
                    const SectionHeader(title: '关联商品'),
                    AppCard(
                      onTap: _pickProduct,
                      child: Row(
                        children: [
                          const Icon(Icons.inventory_2_outlined,
                                  size: 20, color: AppColors.brandDeep)
                              .padding(right: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                product.isEmpty ? '不关联商品' : product.first.name,
                              )
                                  .fontSize(14)
                                  .fontWeight(FontWeight.w500)
                                  .textColor(product.isEmpty
                                      ? AppColors.ink3
                                      : AppColors.ink),
                              if (product.isNotEmpty)
                                Text(
                                  [
                                    if (product.first.spec.isNotEmpty)
                                      product.first.spec,
                                    '成本 ¥${product.first.cost?.toStringAsFixed(2) ?? '—'}',
                                    '售价 ¥${product.first.price?.toStringAsFixed(2) ?? '—'}',
                                  ].join(' · '),
                                )
                                    .fontSize(11)
                                    .textColor(AppColors.ink3)
                                    .padding(top: 2),
                            ],
                          ).expanded(),
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
                    const SectionHeader(title: '商品与订单'),
                    TextField(
                      controller: _titleCtrl,
                      decoration: appInput(
                        label: '商品标题',
                        hint: '便于后续按商品反查包裹',
                      ),
                    ),
                    Row(
                      children: [
                        TextField(
                          controller: _orderNoCtrl,
                          decoration: appInput(label: '平台订单号', hint: '可留空'),
                        ).expanded(),
                        const SizedBox(width: 10),
                        TextField(
                          controller: _amountCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: appInput(label: '金额（元）', hint: '仅记录'),
                        ).expanded(),
                      ],
                    ).padding(top: 10),
                    TextField(
                      controller: _costCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration: appInput(
                        label: '采购成本（元）',
                        hint: '用于利润统计，可留空',
                      ),
                    ).padding(top: 10),
                    TextField(
                      controller: _addressCtrl,
                      maxLines: 2,
                      decoration: appInput(
                        label: '收货地址',
                        hint: '第三方仓库或收件地址',
                      ),
                    ).padding(top: 10),
                    const SectionHeader(title: '物流单号'),
                    TextField(
                      controller: _trackingCtrl,
                      textCapitalization: TextCapitalization.characters,
                      decoration: appInput(
                        label: '物流单号',
                        hint: '平台发货后复制或扫码填入，可留空',
                      ),
                    ),
                    const Text('填入的单号如果已经存在包裹，会自动建立归属；否则会在包裹到货扫码时自动合并。')
                        .fontSize(11)
                        .textColor(AppColors.ink3)
                        .textStyle(const TextStyle(height: 1.5))
                        .padding(top: 8),
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      child: Text(_saving ? '保存中…' : '保存订单'),
                    ).width(double.infinity).padding(top: 22),
                  ],
                ),
    );
  }
}
