import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/app_events.dart';
import '../core/db.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../core/tracking.dart';
import '../widgets/common.dart';

/// 面单识别页：拍照 → 端侧 ML Kit 中文 OCR → 提取单号/尾号/地址 → 入库。
class WaybillPage extends StatefulWidget {
  const WaybillPage({super.key});

  @override
  State<WaybillPage> createState() => _WaybillPageState();
}

class _WaybillPageState extends State<WaybillPage> {
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _trackingCtrl = TextEditingController();
  final TextEditingController _carrierCtrl = TextEditingController();
  final TextEditingController _tailCtrl = TextEditingController();
  final TextEditingController _addressCtrl = TextEditingController();

  String _imagePath = '';
  String _ocrText = '';
  bool _busy = false;
  bool _suspicious = false;

  @override
  void dispose() {
    _trackingCtrl.dispose();
    _carrierCtrl.dispose();
    _tailCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  /// 拍照或从相册取图，并执行端侧 OCR 与字段提取。
  ///
  /// 参数：[source] 图片来源于相机或相册。
  Future<void> _pickAndRecognize(ImageSource source) async {
    XFile? file;
    try {
      file = await _picker.pickImage(source: source, imageQuality: 85);
    } catch (e) {
      if (mounted) showToast(context, '无法打开相机：$e');
      return;
    }
    if (file == null) return;

    setState(() {
      _busy = true;
      _imagePath = file!.path;
      _ocrText = '';
    });

    final recognizer = TextRecognizer(script: TextRecognitionScript.chinese);
    try {
      final input = InputImage.fromFilePath(file.path);
      final recognized = await recognizer.processImage(input);
      if (!mounted) return;
      final text = recognized.text;
      final candidate = extractTrackingCandidate(text);
      final info = parseTracking(candidate);
      setState(() {
        _ocrText = text;
        _trackingCtrl.text = info.normalized;
        _carrierCtrl.text = info.carrier;
        _tailCtrl.text = extractReceiverTail(text);
        _addressCtrl.text = extractAddress(text);
        _suspicious = info.suspicious;
      });
    } catch (e) {
      if (mounted) showToast(context, '识别失败：$e');
    } finally {
      await recognizer.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 保存面单图并把识别结果入库。
  Future<void> _save() async {
    final tracking = _trackingCtrl.text.trim();
    if (tracking.isEmpty) {
      showToast(context, '请填写运单号后再保存');
      return;
    }
    setState(() => _busy = true);
    try {
      String mediaPath = '';
      if (_imagePath.isNotEmpty) {
        final docs = await getApplicationDocumentsDirectory();
        final dir = Directory(p.join(docs.path, 'waybills'));
        await dir.create(recursive: true);
        mediaPath = p.join(
          dir.path,
          '${DateTime.now().millisecondsSinceEpoch}${p.extension(_imagePath)}',
        );
        await File(_imagePath).copy(mediaPath);
      }
      final result = await AppDatabase.instance.addParcel(
        trackingNo: tracking,
        source: ParcelSource.ocr,
        mediaPath: mediaPath,
        ocrRaw: _ocrText,
        receiverTail: _tailCtrl.text.trim(),
        addressText: _addressCtrl.text.trim(),
      );
      if (!mounted) return;
      if (result.created) {
        bumpDbRevision();
        showToast(context, '已入库 ${result.parcel.trackingNo}');
        Navigator.of(context).pop(true);
      } else {
        showToast(
          context,
          '单号 ${result.parcel.trackingNo} 已存在（${result.parcel.status.label}）',
        );
      }
    } catch (e) {
      if (mounted) showToast(context, '保存失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('面单识别')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          if (_imagePath.isEmpty) _buildCaptureCard() else ..._buildResult(),
          const SizedBox(height: 12),
          const Text(
            '识别在本机离线完成，面单原图仅用于留证存档。',
            style: TextStyle(fontSize: 11, color: AppColors.ink3),
          ),
        ],
      ),
    );
  }

  /// 未拍照时的引导卡片。
  Widget _buildCaptureCard() {
    return AppCard(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(
              color: AppColors.brandSoft,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.document_scanner_outlined,
              size: 32,
              color: AppColors.brandDeep,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            '拍摄快递面单',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '尽量正对、铺平、避免反光；单号会与条码交叉校验。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppColors.ink3, height: 1.5),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _busy
                  ? null
                  : () => _pickAndRecognize(ImageSource.camera),
              icon: const Icon(Icons.photo_camera_outlined, size: 18),
              label: const Text('拍照识别'),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed:
                  _busy ? null : () => _pickAndRecognize(ImageSource.gallery),
              icon: const Icon(Icons.photo_library_outlined, size: 18),
              label: const Text('从相册选择'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.ink2,
                minimumSize: const Size(0, 46),
                side: const BorderSide(color: AppColors.line),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 已拍照后的预览、OCR 文本与可编辑字段。
  List<Widget> _buildResult() {
    return [
      ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          children: [
            Image.file(
              File(_imagePath),
              height: 180,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                height: 180,
                color: AppColors.surface2,
                alignment: Alignment.center,
                child: const Text('图片加载失败'),
              ),
            ),
            Positioned(
              right: 8,
              top: 8,
              child: Material(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(999),
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: _busy
                      ? null
                      : () => _pickAndRecognize(ImageSource.camera),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Text(
                      '重拍',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      if (_busy) ...[
        const SizedBox(height: 12),
        const LinearProgressIndicator(minHeight: 3),
        const SizedBox(height: 6),
        const Text(
          '正在本机识别面单…',
          style: TextStyle(fontSize: 12, color: AppColors.ink3),
        ),
      ],
      const SectionHeader(title: '识别结果'),
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _trackingCtrl,
              textCapitalization: TextCapitalization.characters,
              decoration: appInput(
                label: '运单号',
                hint: '识别为空时请手动填写',
                suffix: _suspicious
                    ? const Icon(Icons.warning_amber_rounded,
                        color: AppColors.warn, size: 20)
                    : null,
              ),
            ),
            if (_suspicious) ...[
              const SizedBox(height: 6),
              const Text(
                '单号可能不完整，请对照面单核对',
                style: TextStyle(fontSize: 11, color: AppColors.warn),
              ),
            ],
            const SizedBox(height: 10),
            TextField(
              controller: _carrierCtrl,
              decoration: appInput(label: '快递公司', hint: '自动识别，可修改'),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _tailCtrl,
                    keyboardType: TextInputType.number,
                    decoration: appInput(label: '收件人尾号', hint: '后四位'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _addressCtrl,
                    decoration: appInput(label: '地址线索', hint: '省市区关键词'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      const SectionHeader(title: '面单原文'),
      AppCard(
        color: AppColors.surface2,
        child: Text(
          _ocrText.isEmpty ? '未识别到文字' : _ocrText,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.ink2,
            height: 1.6,
          ),
        ),
      ),
      const SizedBox(height: 18),
      SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: _busy ? null : _save,
          child: const Text('保存并加入待认领池'),
        ),
      ),
    ];
  }
}
