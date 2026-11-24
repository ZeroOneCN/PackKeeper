import 'package:flutter/material.dart';

import '../core/app_events.dart';
import '../core/db.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../widgets/common.dart';

/// 平台配色候选，新增平台时按序取色。
const _palette = <int>[
  0xFFFF5000,
  0xFFE02E24,
  0xFFE1251B,
  0xFFFF6A00,
  0xFF161823,
  0xFFFF2442,
  0xFF0BA85C,
  0xFF2563EB,
  0xFF6D28D9,
  0xFF64748B,
];

/// 账号台账：平台筛选、账号检索、新增平台与账号。
class AccountsPage extends StatefulWidget {
  const AccountsPage({super.key});

  @override
  State<AccountsPage> createState() => _AccountsPageState();
}

class _AccountsPageState extends State<AccountsPage> {
  final TextEditingController _searchCtrl = TextEditingController();
  List<ShopPlatform> _platforms = const [];
  List<AccountView> _accounts = const [];
  String? _platformId;
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
    _searchCtrl.dispose();
    super.dispose();
  }

  /// 加载平台与账号。
  Future<void> _load() async {
    final db = AppDatabase.instance;
    final platforms = await db.platforms();
    final accounts = await db.accountViews(
      platformId: _platformId,
      keyword: _searchCtrl.text,
    );
    if (!mounted) return;
    setState(() {
      _platforms = platforms;
      _accounts = accounts;
      _loading = false;
    });
  }

  /// 新增账号弹窗。
  Future<void> _addAccount() async {
    if (_platforms.isEmpty) {
      showToast(context, '请先添加一个平台');
      return;
    }
    final aliasCtrl = TextEditingController();
    final ownerCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    var platformId = _platformId ?? _platforms.first.id;
    var showError = false;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final platformName = _platforms
              .firstWhere((p) => p.id == platformId,
                  orElse: () => _platforms.first)
              .name;
          return AlertDialog(
            title: const Text('添加账号'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () async {
                      final picked = await _pickPlatform(ctx);
                      if (picked != null) {
                        setDialogState(() => platformId = picked);
                      }
                    },
                    child: InputDecorator(
                      decoration: appInput(label: '所属平台'),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              platformName,
                              style: const TextStyle(
                                fontSize: 14,
                                color: AppColors.ink,
                              ),
                            ),
                          ),
                          const Icon(Icons.expand_more,
                              size: 20, color: AppColors.ink3),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: aliasCtrl,
                    decoration: appInput(
                      label: '账号别名',
                      hint: '如 小王-淘宝1号',
                    ),
                    onChanged: (_) {
                      if (showError) setDialogState(() => showError = false);
                    },
                  ),
                  if (showError) ...[
                    const SizedBox(height: 4),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '请填写账号别名',
                        style: TextStyle(fontSize: 11, color: AppColors.danger),
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  TextField(
                    controller: ownerCtrl,
                    decoration: appInput(label: '归属员工', hint: '可留空'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: noteCtrl,
                    decoration: appInput(label: '备注', hint: '手机号尾号等线索'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () {
                  if (aliasCtrl.text.trim().isEmpty) {
                    setDialogState(() => showError = true);
                    return;
                  }
                  Navigator.pop(ctx, true);
                },
                child: const Text('保存'),
              ),
            ],
          );
        },
      ),
    );

    if (saved == true) {
      await AppDatabase.instance.addAccount(
        platformId: platformId,
        alias: aliasCtrl.text,
        owner: ownerCtrl.text,
        note: noteCtrl.text,
      );
      if (!mounted) return;
      bumpDbRevision();
      showToast(context, '账号已添加');
    }
    aliasCtrl.dispose();
    ownerCtrl.dispose();
    noteCtrl.dispose();
  }

  /// 平台选择底部弹层。
  Future<String?> _pickPlatform(BuildContext context) {
    return showModalBottomSheet<String>(
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
                '选择平台',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final platform in _platforms)
                    ListTile(
                      leading: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: Color(platform.color),
                          shape: BoxShape.circle,
                        ),
                      ),
                      title: Text(platform.name),
                      onTap: () => Navigator.pop(ctx, platform.id),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 新增平台弹窗。
  Future<void> _addPlatform() async {
    final nameCtrl = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新增平台'),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: appInput(hint: '如 天猫、得物、闲鱼'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (saved == true && nameCtrl.text.trim().isNotEmpty) {
      final color = _palette[_platforms.length % _palette.length];
      await AppDatabase.instance.addPlatform(nameCtrl.text, color);
      if (!mounted) return;
      bumpDbRevision();
      showToast(context, '平台已添加');
    }
    nameCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('账号台账'),
        actions: [
          TextButton(onPressed: _addPlatform, child: const Text('+ 平台')),
          IconButton(
            tooltip: '添加账号',
            onPressed: _addAccount,
            icon: const Icon(Icons.add_circle_outline),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (_) => _load(),
              decoration: appInput(
                hint: '搜索账号别名或归属人',
                prefix: const Icon(Icons.search, size: 20, color: AppColors.ink3),
              ),
            ),
          ),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _buildPlatformChip('全部', null),
                for (final platform in _platforms)
                  _buildPlatformChip(platform.name, platform.id),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _accounts.isEmpty
                    ? EmptyState(
                        icon: Icons.badge_outlined,
                        title: '还没有账号',
                        description: '先把平台账号登记进来（只存别名与归属人，不存密码），分配包裹时才能选择。',
                        action: FilledButton(
                          onPressed: _addAccount,
                          child: const Text('添加账号'),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          itemCount: _accounts.length,
                          itemBuilder: (context, index) =>
                              _buildAccountCard(_accounts[index]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  /// 平台筛选标签。
  Widget _buildPlatformChip(String label, String? id) {
    final active = _platformId == id;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () {
          setState(() {
            _platformId = id;
            _loading = true;
          });
          _load();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? AppColors.brand : AppColors.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: active ? AppColors.brand : AppColors.line),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: active ? Colors.white : AppColors.ink2,
            ),
          ),
        ),
      ),
    );
  }

  /// 账号卡片。
  Widget _buildAccountCard(AccountView view) {
    final color = Color(view.platform.color);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                view.platform.name.characters.first,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ),
            const SizedBox(width: 12),
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
                  const SizedBox(height: 3),
                  Text(
                    [
                      view.platform.name,
                      if (view.account.owner.isNotEmpty)
                        '归属 ${view.account.owner}',
                      if (view.account.note.isNotEmpty) view.account.note,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: AppColors.ink3),
                  ),
                ],
              ),
            ),
            AppPill(text: view.account.status == 'active' ? '正常' : '停用'),
          ],
        ),
      ),
    );
  }
}
