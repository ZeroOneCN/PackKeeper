import 'package:flutter/material.dart';
import 'package:styled_widget/styled_widget.dart';

import '../core/db.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import 'shipment_form_page.dart';

/// 转寄批次详情：查看本批次包裹及关联的商品订单。
class ShipmentDetailPage extends StatefulWidget {
  const ShipmentDetailPage({super.key, required this.view});

  final ShipmentView view;

  @override
  State<ShipmentDetailPage> createState() => _ShipmentDetailPageState();
}

class _ShipmentDetailPageState extends State<ShipmentDetailPage> {
  late ShipmentView _view = widget.view;
  List<ShipmentParcelView> _items = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// 加载批次内包裹与关联订单。
  Future<void> _load() async {
    final list = await AppDatabase.instance.shipments();
    final items = await AppDatabase.instance.shipmentParcelViews(
      _view.shipment.id,
    );
    if (!mounted) return;
    setState(() {
      final matched = list.where((e) => e.shipment.id == _view.shipment.id);
      if (matched.isNotEmpty) _view = matched.first;
      _items = items;
      _loading = false;
    });
  }

  /// 打开编辑页，保存后重新加载。
  Future<void> _edit() async {
    final done = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ShipmentFormPage(editing: _view),
      ),
    );
    if (done == true) _load();
  }

  /// 日期展示文案。
  String _date(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }

  /// 批次概要卡片。
  Widget _buildSummary() {
    final shipment = _view.shipment;
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
                  ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    shipment.trackingNo.isEmpty ? '未填写运单号' : shipment.trackingNo,
                  ).fontSize(14).fontWeight(FontWeight.w600),
                  Text(
                    '${_view.parcelCount} 件包裹 · ${_view.orderCount} 个订单 · '
                    '${_date(shipment.shippedAt)}',
                  ).fontSize(11).textColor(AppColors.ink3).padding(top: 3),
                ],
              ).expanded(),
              Text('¥${shipment.fee.toStringAsFixed(2)}')
                  .fontSize(16)
                  .fontWeight(FontWeight.w700),
            ],
          ),
          if (shipment.note.isNotEmpty)
            Text('备注：${shipment.note}')
                .fontSize(12)
                .textColor(AppColors.ink3)
                .padding(top: 10),
        ],
      ),
    );
  }

  /// 单个包裹卡片：单号 + 关联订单信息。
  Widget _buildParcelCard(ShipmentParcelView item) {
    final parcel = item.parcel;
    final hasOrder = item.orderTitle.isNotEmpty;
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                hasOrder ? Icons.receipt_long_outlined : Icons.inventory_2_outlined,
                size: 16,
                color: hasOrder ? AppColors.brandDeep : AppColors.ink3,
              ),
              const SizedBox(width: 6),
              Text(parcel.trackingNo)
                  .fontSize(13)
                  .fontWeight(FontWeight.w600)
                  .expanded(),
              if (item.amount != null)
                Text('¥${item.amount!.toStringAsFixed(2)}')
                    .fontSize(13)
                    .fontWeight(FontWeight.w600),
            ],
          ),
          Text(
            hasOrder ? item.orderTitle : '未关联订单（仅单号）',
          ).fontSize(12).textColor(hasOrder ? AppColors.ink : AppColors.ink3).padding(top: 6),
          Text(
            [
              parcel.carrier.isEmpty ? '未知快递' : parcel.carrier,
              parcel.status.label,
              if (hasOrder) item.accountTitle,
            ].join(' · '),
          ).fontSize(11).textColor(AppColors.ink3).padding(top: 3),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('批次详情'),
        actions: [
          IconButton(
            tooltip: '编辑批次',
            onPressed: _edit,
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  _buildSummary(),
                  const Text('本批次包裹')
                      .fontSize(13)
                      .fontWeight(FontWeight.w600)
                      .padding(top: 18, bottom: 8),
                  if (_items.isEmpty)
                    const Text('本批次暂无包裹')
                        .fontSize(12)
                        .textColor(AppColors.ink3)
                        .padding(vertical: 12)
                  else
                    for (final item in _items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _buildParcelCard(item),
                      ),
                ],
              ),
            ),
    );
  }
}
