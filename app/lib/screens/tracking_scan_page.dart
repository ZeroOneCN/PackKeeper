import 'dart:async';

import 'package:app_settings/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:styled_widget/styled_widget.dart';

import '../core/tracking.dart';
import '../widgets/scan_overlay.dart';

/// 单次扫码取号页：扫到第一张运单条码即返回规范化单号。
class TrackingScanPage extends StatefulWidget {
  const TrackingScanPage({super.key});

  @override
  State<TrackingScanPage> createState() => _TrackingScanPageState();
}

class _TrackingScanPageState extends State<TrackingScanPage> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
  );

  bool _torchOn = false;
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 相机回调：取首个有效条码，规范化后立即返回。
  ///
  /// 参数：[capture] 本次识别的条码集合。
  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
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
    _done = true;
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop(info.normalized);
  }

  /// 切换手电筒。
  Future<void> _toggleTorch() async {
    await _controller.toggleTorch();
    setState(() => _torchOn = !_torchOn);
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
            errorBuilder: (context, error) => _CameraError(
              message: error.errorCode.name,
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: ScanOverlayPainter()),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                      color: Colors.white,
                    ),
                    const Text('扫码填入物流单号')
                        .textColor(Colors.white)
                        .fontSize(17)
                        .fontWeight(FontWeight.w600),
                    const Spacer(),
                    IconButton(
                      onPressed: _toggleTorch,
                      icon: Icon(_torchOn ? Icons.flash_on : Icons.flash_off),
                      color: _torchOn
                          ? const Color(0xFFFFD60A)
                          : Colors.white,
                    ),
                  ],
                ).padding(horizontal: 8, vertical: 6),
                const Spacer(),
                const Text('将快递条码对准取景框，识别后自动返回')
                    .textColor(Color(0xFF9CA3AF))
                    .fontSize(13)
                    .center(),
                const SizedBox(height: 28),
              ],
            ),
          ),
        ],
      ),
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
        const Icon(Icons.no_photography_outlined,
            color: Colors.white70, size: 40),
        const Text('相机不可用')
            .textColor(Colors.white)
            .fontSize(16)
            .fontWeight(FontWeight.w600)
            .padding(top: 14),
        Text('请检查相机权限后重试（$message）')
            .textColor(Colors.white54)
            .fontSize(12)
            .textAlignment(TextAlign.center)
            .padding(top: 6),
        Row(
          children: [
            OutlinedButton(
              onPressed: () => AppSettings.openAppSettings(),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Color(0xFF374151)),
                minimumSize: const Size(0, 46),
              ),
              child: const Text('去设置', maxLines: 1, softWrap: false),
            ).expanded(),
            const SizedBox(width: 10),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('返回', maxLines: 1, softWrap: false),
            ).expanded(),
          ],
        ).padding(top: 18),
      ],
    ).padding(horizontal: 32).center().backgroundColor(Colors.black);
  }
}
