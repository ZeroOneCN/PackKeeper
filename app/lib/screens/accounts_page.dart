import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:styled_widget/styled_widget.dart';

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

/// 账号台账：平台筛选、账号检索、新增/编辑平台与账号。
class AccountsPage extends StatefulWidget {
  const AccountsPage({super.key});

  @override
  State<AccountsPage> createState() => _AccountsPageState();
}

class _AccountsPageState extends State<AccountsPage> {
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _aliasCtrl = TextEditingController();
  final TextEditingController _ownerCtrl = TextEditingController();
  final TextEditingController _noteCtrl = TextEditingController();
  final TextEditingController _platformNameCtrl = TextEditingController();

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
    _aliasCtrl.dispose();
    _ownerCtrl.dispose();
    _noteCtrl.dispose();
    _platformNameCtrl.dispose();
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

  /// 添加或编辑账号弹窗。
  ///
  /// 参数：[editing] 传入时为编辑模式，否则为新增模式。
  Future<void> _openAccountDialog({AccountView? editing}) async {
    if (_platforms.isEmpty) {
      showToast(context, '请先添加一个平台');
      return;
    }
    final isEdit = editing != null;
    _aliasCtrl.text = editing?.account.alias ?? '';
    _ownerCtrl.text = editing?.account.owner ?? '';
    _noteCtrl.text = editing?.account.note ?? '';
    var platformId =
        editing?.account.platformId ?? _platformId ?? _platforms.first.id;
    var status = editing?.account.status ?? 'active';
    var showError = false;
    var saving = false;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final platformName = _platforms
              .firstWhere(
                (p) => p.id == platformId,
                orElse: () => _platforms.first,
              )
              .name;
          return AlertDialog(
            title: Text(isEdit ? '编辑账号' : '添加账号'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InputDecorator(
                        decoration: appInput(label: '所属平台'),
                        child: Row(
                          children: [
                            Text(platformName)
                                .fontSize(14)
                                .textColor(AppColors.ink)
                                .expanded(),
                            const Icon(
                              Icons.expand_more,
                              size: 20,
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
                      .gestures(
                        onTap: saving
                            ? null
                            : () async {
                                final picked = await _pickPlatform(
                                  ctx,
                                  selectedId: platformId,
                                );
                                if (picked != null) {
                                  setDialogState(() => platformId = picked);
                                }
                              },
                      ),
                  TextField(
                    controller: _aliasCtrl,
                    decoration: appInput(label: '账号别名', hint: '如 小王-淘宝1号'),
                    onChanged: (_) {
                      if (showError) setDialogState(() => showError = false);
                    },
                  ).padding(top: 10),
                  if (showError)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: const Text('请填写账号别名')
                          .fontSize(11)
                          .textColor(AppColors.danger),
                    ).padding(top: 4),
                  TextField(
                    controller: _ownerCtrl,
                    decoration: appInput(label: '归属员工', hint: '可留空'),
                  ).padding(top: 10),
                  TextField(
                    controller: _noteCtrl,
                    decoration: appInput(label: '备注', hint: '手机号尾号等线索'),
                  ).padding(top: 10),
                  Row(
                    children: [
                      const Text('账号状态').fontSize(14).textColor(AppColors.ink2),
                      const Spacer(),
                      Text(status == 'active' ? '正常' : '停用')
                          .fontSize(13)
                          .fontWeight(FontWeight.w600)
                          .textColor(
                            status == 'active'
                                ? AppColors.brandDeep
                                : AppColors.ink3,
                          )
                          .padding(right: 8),
                      Switch(
                        value: status == 'active',
                        onChanged: saving
                            ? null
                            : (v) => setDialogState(
                                () => status = v ? 'active' : 'disabled',
                              ),
                      ),
                    ],
                  ).padding(top: 4),
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
                        if (_aliasCtrl.text.trim().isEmpty) {
                          setDialogState(() => showError = true);
                          return;
                        }
                        setDialogState(() => saving = true);
                        try {
                          if (isEdit) {
                            await AppDatabase.instance.updateAccount(
                              id: editing.account.id,
                              platformId: platformId,
                              alias: _aliasCtrl.text,
                              owner: _ownerCtrl.text,
                              note: _noteCtrl.text,
                              status: status,
                            );
                          } else {
                            await AppDatabase.instance.addAccount(
                              platformId: platformId,
                              alias: _aliasCtrl.text,
                              owner: _ownerCtrl.text,
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
          );
        },
      ),
    );

    if (saved == true) {
      if (!mounted) return;
      bumpDbRevision();
      showToast(context, isEdit ? '账号已更新' : '账号已添加');
    }
  }

  /// 平台选择底部弹层。
  ///
  /// 参数：[selectedId] 当前选中的平台主键，用于显示勾选状态。
  Future<String?> _pickPlatform(BuildContext context, {String? selectedId}) {
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
                      leading: const SizedBox(width: 10, height: 10).decorated(
                        color: Color(platform.color),
                        shape: BoxShape.circle,
                      ),
                      title: Text(platform.name),
                      trailing: selectedId == platform.id
                          ? const Icon(
                              Icons.check,
                              size: 20,
                              color: AppColors.brand,
                            )
                          : null,
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

  /// 新增平台弹窗（含重名与空值校验）。
  Future<void> _addPlatform() async {
    _platformNameCtrl.clear();
    var error = '';

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('新增平台'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _platformNameCtrl,
                autofocus: true,
                decoration: appInput(hint: '如 天猫、得物、闲鱼'),
                onChanged: (_) {
                  if (error.isNotEmpty) setDialogState(() => error = '');
                },
              ),
              if (error.isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(error)
                      .fontSize(11)
                      .textColor(AppColors.danger)
                      .padding(top: 4),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final name = _platformNameCtrl.text.trim();
                if (name.isEmpty) {
                  setDialogState(() => error = '请输入平台名称');
                  return;
                }
                if (_platforms.any((p) => p.name == name)) {
                  setDialogState(() => error = '该平台已存在');
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );

    if (saved != true) return;
    final name = _platformNameCtrl.text.trim();
    final color = _palette[_platforms.length % _palette.length];
    try {
      await AppDatabase.instance.addPlatform(name, color);
      if (!mounted) return;
      bumpDbRevision();
      showToast(context, '平台已添加');
    } catch (_) {
      if (!mounted) return;
      showToast(context, '平台添加失败，请检查名称是否重复');
    }
  }

  /// 平台管理：底部弹层中重命名或删除平台。
  Future<void> _managePlatforms() async {
    final action =
        await showModalBottomSheet<({String type, ShopPlatform platform})>(
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
                    '平台管理',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final platform in _platforms)
                        ListTile(
                          leading: const SizedBox(width: 10, height: 10)
                              .decorated(
                                color: Color(platform.color),
                                shape: BoxShape.circle,
                              ),
                          title: Text(platform.name),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: '重命名',
                                icon: const Icon(
                                  Icons.edit_outlined,
                                  size: 20,
                                  color: AppColors.ink2,
                                ),
                                onPressed: () => Navigator.pop(ctx, (
                                  type: 'rename',
                                  platform: platform,
                                )),
                              ),
                              IconButton(
                                tooltip: '删除',
                                icon: const Icon(
                                  Icons.delete_outline,
                                  size: 20,
                                  color: AppColors.danger,
                                ),
                                onPressed: () => Navigator.pop(ctx, (
                                  type: 'delete',
                                  platform: platform,
                                )),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
    if (action == null || !mounted) return;
    if (action.type == 'rename') {
      await _renamePlatform(action.platform);
    } else {
      await _deletePlatform(action.platform);
    }
  }

  /// 重命名平台（名称非空且不与其它平台重复）。
  ///
  /// 参数：[platform] 目标平台。
  Future<void> _renamePlatform(ShopPlatform platform) async {
    _platformNameCtrl.text = platform.name;
    var error = '';
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('重命名平台'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _platformNameCtrl,
                autofocus: true,
                decoration: appInput(hint: '平台名称'),
                onChanged: (_) {
                  if (error.isNotEmpty) setDialogState(() => error = '');
                },
              ),
              if (error.isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(error)
                      .fontSize(11)
                      .textColor(AppColors.danger)
                      .padding(top: 4),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final name = _platformNameCtrl.text.trim();
                if (name.isEmpty) {
                  setDialogState(() => error = '请输入平台名称');
                  return;
                }
                if (_platforms.any(
                  (p) => p.name == name && p.id != platform.id,
                )) {
                  setDialogState(() => error = '该平台已存在');
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (saved != true) return;
    try {
      await AppDatabase.instance.renamePlatform(
        id: platform.id,
        name: _platformNameCtrl.text,
      );
    } catch (_) {
      if (!mounted) return;
      showToast(context, '重命名失败，请检查名称是否重复');
      return;
    }
    if (!mounted) return;
    bumpDbRevision();
    showToast(context, '平台已重命名');
  }

  /// 删除平台（二次确认，平台下无账号时才可删除）。
  ///
  /// 参数：[platform] 目标平台。
  Future<void> _deletePlatform(ShopPlatform platform) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除平台'),
        content: Text('确认删除「${platform.name}」？仅当该平台下没有账号时可以删除。'),
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
    try {
      await AppDatabase.instance.deletePlatform(platform.id);
    } on StateError catch (e) {
      if (!mounted) return;
      showToast(context, e.message);
      return;
    } catch (_) {
      if (!mounted) return;
      showToast(context, '删除失败，请重试');
      return;
    }
    if (!mounted) return;
    if (_platformId == platform.id) {
      setState(() => _platformId = null);
    }
    bumpDbRevision();
    showToast(context, '平台已删除');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('账号台账'),
        actions: [
          PopupMenuButton<String>(
            tooltip: '更多操作',
            icon: const Icon(Icons.more_vert, color: AppColors.ink2),
            onSelected: (value) {
              switch (value) {
                case 'account':
                  _openAccountDialog();
                case 'platform':
                  _addPlatform();
                case 'manage':
                  _managePlatforms();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'account', child: Text('添加账号')),
              PopupMenuItem(value: 'platform', child: Text('添加平台')),
              PopupMenuItem(value: 'manage', child: Text('平台管理')),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          Row(
            children: [
              TextField(
                controller: _searchCtrl,
                onChanged: (_) => _load(),
                decoration: appInput(
                  hint: '搜索账号别名或归属人',
                  prefix: const Icon(
                    Icons.search,
                    size: 20,
                    color: AppColors.ink3,
                  ),
                ),
              ).expanded(),
              const SizedBox(width: 10),
              _buildPlatformFilter(),
            ],
          ).padding(left: 16, right: 16, bottom: 8),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _accounts.isEmpty
                ? EmptyState(
                    icon: Icons.badge_outlined,
                    title: '还没有账号',
                    description: '先把平台账号登记进来（只存别名与归属人，不存密码），分配包裹时才能选择。',
                    action: FilledButton(
                      onPressed: () => _openAccountDialog(),
                      child: const Text('添加账号'),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: SlidableAutoCloseBehavior(
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        itemCount: _accounts.length,
                        itemBuilder: (context, index) =>
                            _buildAccountCard(_accounts[index]),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  /// 平台筛选下拉入口。
  Widget _buildPlatformFilter() {
    final active = _platforms.where((p) => p.id == _platformId).toList();
    final name = active.isEmpty ? '全部平台' : active.first.name;
    final color = active.isEmpty ? AppColors.ink3 : Color(active.first.color);
    return SizedBox(
      width: 132,
      child:
          InputDecorator(
                decoration: appInput(),
                child: Row(
                  children: [
                    SizedBox(width: 8, height: 8)
                        .decorated(color: color, shape: BoxShape.circle)
                        .padding(right: 6),
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ).fontSize(13).textColor(AppColors.ink).expanded(),
                    const Icon(
                      Icons.expand_more,
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
              .gestures(onTap: _pickFilterPlatform),
    );
  }

  /// 平台筛选底部弹层（含「全部平台」）。
  Future<void> _pickFilterPlatform() async {
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
                '筛选平台',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  ListTile(
                    leading: const Icon(
                      Icons.apps,
                      size: 20,
                      color: AppColors.ink2,
                    ),
                    title: const Text('全部平台'),
                    trailing: _platformId == null
                        ? const Icon(
                            Icons.check,
                            size: 20,
                            color: AppColors.brand,
                          )
                        : null,
                    onTap: () => Navigator.pop(ctx, ''),
                  ),
                  for (final platform in _platforms)
                    ListTile(
                      leading: const SizedBox(width: 10, height: 10).decorated(
                        color: Color(platform.color),
                        shape: BoxShape.circle,
                      ),
                      title: Text(platform.name),
                      trailing: _platformId == platform.id
                          ? const Icon(
                              Icons.check,
                              size: 20,
                              color: AppColors.brand,
                            )
                          : null,
                      onTap: () => Navigator.pop(ctx, platform.id),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _platformId = picked.isEmpty ? null : picked;
      _loading = true;
    });
    _load();
  }

  /// 删除账号（二次确认）。
  ///
  /// 参数：[view] 目标账号；存在代下单订单时数据层会拒绝删除并提示原因。
  Future<void> _confirmDeleteAccount(AccountView view) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除账号'),
        content: Text('确认删除「${view.account.alias}」？该账号下的包裹将退回待认领池，删除后不可恢复。'),
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
    try {
      await AppDatabase.instance.deleteAccount(view.account.id);
    } on StateError catch (e) {
      if (!mounted) return;
      showToast(context, e.message);
      return;
    } catch (_) {
      if (!mounted) return;
      showToast(context, '删除失败，请重试');
      return;
    }
    if (!mounted) return;
    bumpDbRevision();
    showToast(context, '账号已删除');
  }

  /// 账号卡片：左滑出现「编辑 / 删除」，按钮与卡片同高贴合，点击卡片不进入编辑。
  Widget _buildAccountCard(AccountView view) {
    final color = Color(view.platform.color);
    final disabled = view.account.status != 'active';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Slidable(
        key: ValueKey(view.account.id),
        groupTag: 'accounts',
        endActionPane: ActionPane(
          motion: const ScrollMotion(),
          extentRatio: 0.38,
          children: [
            SlidableAction(
              onPressed: (_) => _openAccountDialog(editing: view),
              backgroundColor: AppColors.brand,
              foregroundColor: Colors.white,
              icon: Icons.edit_outlined,
              label: '编辑',
              labelStyle: const TextStyle(fontSize: 12),
            ),
            SlidableAction(
              onPressed: (_) => _confirmDeleteAccount(view),
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
              icon: Icons.delete_outline,
              label: '删除',
              labelStyle: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        child: AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Text(view.platform.name.characters.first)
                  .fontSize(15)
                  .fontWeight(FontWeight.w700)
                  .textColor(color)
                  .center()
                  .constrained(width: 38, height: 38)
                  .decorated(
                    color: color.withValues(alpha: disabled ? 0.05 : 0.1),
                    borderRadius: BorderRadius.circular(10),
                  )
                  .padding(right: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(view.account.alias)
                      .fontSize(14)
                      .fontWeight(FontWeight.w600)
                      .textColor(disabled ? AppColors.ink3 : AppColors.ink),
                  Text(
                    [
                      view.platform.name,
                      if (view.account.owner.isNotEmpty)
                        '归属 ${view.account.owner}',
                      if (view.account.note.isNotEmpty) view.account.note,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ).fontSize(12).textColor(AppColors.ink3).padding(top: 3),
                ],
              ).expanded(),
              AppPill(text: disabled ? '停用' : '正常'),
            ],
          ),
        ),
      ),
    );
  }
}
