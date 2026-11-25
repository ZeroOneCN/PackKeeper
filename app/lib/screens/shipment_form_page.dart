import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:styled_widget/styled_widget.dart';

import '../core/app_events.dart';
import '../core/db.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../widgets/common.dart';

/// 新建/编辑转寄批次：填写快递费，并在新建时勾选本次寄出的包裹。
class ShipmentFormPage extends StatefulWidget {
  const ShipmentFormPage({super.key, this.editing});

  /// 传入时为编辑模式，仅修改基础信息；为空表示新建并选择包裹。
  final ShipmentView? editing;

  @override
  State<ShipmentFormPage> createState() => _ShipmentFormPageState();
}

class _ShipmentFormPageState extends State<ShipmentFormPage> {
  final TextEditingController _carrierCtrl = TextEditingController();
  final TextEditingController _trackingCtrl = TextEditingController();
  final TextEditingController _feeCtrl = TextEditingController();
  final TextEditingController _noteCtrl = TextEditingController();

  late DateTime _shippedAt;
  List<ParcelModel> _candidates = const [];
  final Set<String> _selected = {};

  /// 编辑模式下批次原有的包裹，用于计算追加/移出。
  Set<String> _initialSelected = {};
  bool _loading = true;
  bool _saving = false;

  bool get _isEdit => widget.editing != null;

  @override
  void initState() {
    super.initState();
    final shipment = widget.editing?.shipment;
    _carrierCtrl.text = shipment?.carrier ?? '';
    _trackingCtrl.text = shipment?.trackingNo ?? '';
    _feeCtrl.text = shipment == null ? '' : shipment.fee.toStringAsFixed(2);
    _noteCtrl.text = shipment?.note ?? '';
    _shippedAt = shipment == null
        ? DateTime.now()
        : DateTime.fromMillisecondsSinceEpoch(shipment.shippedAt);
    _load();
  }

  @override
  void dispose() {
    _carrierCtrl.dispose();
    _trackingCtrl.dispose();
    _feeCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  /// 加载候选包裹：编辑模式包含批次原有包裹，其余为可加入包裹。
  Future<void> _load() async {
    if (_isEdit) {
      final current = await AppDatabase.instance.shipmentParcels(
        widget.editing!.shipment.id,
      );
      final others = await AppDatabase.instance.shipableParcels();
      if (!mounted) return;
      setState(() {
        _candidates = [...current, ...others];
        _selected
          ..clear()
          ..addAll(current.map((p) => p.id));
        _initialSelected = current.map((p) => p.id).toSet();
        _loading = false;
      });
      return;
    }
    final parcels = await AppDatabase.instance.shipableParcels();
    if (!mounted) return;
    setState(() {
      _candidates = parcels;
      _loading = false;
    });
  }

  /// 选择寄出日期。
  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _shippedAt,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      helpText: '选择寄出日期',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _shippedAt = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _shippedAt.hour,
        _shippedAt.minute,
      );
    });
  }

  /// 保存批次：新建要求至少勾选一个包裹。
  Future<void> _save() async {
    final feeText = _feeCtrl.text.trim();
    final fee = double.tryParse(feeText.isEmpty ? '0' : feeText);
    if (fee == null || fee < 0) {
      showToast(context, '请填写正确的快递费');
      return;
    }
    if (_selected.isEmpty) {
      showToast(context, '请至少选择一个包裹');
      return;
    }
    setState(() => _saving = true);
    try {
      if (_isEdit) {
        final id = widget.editing!.shipment.id;
        await AppDatabase.instance.updateShipment(
          id: id,
          carrier: _carrierCtrl.text,
          trackingNo: _trackingCtrl.text,
          fee: fee,
          shippedAt: _shippedAt.millisecondsSinceEpoch,
          note: _noteCtrl.text,
        );
        await AppDatabase.instance.setShipmentParcels(
          shipmentId: id,
          addIds: _selected.difference(_initialSelected).toList(),
          removeIds: _initialSelected.difference(_selected).toList(),
        );
      } else {
        await AppDatabase.instance.addShipment(
          carrier: _carrierCtrl.text,
          trackingNo: _trackingCtrl.text,
          fee: fee,
          shippedAt: _shippedAt.millisecondsSinceEpoch,
          note: _noteCtrl.text,
          parcelIds: _selected.toList(),
        );
      }
      if (!mounted) return;
      bumpDbRevision();
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      showToast(context, '保存失败，请重试');
    }
  }

  /// 日期展示文案。
  String get _dateLabel {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${_shippedAt.year}-${two(_shippedAt.month)}-${two(_shippedAt.day)}';
  }

  /// 表单输入项。
  Widget _buildFields() {
    return Column(
      children: [
        TextField(
          controller: _carrierCtrl,
          decoration: appInput(label: '快递公司', hint: '如 顺丰 / 中通 / 韵达'),
        ),
        TextField(
          controller: _trackingCtrl,
          textCapitalization: TextCapitalization.characters,
          decoration: appInput(label: '运单号', hint: '本次寄件的快递单号，可留空'),
        ).padding(top: 10),
        TextField(
          controller: _feeCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
          decoration: appInput(label: '快递费（元）', hint: '这一单快递的总费用'),
        ).padding(top: 10),
        InputDecorator(
              decoration: appInput(label: '寄出日期'),
              child: Row(
                children: [
                  Text(_dateLabel).fontSize(14).textColor(AppColors.ink).expanded(),
                  const Icon(
                    Icons.calendar_today_outlined,
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
            .gestures(onTap: _saving ? null : _pickDate)
            .padding(top: 10),
        TextField(
          controller: _noteCtrl,
          decoration: appInput(label: '备注', hint: '如 上家批次、件数说明'),
        ).padding(top: 10),
      ],
    );
  }

  /// 包裹勾选列表：新建时选包裹，编辑时可追加或移出。
  Widget _buildParcelPicker() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator()).padding(
        vertical: 24,
      );
    }
    if (_candidates.isEmpty) {
      return const Text('暂无可转寄的包裹（待认领、已分配、已入库且未寄出的包裹可加入批次）')
          .fontSize(12)
          .textColor(AppColors.ink3)
          .padding(vertical: 16);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('选择本次寄出的包裹').fontSize(14).fontWeight(FontWeight.w600),
            const Spacer(),
            TextButton(
              onPressed: () => setState(() {
                if (_selected.length == _candidates.length) {
                  _selected.clear();
                } else {
                  _selected
                    ..clear()
                    ..addAll(_candidates.map((p) => p.id));
                }
              }),
              child: Text(
                _selected.length == _candidates.length ? '清空' : '全选',
              ),
            ),
          ],
        ).padding(top: 18, bottom: 4),
        for (final parcel in _candidates)
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: CheckboxListTile(
              value: _selected.contains(parcel.id),
              onChanged: _saving
                  ? null
                  : (checked) => setState(() {
                      if (checked == true) {
                        _selected.add(parcel.id);
                      } else {
                        _selected.remove(parcel.id);
                      }
                    }),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(parcel.trackingNo)
                  .fontSize(13)
                  .fontWeight(FontWeight.w600)
                  .textColor(AppColors.ink),
              subtitle: Text(
                [
                  parcel.carrier.isEmpty ? '未知快递' : parcel.carrier,
                  parcel.status.label,
                  if (_initialSelected.contains(parcel.id)) '已在本批次',
                ].join(' · '),
              ).fontSize(11).textColor(AppColors.ink3),
            ),
          ).padding(bottom: 6),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? '编辑转寄批次' : '新建转寄批次')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                _buildFields(),
                _buildParcelPicker(),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? '保存中…' : '保存批次'),
                ),
              ],
            ),
    );
  }
}
