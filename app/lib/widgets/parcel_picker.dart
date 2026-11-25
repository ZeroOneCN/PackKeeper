import 'package:flutter/material.dart';
import 'package:styled_widget/styled_widget.dart';

import '../core/db.dart';
import '../core/models.dart';
import '../core/theme.dart';
import 'common.dart';

/// 弹出待认领池选择器，返回选中的包裹。
///
/// 仅列出尚未关联订单的包裹，供订单补单号时直接挑选。
Future<ParcelModel?> showParcelPicker(BuildContext context) {
  return showModalBottomSheet<ParcelModel>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const ParcelPickerSheet(),
  );
}

/// 待认领池选择面板：支持按单号/快递搜索。
class ParcelPickerSheet extends StatefulWidget {
  const ParcelPickerSheet({super.key});

  @override
  State<ParcelPickerSheet> createState() => _ParcelPickerSheetState();
}

class _ParcelPickerSheetState extends State<ParcelPickerSheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  List<ParcelModel> _items = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// 按关键词加载可绑定包裹。
  Future<void> _load() async {
    final items = await AppDatabase.instance.unboundParcels(
      keyword: _searchCtrl.text,
    );
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.62,
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '从待认领池选择',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              TextField(
                controller: _searchCtrl,
                onChanged: (_) => _load(),
                decoration: appInput(
                  hint: '搜索运单号或快递公司',
                  prefix: const Icon(
                    Icons.search,
                    size: 20,
                    color: AppColors.ink3,
                  ),
                ),
              ).padding(horizontal: 16, vertical: 8),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _items.isEmpty
                    ? const Center(
                        child: Text(
                          '没有可绑定单号的包裹',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.ink3,
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        itemCount: _items.length,
                        itemBuilder: (context, index) {
                          final parcel = _items[index];
                          return AppCard(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 4,
                            ),
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(parcel.trackingNo)
                                  .fontSize(13)
                                  .fontWeight(FontWeight.w600),
                              subtitle: Text(
                                '${parcel.carrier.isEmpty ? '未知快递' : parcel.carrier}'
                                ' · ${parcel.status.label}',
                              ).fontSize(11).textColor(AppColors.ink3),
                              trailing: const Icon(
                                Icons.chevron_right,
                                size: 18,
                                color: AppColors.ink3,
                              ),
                              onTap: () => Navigator.pop(context, parcel),
                            ),
                          ).padding(bottom: 8);
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
