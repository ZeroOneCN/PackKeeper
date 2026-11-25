import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:styled_widget/styled_widget.dart';

import '../core/app_events.dart';
import '../core/db.dart';
import '../core/theme.dart';
import '../widgets/common.dart';

/// 显示数据备份/恢复底部弹层。
///
/// 参数：[context] 页面上下文。
Future<void> showBackupSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const _BackupSheet(),
  );
}

/// 备份弹层：导出 JSON 备份到系统分享，或从文件选择器导入恢复。
class _BackupSheet extends StatefulWidget {
  const _BackupSheet();

  @override
  State<_BackupSheet> createState() => _BackupSheetState();
}

class _BackupSheetState extends State<_BackupSheet> {
  bool _busy = false;

  /// 两位补零。
  String _two(int value) => value.toString().padLeft(2, '0');

  /// 导出全量数据为 JSON 文件并调起系统分享。
  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final payload = await AppDatabase.instance.exportAll();
      final dir = await getTemporaryDirectory();
      final now = DateTime.now();
      final stamp =
          '${now.year}${_two(now.month)}${_two(now.day)}-'
          '${_two(now.hour)}${_two(now.minute)}';
      final file = File(p.join(dir.path, '包裹管家备份-$stamp.json'));
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(payload),
      );
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/json')],
          text: '包裹管家数据备份',
        ),
      );
      if (!mounted) return;
      showToast(context, '备份文件已生成，请在分享面板中选择保存位置');
    } catch (_) {
      if (!mounted) return;
      showToast(context, '导出失败，请重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 通过文件选择器读取 JSON 备份，二次确认后覆盖导入。
  Future<void> _import() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['json'],
      dialogTitle: '选择备份文件',
    );
    if (file == null) return;
    setState(() => _busy = true);
    try {
      final text = utf8.decode(await file.readAsBytes());
      final decoded = jsonDecode(text);
      if (decoded is! Map) {
        throw const FormatException('文件内容不是有效的备份数据');
      }
      final payload =
          decoded.map((key, value) => MapEntry(key.toString(), value as Object?));
      final data = payload['data'];
      int countOf(String table) =>
          data is Map && data[table] is List ? (data[table]! as List).length : 0;
      final summary = '平台 ${countOf('platforms')} / 账号 ${countOf('accounts')} / '
          '商品 ${countOf('products')} / 包裹 ${countOf('parcels')} / '
          '订单 ${countOf('orders')} / 转寄 ${countOf('shipments')}';
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('覆盖导入备份'),
          content: Text('将用备份覆盖当前全部数据（$summary），当前数据不可恢复。是否继续？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('覆盖导入'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      final result = await AppDatabase.instance.importAll(payload);
      bumpDbRevision();
      if (!mounted) return;
      showToast(
        context,
        '已恢复 ${result.accounts} 个账号、${result.orders} 笔订单、'
        '${result.parcels} 件包裹',
      );
      Navigator.of(context).pop();
    } on FormatException catch (e) {
      if (!mounted) return;
      showToast(context, '导入失败：${e.message}');
    } catch (_) {
      if (!mounted) return;
      showToast(context, '导入失败，请确认文件来自本应用');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 18, 20, 4),
            child: Text(
              '数据备份',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
          const Text('备份为 JSON 文件，包含平台、账号、商品、包裹、转寄批次与订单，可换机恢复。')
              .fontSize(12)
              .textColor(AppColors.ink3)
              .textStyle(const TextStyle(height: 1.5))
              .padding(horizontal: 20),
          const SizedBox(height: 8),
          ListTile(
            enabled: !_busy,
            leading: const Icon(Icons.ios_share, color: AppColors.brandDeep),
            title: const Text('导出备份'),
            subtitle: const Text('生成 JSON 文件并调起系统分享/保存'),
            onTap: _busy ? null : _export,
          ),
          ListTile(
            enabled: !_busy,
            leading: const Icon(Icons.settings_backup_restore, color: AppColors.warn),
            title: const Text('导入恢复'),
            subtitle: const Text('选择备份文件覆盖当前数据（需二次确认）'),
            onTap: _busy ? null : _import,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
