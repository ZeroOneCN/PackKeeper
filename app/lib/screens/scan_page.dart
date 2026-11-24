import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/db.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../core/tracking.dart';

/// 本次扫描会话中的一条记录。
class _ScanEntry {
  const _ScanEntry({
    required this.info,
    required this.duplicate,
    required this.source,
  });

  final TrackingInfo info;

  /// 数据库中已存在同名单号时为 true。
  final bool duplicate;
  final ParcelSource source;
}

/// 扫码入库页：全屏取景、连续扫码、自动去抖与重复提示。
class ScanPage extends StatefulWidget {
  const ScanPage({super.key});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
  );

  final Map<String, _ScanEntry> _entries = <String, _ScanEntry>{};
  bool _torchOn = false;
  bool _saving = false;
  String _lastCode = '';
  DateTime? _lastAt;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 相机回调：规范化单号、1.5 秒去抖、入库去重检测。
  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_saving) return;
    String? raw;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value != null && value.trim().isNotEmpty) {
        raw = value;
        break;
      }
    }
    if (raw == null) return;

    final info = parseTracking(raw);
    if (info.normalized.isEmpty) return;

    final now = DateTime.now();
    if (_lastCode == info.normalized &&
        _lastAt != null &&
        now.difference(_lastAt!).inMilliseconds < 1500) {
      return;
    }
    _lastCode = info.normalized;
    _lastAt = now;

    if (_entries.containsKey(info.normalized)) return;

    final existing = await AppDatabase.instance.findByTracking(info.normalized);
    if (!mounted) return;
    setState(() {
      _entries[info.normalized] = _ScanEntry(
        info: info,
        duplicate: existing != null,
        source: ParcelSource.barcode,
      );
    });
    HapticFeedback.mediumImpact();
  }

  /// 手动输入单号（面单条码破损时的降级通道）。
  Future<void> _manualInput() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('手动输入单号'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: appInput(hint: '如 SF1234567890123'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('加入'),
          ),
        ],
      ),
    );
    if (code == null || code.trim().isEmpty) return;

    final info = parseTracking(code);
    if (info.normalized.isEmpty) return;
    if (_entries.containsKey(info.normalized)) {
      if (mounted) _toast('该单号已在本次扫描列表中');
      return;
    }
    final existing = await AppDatabase.instance.findByTracking(info.normalized);
    if (!mounted) return;
    setState(() {
      _entries[info.normalized] = _ScanEntry(
        info: info,
        duplicate: existing != null,
        source: ParcelSource.manual,
      );
    });
  }

  /// 提交本次扫描结果并返回新建数量。
  Future<void> _commit() async {
    final pending = _entries.values.where((e) => !e.duplicate).toList();
    if (pending.isEmpty) {
      Navigator.of(context).pop(0);
      return;
    }
    setState(() => _saving = true);
    var created = 0;
    for (final entry in pending) {
      final result = await AppDatabase.instance.addParcel(
        trackingNo: entry.info.normalized,
        source: entry.source,
      );
      if (result.created) created++;
    }
    if (!mounted) return;
    Navigator.of(context).pop(created);
  }

  /// 切换手电筒。
  Future<void> _toggleTorch() async {
    await _controller.toggleTorch();
    setState(() => _torchOn = !_torchOn);
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final total = _entries.length;
    final duplicates = _entries.values.where((e) => e.duplicate).length;
    final pending = total - duplicates;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => _CameraError(
              message: error.errorCode.name,
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _ScanOverlayPainter()),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                _buildTopBar(),
                const Spacer(),
                _buildPanel(total, duplicates, pending),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 顶部返回、标题与手电筒。
  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(0),
            icon: const Icon(Icons.arrow_back_ios_new, size: 20),
            color: Colors.white,
          ),
          const Text(
            '扫码入库',
            style: TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: _toggleTorch,
            icon: Icon(_torchOn ? Icons.flash_on : Icons.flash_off),
            color: _torchOn ? const Color(0xFFFFD60A) : Colors.white,
          ),
        ],
      ),
    );
  }

  /// 底部结果面板：计数、列表与操作。
  Widget _buildPanel(int total, int duplicates, int pending) {
    return Container(
      height: 300,
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Color(0xFF111827),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                '本次扫描 $total 件',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              if (duplicates > 0)
                Text(
                  '重复 $duplicates',
                  style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 12),
                ),
              const Spacer(),
              Text(
                '待入库 $pending',
                style: const TextStyle(color: Color(0xFF86EFAC), fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _entries.isEmpty
                ? const Center(
                    child: Text(
                      '将快递条码对准取景框，支持连续扫描',
                      style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
                    ),
                  )
                : ListView.separated(
                    itemCount: _entries.length,
                    separatorBuilder: (_, _) => const Divider(
                      height: 1,
                      color: Color(0xFF1F2937),
                    ),
                    itemBuilder: (context, index) {
                      final entry = _entries.values
                          .toList()
                          .reversed
                          .elementAt(index);
                      return _buildEntryRow(entry);
                    },
                  ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _saving ? null : _manualInput,
                  icon: const Icon(Icons.keyboard, size: 18),
                  label: const Text('手输单号'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    side: const BorderSide(color: Color(0xFF374151)),
                    minimumSize: const Size(0, 46),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: _saving ? null : _commit,
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(pending > 0 ? '完成入库（$pending）' : '完成'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 单条扫描记录。
  Widget _buildEntryRow(_ScanEntry entry) {
    final info = entry.info;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Icon(
            entry.duplicate ? Icons.error_outline : Icons.check_circle_outline,
            size: 18,
            color: entry.duplicate
                ? const Color(0xFFFCA5A5)
                : const Color(0xFF86EFAC),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  info.normalized,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  entry.duplicate
                      ? '已存在，不会重复入库'
                      : '${info.carrier.isEmpty ? '未知快递' : info.carrier}'
                          '${info.suspicious ? ' · ${info.hint}' : ''}',
                  style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 11),
                ),
              ],
            ),
          ),
          Text(
            entry.source.label,
            style: const TextStyle(color: Color(0xFF6B7280), fontSize: 11),
          ),
        ],
      ),
    );
  }
}

/// 取景框遮罩与四角高亮。
class _ScanOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final frame = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.38),
      width: size.width * 0.74,
      height: size.width * 0.52,
    );
    final mask = Paint()..color = Colors.black.withValues(alpha: 0.45);
    final path = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(RRect.fromRectAndRadius(frame, const Radius.circular(16)))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, mask);

    final border = Paint()
      ..color = Colors.white.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawRRect(
      RRect.fromRectAndRadius(frame, const Radius.circular(16)),
      border,
    );

    final corner = Paint()
      ..color = AppColors.brand
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;
    const len = 22.0;
    final r = frame;
    canvas
      ..drawLine(r.topLeft, r.topLeft + const Offset(len, 0), corner)
      ..drawLine(r.topLeft, r.topLeft + const Offset(0, len), corner)
      ..drawLine(r.topRight, r.topRight + const Offset(-len, 0), corner)
      ..drawLine(r.topRight, r.topRight + const Offset(0, len), corner)
      ..drawLine(r.bottomLeft, r.bottomLeft + const Offset(len, 0), corner)
      ..drawLine(r.bottomLeft, r.bottomLeft + const Offset(0, -len), corner)
      ..drawLine(r.bottomRight, r.bottomRight + const Offset(-len, 0), corner)
      ..drawLine(r.bottomRight, r.bottomRight + const Offset(0, -len), corner);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 相机不可用时的兜底界面。
class _CameraError extends StatelessWidget {
  const _CameraError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.no_photography_outlined,
                  color: Colors.white70, size: 40),
              const SizedBox(height: 14),
              const Text(
                '相机不可用',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '请检查相机权限后重试（$message）',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(0),
                child: const Text('返回'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
