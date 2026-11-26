import 'package:app_settings/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:styled_widget/styled_widget.dart';

import '../core/theme.dart';
import '../core/update_service.dart';
import 'common.dart';

/// 是否已有更新检查在进行，避免启动检查与手动检查重复弹窗。
bool _checking = false;

/// 检查并提示应用更新。
///
/// 参数：[context] 页面上下文；[silent] 为 true 时无更新或失败均不打扰用户（启动时使用）。
/// 返回：无返回值；发现新版本时弹出更新对话框，下载安装结果通过 Toast 提示。
Future<void> checkForUpdates(
  BuildContext context, {
  bool silent = false,
}) async {
  if (_checking) return;
  _checking = true;
  try {
    final info = await PackageInfo.fromPlatform();
    final code = int.tryParse(info.buildNumber) ?? 0;
    final result = await UpdateService.checkForUpdate(code);
    if (!context.mounted) return;
    final latest = result.latest;
    if (!result.hasUpdate || latest == null) {
      if (!silent) showToast(context, '当前已是最新版本 v${info.version}');
      return;
    }
    final message = await showDialog<String>(
      context: context,
      barrierDismissible: !result.forceUpdate,
      builder: (_) => UpdateDialog(
        release: latest,
        currentVersion: info.version.isEmpty ? info.buildNumber : info.version,
        force: result.forceUpdate,
        reason: result.reason,
        onRefresh: () async {
          final refreshed = await UpdateService.checkForUpdate(code);
          return refreshed.latest;
        },
      ),
    );
    if (message != null && context.mounted) showToast(context, message);
  } on UpdateException catch (e) {
    if (!silent && context.mounted) showToast(context, e.message);
  } catch (_) {
    if (!silent && context.mounted) showToast(context, '检查更新失败，请稍后重试');
  } finally {
    _checking = false;
  }
}

/// 更新提示对话框：展示版本信息、更新日志，并下载安装。
class UpdateDialog extends StatefulWidget {
  const UpdateDialog({
    super.key,
    required this.release,
    required this.currentVersion,
    required this.force,
    this.reason,
    this.onRefresh,
  });

  /// 目标版本信息。
  final AppRelease release;

  /// 当前安装的版本名。
  final String currentVersion;

  /// 是否强制更新（不可跳过）。
  final bool force;

  /// 服务端补充说明。
  final String? reason;

  /// 重新检查更新并返回最新发布信息（用于下载链接过期后刷新）。
  final Future<AppRelease?> Function()? onRefresh;

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  /// 当前目标版本，下载链接过期后会被刷新。
  late AppRelease _release;

  /// 下载进度，null 表示尚未开始。
  UpdateProgress? _progress;

  /// 是否正在下载。
  bool _downloading = false;

  /// 失败提示，null 表示无错误。
  String? _error;

  @override
  void initState() {
    super.initState();
    _release = widget.release;
  }

  /// 字节数转可读文案。
  ///
  /// 参数：[bytes] 字节数。
  /// 返回：例如「100.1 MB」。
  String _size(int bytes) {
    if (bytes <= 0) return '未知大小';
    if (bytes >= 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }

  /// 下载、校验并调起系统安装。
  Future<void> _start() async {
    setState(() {
      _downloading = true;
      _error = null;
      _progress = null;
    });
    try {
      final file = await UpdateService.downloadApk(
        _release,
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress);
        },
      );
      if (!mounted) return;
      final result = await OpenFilex.open(
        file.path,
        type: 'application/vnd.android.package-archive',
      );
      if (!mounted) return;
      if (result.type == ResultType.done) {
        Navigator.pop(context, '已开始安装，请按系统提示完成');
        return;
      }
      if (result.type == ResultType.permissionDenied) {
        await AppSettings.openAppSettings(
          type: AppSettingsType.manageUnknownAppSources,
        );
        if (!mounted) return;
        Navigator.pop(context, '请在系统中允许安装未知应用后重新检查更新');
        return;
      }
      setState(() {
        _downloading = false;
        _error = '无法启动安装程序（${result.message}）';
      });
    } on UpdateException catch (e) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _error = '下载或安装失败，请稍后重试';
      });
    }
  }

  /// 失败后重试：下载链接过期时先重新检查，拿到新的签名地址。
  Future<void> _retry() async {
    if (_error?.contains('过期') ?? false) {
      try {
        final latest = await widget.onRefresh?.call();
        if (latest != null && mounted) {
          setState(() => _release = latest);
        }
      } catch (_) {
        // 刷新失败时继续用旧地址重试，由下载层给出最终错误。
      }
    }
    await _start();
  }

  /// 关闭对话框（强制更新时不允许）。
  void _close() {
    if (widget.force) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final release = _release;
    final progress = _progress;
    final ratio = progress?.ratio;

    final content = AlertDialog(
      title: Row(
        children: [
          const Padding(
            padding: EdgeInsets.only(right: 8),
            child: Icon(
              Icons.system_update_alt,
              size: 22,
              color: AppColors.brand,
            ),
          ),
          Text('发现新版本 v${release.versionName}').fontSize(17),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '当前 v${widget.currentVersion}  ·  安装包 ${_size(release.fileSize)}',
              ).fontSize(12).textColor(AppColors.ink3),
              if (widget.force)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(top: 12),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.warn.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    widget.reason ?? '该版本包含重要修复，更新后才能继续使用。',
                  ).fontSize(12).textColor(AppColors.warn),
                ),
              const SizedBox(height: 14),
              Text('更新内容').fontSize(13).fontWeight(FontWeight.w600),
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 168),
                margin: const EdgeInsets.only(top: 6),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    release.changelog.trim().isEmpty
                        ? '本次更新包含体验优化与问题修复。'
                        : release.changelog.trim(),
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: AppColors.ink2,
                    ),
                  ),
                ),
              ),
              if (_downloading)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LinearProgressIndicator(
                      value: ratio,
                      minHeight: 6,
                      borderRadius: BorderRadius.circular(999),
                    ).padding(top: 18),
                    Text(
                      ratio == null
                          ? '正在下载安装包…'
                          : '正在下载 ${(ratio * 100).toStringAsFixed(0)}%'
                                '（${_size(progress?.received ?? 0)} / '
                                '${_size(progress?.total ?? release.fileSize)}）',
                    ).fontSize(12).textColor(AppColors.ink3).padding(top: 8),
                  ],
                ),
              if (_error != null)
                Text(_error!)
                    .fontSize(12)
                    .textColor(AppColors.danger)
                    .padding(top: 12),
            ],
          ),
        ),
      ),
      actions: _downloading
          ? const []
          : [
              if (!widget.force && _error == null)
                TextButton(
                  onPressed: _close,
                  child: const Text('稍后更新'),
                ),
              if (!widget.force && _error != null)
                TextButton(
                  onPressed: _close,
                  child: const Text('取消'),
                ),
              FilledButton(
                onPressed: _error == null ? _start : _retry,
                child: Text(_error == null ? '立即更新' : '重试'),
              ),
            ],
    );

    return PopScope(
      canPop: !widget.force,
      child: content,
    );
  }
}
