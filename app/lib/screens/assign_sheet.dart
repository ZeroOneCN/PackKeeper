import 'package:flutter/material.dart';

import '../core/app_events.dart';
import '../core/db.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../widgets/common.dart';

/// 分配归属面板：按平台分组选择账号，批量分配包裹。
class AssignSheet extends StatefulWidget {
  const AssignSheet({super.key, required this.parcelIds});

  /// 待分配的包裹主键列表。
  final List<String> parcelIds;

  @override
  State<AssignSheet> createState() => _AssignSheetState();
}

class _AssignSheetState extends State<AssignSheet> {
  List<AccountView> _accounts = const [];
  String? _pickedAccountId;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// 加载账号台账。
  Future<void> _load() async {
    final accounts = await AppDatabase.instance.accountViews();
    if (!mounted) return;
    setState(() {
      _accounts = accounts;
      _loading = false;
    });
  }

  /// 执行批量分配。
  Future<void> _submit() async {
    final accountId = _pickedAccountId;
    if (accountId == null) return;
    setState(() => _saving = true);
    await AppDatabase.instance.assignParcels(widget.parcelIds, accountId);
    if (!mounted) return;
    bumpDbRevision();
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<AccountView>>{};
    final platformNames = <String, String>{};
    for (final view in _accounts) {
      grouped.putIfAbsent(view.platform.id, () => []).add(view);
      platformNames[view.platform.id] = view.platform.name;
    }

    return Container(
      height: MediaQuery.sizeOf(context).height * 0.72,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.line,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 12, 6),
            child: Row(
              children: [
                const Text(
                  '分配归属',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${widget.parcelIds.length} 件',
                  style: const TextStyle(fontSize: 12, color: AppColors.ink3),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  icon: const Icon(Icons.close, size: 20),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _accounts.isEmpty
                    ? EmptyState(
                        icon: Icons.badge_outlined,
                        title: '还没有平台账号',
                        description: '请先在「台账」页添加平台账号，再回来分配包裹。',
                        action: FilledButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: const Text('知道了'),
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                        children: [
                          for (final entry in grouped.entries) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
                              child: Text(
                                platformNames[entry.key] ?? '',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.ink3,
                                ),
                              ),
                            ),
                            for (final view in entry.value)
                              _buildAccountRow(view),
                          ],
                        ],
                      ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.line)),
            ),
            child: SafeArea(
              top: false,
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: (_pickedAccountId == null || _saving) ? null : _submit,
                  child: Text(
                    _pickedAccountId == null ? '请选择账号' : '确认分配',
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 单个账号选项。
  Widget _buildAccountRow(AccountView view) {
    final picked = _pickedAccountId == view.account.id;
    final color = Color(view.platform.color);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        borderColor: picked ? AppColors.brand : AppColors.line,
        color: picked ? AppColors.brandSoft : AppColors.surface,
        onTap: () => setState(() => _pickedAccountId = view.account.id),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    view.account.alias,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                  if (view.account.owner.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      '归属人 ${view.account.owner}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.ink3,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Icon(
              picked ? Icons.check_circle : Icons.circle_outlined,
              size: 20,
              color: picked ? AppColors.brand : AppColors.ink3,
            ),
          ],
        ),
      ),
    );
  }
}
