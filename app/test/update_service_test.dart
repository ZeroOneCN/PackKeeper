import 'package:flutter_test/flutter_test.dart';
import 'package:packkeeper/core/update_service.dart';

/// 更新检查接口解析与强制更新语义测试。
void main() {
  /// 构造一份接口返回的 latest 对象。
  ///
  /// 参数：[versionCode] 远端版本号；[minSupported] 最低支持版本号。
  /// 返回：符合接口字段的 JSON Map。
  Map<String, dynamic> releaseJson({
    int versionCode = 4028,
    int? minSupported = 1000,
  }) {
    return {
      'versionName': '1.0.1',
      'versionCode': versionCode,
      'changelog': '修复导入崩溃\n优化列表加载',
      'fileSize': 104857600,
      'sha256': 'abc123',
      'minSdk': 24,
      'minSupportedVersionCode': minSupported,
      'downloadUrl': 'https://apps.01iot.top/api/download/x?exp=1&sig=y',
      'publishedAt': '2026-11-26T08:00:00.000Z',
    };
  }

  test('远端版本更高时返回更新信息', () {
    final result = UpdateCheckResult.fromJson(
      {'hasUpdate': true, 'forceUpdate': false, 'latest': releaseJson()},
      currentVersionCode: 4027,
    );
    expect(result.hasUpdate, isTrue);
    expect(result.forceUpdate, isFalse);
    expect(result.latest!.versionName, '1.0.1');
    expect(result.latest!.changelog, contains('修复导入崩溃'));
  });

  test('低于最低支持版本时强制更新', () {
    final result = UpdateCheckResult.fromJson(
      {
        'hasUpdate': true,
        'forceUpdate': false,
        'latest': releaseJson(minSupported: 5000),
      },
      currentVersionCode: 4027,
    );
    expect(result.hasUpdate, isTrue);
    expect(result.forceUpdate, isTrue);
  });

  test('服务端标记强制更新时生效', () {
    final result = UpdateCheckResult.fromJson(
      {
        'hasUpdate': true,
        'forceUpdate': true,
        'latest': releaseJson(),
      },
      currentVersionCode: 4027,
    );
    expect(result.forceUpdate, isTrue);
  });

  test('远端版本不高于当前版本时忽略更新', () {
    final result = UpdateCheckResult.fromJson(
      {'hasUpdate': true, 'latest': releaseJson(versionCode: 4027)},
      currentVersionCode: 4027,
    );
    expect(result.hasUpdate, isFalse);
    expect(result.latest, isNull);
  });

  test('hasUpdate=false 时 latest 为空', () {
    final result = UpdateCheckResult.fromJson(
      {'hasUpdate': false, 'forceUpdate': false, 'reason': 'NOT_FOUND'},
      currentVersionCode: 4027,
    );
    expect(result.hasUpdate, isFalse);
    expect(result.latest, isNull);
    expect(result.reason, 'NOT_FOUND');
  });

  test('缺少下载地址或校验值时抛出格式异常', () {
    expect(
      () => AppRelease.fromJson({
        'versionCode': 4028,
        'downloadUrl': 'https://example.com/a.apk',
      }),
      throwsFormatException,
    );
  });
}
