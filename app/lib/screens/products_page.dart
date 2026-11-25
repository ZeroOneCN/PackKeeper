import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:styled_widget/styled_widget.dart';

import '../core/app_events.dart';
import '../core/db.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../widgets/common.dart';

/// 商品库：维护商品规格、采购成本与售价，用于订单利润统计。
class ProductsPage extends StatefulWidget {
  const ProductsPage({super.key});

  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage> {
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _specCtrl = TextEditingController();
  final TextEditingController _costCtrl = TextEditingController();
  final TextEditingController _priceCtrl = TextEditingController();
  final TextEditingController _noteCtrl = TextEditingController();

  List<ProductModel> _products = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    dbRevision.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    dbRevision.removeListener(_load);
    _nameCtrl.dispose();
    _specCtrl.dispose();
    _costCtrl.dispose();
    _priceCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  /// 加载商品库。
  Future<void> _load() async {
    final products = await AppDatabase.instance.products();
    if (!mounted) return;
    setState(() {
      _products = products;
      _loading = false;
    });
  }

  /// 金额格式化：保留两位小数并去掉多余的 0。
  String _money(double? value) {
    if (value == null) return '—';
    return value.toStringAsFixed(2);
  }

  /// 新增或编辑商品弹窗。
  ///
  /// 参数：[editing] 传入时为编辑模式，否则为新增模式。
  Future<void> _openDialog({ProductModel? editing}) async {
    final isEdit = editing != null;
    _nameCtrl.text = editing?.name ?? '';
    _specCtrl.text = editing?.spec ?? '';
    _costCtrl.text = editing?.cost == null ? '' : _money(editing!.cost);
    _priceCtrl.text = editing?.price == null ? '' : _money(editing!.price);
    _noteCtrl.text = editing?.note ?? '';
    var showError = false;
    var saving = false;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(isEdit ? '编辑商品' : '添加商品'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _nameCtrl,
                  decoration: appInput(label: '商品名称', hint: '如 保温杯'),
                  onChanged: (_) {
                    if (showError) setDialogState(() => showError = false);
                  },
                ),
                if (showError)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: const Text('请填写商品名称')
                        .fontSize(11)
                        .textColor(AppColors.danger),
                  ).padding(top: 4),
                TextField(
                  controller: _specCtrl,
                  decoration: appInput(label: '规格', hint: '如 500ml 白色，可留空'),
                ).padding(top: 10),
                Row(
                  children: [
                    TextField(
                      controller: _costCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: appInput(label: '采购成本'),
                    ).expanded(),
                    const SizedBox(width: 10),
                    TextField(
                      controller: _priceCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: appInput(label: '售价'),
                    ).expanded(),
                  ],
                ).padding(top: 10),
                TextField(
                  controller: _noteCtrl,
                  decoration: appInput(label: '备注', hint: '供应商、货号等，可留空'),
                ).padding(top: 10),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (_nameCtrl.text.trim().isEmpty) {
                        setDialogState(() => showError = true);
                        return;
                      }
                      setDialogState(() => saving = true);
                      try {
                        if (isEdit) {
                          await AppDatabase.instance.updateProduct(
                            id: editing.id,
                            name: _nameCtrl.text,
                            spec: _specCtrl.text,
                            cost: double.tryParse(_costCtrl.text.trim()),
                            price: double.tryParse(_priceCtrl.text.trim()),
                            note: _noteCtrl.text,
                          );
                        } else {
                          await AppDatabase.instance.addProduct(
                            name: _nameCtrl.text,
                            spec: _specCtrl.text,
                            cost: double.tryParse(_costCtrl.text.trim()),
                            price: double.tryParse(_priceCtrl.text.trim()),
                            note: _noteCtrl.text,
                          );
                        }
                        if (ctx.mounted) Navigator.pop(ctx, true);
                      } catch (_) {
                        if (ctx.mounted) {
                          setDialogState(() => saving = false);
                          showToast(ctx, '保存失败，请重试');
                        }
                      }
                    },
              child: Text(isEdit ? '保存修改' : '保存'),
            ),
          ],
        ),
      ),
    );

    if (saved == true) {
      if (!mounted) return;
      bumpDbRevision();
      showToast(context, isEdit ? '商品已更新' : '商品已添加');
    }
  }

  /// 删除商品（二次确认，已引用该商品的订单会保留并置空商品字段）。
  ///
  /// 参数：[product] 目标商品。
  Future<void> _delete(ProductModel product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除商品'),
        content: Text(
          '确认删除「${product.name}」？已关联该商品的订单会保留，但不再显示商品信息。',
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
    if (confirmed != true) return;
    await AppDatabase.instance.deleteProduct(product.id);
    if (!mounted) return;
    bumpDbRevision();
    showToast(context, '商品已删除');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('商品库'),
        actions: [
          IconButton(
            tooltip: '添加商品',
            onPressed: () => _openDialog(),
            icon: const Icon(Icons.add),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _products.isEmpty
              ? EmptyState(
                  icon: Icons.inventory_2_outlined,
                  title: '还没有商品',
                  description: '登记商品成本与售价后，下单时可直接带出，工作台自动统计利润。',
                  action: FilledButton(
                    onPressed: () => _openDialog(),
                    child: const Text('添加商品'),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: SlidableAutoCloseBehavior(
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      itemCount: _products.length,
                      itemBuilder: (context, index) =>
                          _buildCard(_products[index]),
                    ),
                  ),
                ),
    );
  }

  /// 商品卡片：左滑出现「编辑 / 删除」，按钮与卡片同高贴合，点击卡片不进入编辑。
  /// 商品卡片：左滑出现「编辑 / 删除」，动作按钮裁剪在卡片圆角内，点击卡片不进入编辑。
  Widget _buildCard(ProductModel product) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SlideActionCard(
        slideKey: ValueKey(product.id),
        groupTag: 'products',
        extentRatio: 0.38,
        actions: [
          SlidableAction(
            onPressed: (_) => _openDialog(editing: product),
            backgroundColor: AppColors.brand,
            foregroundColor: Colors.white,
            icon: Icons.edit_outlined,
            label: '编辑',
            labelStyle: const TextStyle(fontSize: 12),
          ),
          SlidableAction(
            onPressed: (_) => _delete(product),
            backgroundColor: AppColors.danger,
            foregroundColor: Colors.white,
            icon: Icons.delete_outline,
            label: '删除',
            labelStyle: const TextStyle(fontSize: 12),
          ),
        ],
        child: AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(product.name)
                    .fontSize(14)
                    .fontWeight(FontWeight.w600)
                    .textColor(AppColors.ink),
                Text(
                  [
                    if (product.spec.isNotEmpty) product.spec,
                    '成本 ¥${_money(product.cost)}',
                    '售价 ¥${_money(product.price)}',
                    if (product.note.isNotEmpty) product.note,
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                )
                    .fontSize(12)
                    .textColor(AppColors.ink3)
                    .padding(top: 3),
              ],
            ).expanded(),
            Text('利润 ¥${_money(product.profit)}')
                .fontSize(12)
                .fontWeight(FontWeight.w600)
                .textColor(product.profit >= 0
                    ? AppColors.brandDeep
                    : AppColors.danger)
                .padding(left: 8)
                .decorated(
                  color: product.profit >= 0
                      ? AppColors.brandSoft
                      : AppColors.dangerSoft,
                  borderRadius: BorderRadius.circular(999),
                )
                .padding(horizontal: 8, vertical: 3),
          ],
        ),
      ),
      ),
    );
  }
}
