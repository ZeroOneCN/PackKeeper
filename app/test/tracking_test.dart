import 'package:flutter_test/flutter_test.dart';
import 'package:packkeeper/core/tracking.dart';

void main() {
  group('运单号规范化与识别', () {
    test('去除空格与连字符并转大写', () {
      final info = parseTracking(' sf 1234-5678-9012 ');
      expect(info.normalized, 'SF123456789012');
      expect(info.carrier, '顺丰');
      expect(info.suspicious, isFalse);
    });

    test('空单号标记为可疑', () {
      expect(parseTracking('   ').suspicious, isTrue);
    });

    test('长度异常标记为可疑', () {
      final info = parseTracking('SF123');
      expect(info.suspicious, isTrue);
      expect(info.hint, contains('长度异常'));
    });

    test('13 位 77 开头识别为申通', () {
      expect(parseTracking('7730123456789').carrier, '申通');
    });
  });

  group('面单文本字段提取', () {
    const text = '''
      中通快递 ZTO
      运单号：78123456789012
      收件人：张三 13812345678
      广东省深圳市南山区科技园路 1 号
    ''';

    test('提取最长候选单号', () {
      expect(extractTrackingCandidate(text), '78123456789012');
    });

    test('提取手机号后四位', () {
      expect(extractReceiverTail(text), '5678');
    });

    test('提取地址行', () {
      expect(extractAddress(text), contains('广东省'));
    });
  });
}
