/// 运单号解析结果。
class TrackingInfo {
  const TrackingInfo({
    required this.normalized,
    required this.carrier,
    required this.suspicious,
    required this.hint,
  });

  /// 规范化后的单号（大写、去空格与连字符）。
  final String normalized;

  /// 推测的快递公司，未知时为空串。
  final String carrier;

  /// 是否疑似无效单号。
  final bool suspicious;

  /// 给用户的提示文案。
  final String hint;
}

const _prefixCarriers = <String, String>{
  'SF': '顺丰',
  'JD': '京东',
  'JT': '极兔',
  'YT': '圆通',
  'YTO': '圆通',
  'ZTO': '中通',
  'STO': '申通',
  'EMS': '邮政',
  'DPK': '德邦',
  'DBL': '德邦',
  'UC': '优速',
  'YD': '韵达',
};

/// 规范化并校验运单号。
///
/// 参数：[raw] 扫码或手输的原始字符串。
/// 返回：包含规范化单号、快递公司、可疑标记与提示的 TrackingInfo。
TrackingInfo parseTracking(String raw) {
  final normalized = raw.replaceAll(RegExp(r'[\s\-]'), '').toUpperCase();
  if (normalized.isEmpty) {
    return const TrackingInfo(
      normalized: '',
      carrier: '',
      suspicious: true,
      hint: '单号为空',
    );
  }
  if (!RegExp(r'^[A-Z0-9]+$').hasMatch(normalized)) {
    return TrackingInfo(
      normalized: normalized,
      carrier: '',
      suspicious: true,
      hint: '单号含非法字符',
    );
  }

  var carrier = '';
  for (final entry in _prefixCarriers.entries) {
    if (normalized.startsWith(entry.key)) {
      carrier = entry.value;
      break;
    }
  }
  if (carrier.isEmpty) {
    carrier = _guessByDigits(normalized) ?? '';
  }

  final len = normalized.length;
  if (len < 8 || len > 24) {
    return TrackingInfo(
      normalized: normalized,
      carrier: carrier,
      suspicious: true,
      hint: '单号长度异常（$len 位）',
    );
  }

  return TrackingInfo(
    normalized: normalized,
    carrier: carrier,
    suspicious: carrier.isEmpty,
    hint: carrier.isEmpty ? '未能识别快递公司，请人工核对' : '',
  );
}

/// 按数字前缀粗略推断快递公司。
///
/// 参数：[no] 纯数字或字母数字单号。
/// 返回：快递公司名，无法判断时返回 null。
String? _guessByDigits(String no) {
  if (!RegExp(r'^\d+$').hasMatch(no)) return null;
  final len = no.length;
  if (len == 13) {
    if (no.startsWith('43') || no.startsWith('31') || no.startsWith('38')) {
      return '韵达';
    }
    if (no.startsWith('77') || no.startsWith('88') || no.startsWith('66')) {
      return '申通';
    }
    if (no.startsWith('97') || no.startsWith('98')) {
      return '邮政';
    }
  }
  if ((len == 12 || len == 13 || len == 14) &&
      (no.startsWith('7') || no.startsWith('8'))) {
    return '中通';
  }
  if (len == 15 && no.startsWith('1')) return '京东';
  return null;
}

/// 从面单 OCR 文本中提取候选运单号。
///
/// 参数：[text] OCR 识别的整段文本。
/// 返回：最可能的运单号候选，未命中返回空串。
String extractTrackingCandidate(String text) {
  final matches = RegExp(r'[A-Z]{0,4}\d{9,20}').allMatches(text.toUpperCase());
  String best = '';
  for (final m in matches) {
    final candidate = m.group(0) ?? '';
    if (candidate.length > best.length) best = candidate;
  }
  return best;
}

/// 从面单文本中提取收件人手机号后四位。
///
/// 参数：[text] OCR 识别的整段文本。
/// 返回：四位尾号，未命中返回空串。
String extractReceiverTail(String text) {
  final m = RegExp(r'1[3-9]\d{9}').firstMatch(text);
  final phone = m?.group(0);
  if (phone == null || phone.length < 4) return '';
  return phone.substring(phone.length - 4);
}

/// 从面单文本中粗略提取地址行。
///
/// 参数：[text] OCR 识别的整段文本。
/// 返回：包含省/市/区/县关键词的最长行，未命中返回空串。
String extractAddress(String text) {
  String best = '';
  for (final line in text.split('\n')) {
    final t = line.trim();
    if (t.isEmpty) continue;
    // 排除单号、电话等容易含「号」字的干扰行。
    if (RegExp(r'单号|订单|电话|手机|快递员|取件码').hasMatch(t)) continue;
    if (RegExp(r'[省市区县镇乡街道路号]').hasMatch(t) && t.length > best.length) {
      best = t;
    }
  }
  return best;
}
