import 'package:app_settings/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:styled_widget/styled_widget.dart';

import '../core/tracking.dart';
import '../widgets/scan_overlay.dart';

/// 扫码采集页：仅采集物流单号，不写入数据库，支持连续扫码。
///
/// 返回：`Navigator.pop(context, List<String>)` 采集到的规范化单号列表。
class ScanCapturePage extends StatefulWidget {
  const ScanCapturePage({super.key});

  @override
  State<ScanCapturePage> createState() => _ScanCapturePageState();
}

class _ScanCapturePageState extends State<ScanCapturePage> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
  );

  /// 已采集单号，按采集顺序保存（key 为规范化单号）。
  final Map<String, TrackingInfo> _entries = <String, TrackingInfo>{};

  /// 手动输入框控制器，常驻页面避免弹窗切换导致状态丢失。
  final TextEditingController _manualCtrl = TextEditingController();
  final FocusNode _manualFocus = FocusNode();

  /// 是否展开手动输入行。
  bool _manualOpen = false;
  bool _torchOn = false;
  String _lastCode = '';
  DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void dispose() {
    _manualCtrl.dispose();
    _manualFocus.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// 处理相机识别结果：校验、去抖、去重后加入列表。
  ///
  /// 参数：[capture] 相机条码回调。
  void _onDetect(BarcodeCapture capture) {
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null || raw.trim().isEmpty) continue;
      final info = parseTracking(raw);
      if (info.normalized.isEmpty) continue;
      final now = DateTime.now();
      if (info.normalized == _lastCode &&
          now.difference(_lastAt) < const Duration(milliseconds: 1200)) {
        continue;
      }
      _lastCode = info.normalized;
      _lastAt = now;
      // 有效扫码统一震动反馈（包括重复单号）。
      HapticFeedback.mediumImpact();
      if (_entries.containsKey(info.normalized)) {
        _toast('该单号已在本次列表中');
        continue;
      }
      setState(() => _entries[info.normalized] = info);
    }
  }

  /// 展开或收起手动输入行。
  void _toggleManual() {
    setState(() => _manualOpen = !_manualOpen);
    if (_manualOpen) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _manualFocus.requestFocus(),
      );
    } else {
      _manualFocus.unfocus();
    }
  }

  /// 添加手动输入的单号，成功后清空输入框并保持焦点以便继续录入。
  void _submitManual() {
    final info = parseTracking(_manualCtrl.text);
    if (info.normalized.isEmpty) {
      _toast('未识别到有效单号');
      return;
    }
    if (_entries.containsKey(info.normalized)) {
      _toast('该单号已在列表中');
      _manualCtrl.clear();
      return;
    }
    setState(() => _entries[info.normalized] = info);
    _manualCtrl.clear();
    _manualFocus.requestFocus();
  }

  /// 切换手电筒。
  Future<void> _toggleTorch() async {
    await _controller.toggleTorch();
    setState(() => _torchOn = !_torchOn);
  }

  /// 轻提示。
  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) =>
                _CameraError(message: error.errorCode.name),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: ScanOverlayPainter()),
            ),
          ),
          SafeArea(
            child: Column(
              children: [_buildTopBar(), const Spacer(), _buildPanel()],
            ),
          ),
        ],
      ),
    );
  }

  /// 顶部返回、标题与手电筒。
  Widget _buildTopBar() {
    return Row(
      children: [
        IconButton(
          onPressed: () => Navigator.of(context).pop(<String>[]),
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          color: Colors.white,
        ),
        const Text('扫码录入')
            .textColor(Colors.white)
            .fontSize(17)
            .fontWeight(FontWeight.w600),
        const Spacer(),
        IconButton(
          onPressed: _toggleTorch,
          icon: Icon(_torchOn ? Icons.flash_on : Icons.flash_off),
          color: _torchOn ? const Color(0xFFFFD60A) : Colors.white,
        ),
      ],
    ).padding(horizontal: 8, vertical: 6);
  }

  /// 底部采集面板：计数、单号列表与操作。
  Widget _buildPanel() {
    return Column(
          children: [
            Row(
              children: [
                Text('已采集 ${_entries.length} 个单号')
                    .textColor(Colors.white)
                    .fontSize(15)
                    .fontWeight(FontWeight.w600),
                const Spacer(),
                if (_entries.isNotEmpty)
                  IconButton(
                    tooltip: '清空',
                    onPressed: () => setState(_entries.clear),
                    icon: const Icon(
                      Icons.delete_sweep_outlined,
                      size: 20,
                      color: Colors.white70,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: _manualOpen ? 92 : 150,
              child: _entries.isEmpty
                  ? const Text('对准快递条码连续扫描，扫到的单号会自动去重')
                        .textColor(Color(0xFF9CA3AF))
                        .fontSize(13)
                        .center()
                  : ListView.separated(
                      itemCount: _entries.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1, color: Color(0xFF1F2937)),
                      itemBuilder: (context, index) {
                        final info = _entries.values
                            .toList()
                            .reversed
                            .elementAt(index);
                        return Row(
                          children: [
                            const Icon(
                              Icons.check_circle_outline,
                              size: 18,
                              color: Color(0xFF86EFAC),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(info.normalized)
                                    .textColor(Colors.white)
                                    .fontSize(13)
                                    .fontWeight(FontWeight.w600)
                                    .letterSpacing(0.3),
                                Text(
                                      info.carrier.isEmpty
                                          ? '未知快递'
                                          : '${info.carrier}'
                                                '${info.suspicious ? ' · ${info.hint}' : ''}',
                                    )
                                    .textColor(const Color(0xFF9CA3AF))
                                    .fontSize(11)
                                    .padding(top: 2),
                              ],
                            ).padding(left: 8).expanded(),
                            IconButton(
                              tooltip: '移除',
                              onPressed: () => setState(
                                () => _entries.remove(info.normalized),
                              ),
                              icon: const Icon(
                                Icons.close,
                                size: 18,
                                color: Colors.white38,
                              ),
                            ),
                          ],
                        ).padding(vertical: 3);
                      },
                    ),
            ),
            if (_manualOpen)
              Row(
                children: [
                  TextField(
                    controller: _manualCtrl,
                    focusNode: _manualFocus,
                    autofocus: true,
                    textCapitalization: TextCapitalization.characters,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submitManual(),
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: '输入或粘贴单号，支持连续录入',
                      hintStyle: const TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 13,
                      ),
                      filled: true,
                      fillColor: const Color(0xFF1F2937),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 11,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ).expanded(),
                  const SizedBox(width: 10),
                  FilledButton(
                    onPressed: _submitManual,
                    child: const Text('添加', maxLines: 1, softWrap: false),
                  ),
                ],
              ).padding(top: 8),
            Row(
              children: [
                OutlinedButton(
                  onPressed: _toggleManual,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    side: const BorderSide(color: Color(0xFF374151)),
                    minimumSize: const Size(0, 46),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('手输单号', maxLines: 1, softWrap: false),
                ).expanded(),
                const SizedBox(width: 10),
                FilledButton(
                  onPressed: () =>
                      Navigator.of(context).pop(_entries.keys.toList()),
                  child: Text(
                    '完成录入 (${_entries.length})',
                    maxLines: 1,
                    softWrap: false,
                  ),
                ).expanded(),
              ],
            ).padding(top: 10),
          ],
        )
        .padding(left: 16, top: 12, right: 8, bottom: 12)
        .constrained(width: double.infinity)
        .decorated(
          color: const Color(0xFF111827),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        );
  }
}

/// 相机不可用时的兜底界面。
class _CameraError extends StatelessWidget {
  const _CameraError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(
          Icons.no_photography_outlined,
          color: Colors.white70,
          size: 40,
        ),
        const Text('相机不可用')
            .textColor(Colors.white)
            .fontSize(16)
            .fontWeight(FontWeight.w600)
            .padding(top: 14),
        Text('请检查相机权限后重试（$message）')
            .textColor(Colors.white54)
            .fontSize(12)
            .textAlignment(TextAlign.center)
            .padding(top: 6, horizontal: 32),
        FilledButton(
          onPressed: () =>
              AppSettings.openAppSettings(type: AppSettingsType.settings),
          child: const Text('去设置'),
        ).padding(top: 20),
        TextButton(
          onPressed: () => Navigator.of(context).pop(<String>[]),
          child: const Text('返回批量录单'),
        ).padding(top: 4),
      ],
    );
  }
}
