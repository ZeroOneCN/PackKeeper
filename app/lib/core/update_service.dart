import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 更新服务根地址（apps.01iot.top 公开接口）。
///
/// 可通过 `--dart-define=UPDATE_BASE_URL=...` 指向联调环境，默认使用线上地址。
const String updateBaseUrl = String.fromEnvironment(
  'UPDATE_BASE_URL',
  defaultValue: 'https://apps.01iot.top',
);

/// 本应用包名，必须与上架 APK 解析出的包名一致。
const String appPackageName = 'com.packkeeper.packkeeper';

/// 远端发布版本信息。
class AppRelease {
  const AppRelease({
    required this.versionName,
    required this.versionCode,
    required this.changelog,
    required this.fileSize,
    required this.sha256,
    required this.downloadUrl,
    this.minSdk,
    this.minSupportedVersionCode,
    this.publishedAt,
  });

  /// 展示用版本名，例如 1.2.0。
  final String versionName;

  /// 用于比较的版本号（versionCode）。
  final int versionCode;

  /// 更新日志，可能包含换行。
  final String changelog;

  /// 安装包字节数。
  final int fileSize;

  /// 安装包 SHA-256，下载后用于校验。
  final String sha256;

  /// 带签名的下载地址，10 分钟有效。
  final String downloadUrl;

  /// 安装包解析出的最低 Android API。
  final int? minSdk;

  /// 低于该版本号时服务端要求强制更新。
  final int? minSupportedVersionCode;

  /// 发布时间。
  final DateTime? publishedAt;

  /// 从接口 JSON 构造发布信息。
  ///
  /// 参数：[json] 接口返回的 latest 对象。
  /// 返回：解析后的发布版本；字段缺失或类型错误时抛出 [FormatException]。
  factory AppRelease.fromJson(Map<String, dynamic> json) {
    final versionCode = json['versionCode'];
    final downloadUrl = json['downloadUrl'];
    final sha256 = json['sha256'];
    if (versionCode is! int || downloadUrl is! String || sha256 is! String) {
      throw const FormatException('更新信息缺少必要字段');
    }
    return AppRelease(
      versionName: (json['versionName'] as String?) ?? '$versionCode',
      versionCode: versionCode,
      changelog: (json['changelog'] as String?) ?? '',
      fileSize: (json['fileSize'] as num?)?.toInt() ?? 0,
      sha256: sha256,
      downloadUrl: downloadUrl,
      minSdk: (json['minSdk'] as num?)?.toInt(),
      minSupportedVersionCode:
          (json['minSupportedVersionCode'] as num?)?.toInt(),
      publishedAt: DateTime.tryParse((json['publishedAt'] as String?) ?? ''),
    );
  }
}

/// 更新检查结果。
class UpdateCheckResult {
  const UpdateCheckResult({
    required this.hasUpdate,
    required this.forceUpdate,
    this.reason,
    this.latest,
  });

  /// 是否存在更高版本的正式发布。
  final bool hasUpdate;

  /// 服务端是否标记为强制更新（已结合最低支持版本判断）。
  final bool forceUpdate;

  /// 服务端补充说明，例如命中了最低支持版本。
  final String? reason;

  /// 最新发布信息；无更新时为 null。
  final AppRelease? latest;

  /// 构造“无更新”结果。
  ///
  /// 参数：[reason] 服务端返回的状态说明。
  factory UpdateCheckResult.noUpdate([String? reason]) =>
      UpdateCheckResult(hasUpdate: false, forceUpdate: false, reason: reason);

  /// 从接口 JSON 构造检查结果。
  ///
  /// 参数：[json] 接口响应体；[currentVersionCode] 当前安装包的 versionCode。
  /// 返回：仅在远端版本号更高时标记 hasUpdate；低于最低支持版本时置为强制更新。
  factory UpdateCheckResult.fromJson(
    Map<String, dynamic> json, {
    required int currentVersionCode,
  }) {
    final latestJson = json['latest'];
    if (json['hasUpdate'] != true || latestJson is! Map<String, dynamic>) {
      return UpdateCheckResult.noUpdate(json['reason'] as String?);
    }
    final latest = AppRelease.fromJson(latestJson);
    if (latest.versionCode <= currentVersionCode) {
      return UpdateCheckResult.noUpdate(json['reason'] as String?);
    }
    final minSupported = latest.minSupportedVersionCode;
    final force = json['forceUpdate'] == true ||
        (minSupported != null && currentVersionCode < minSupported);
    return UpdateCheckResult(
      hasUpdate: true,
      forceUpdate: force,
      reason: json['reason'] as String?,
      latest: latest,
    );
  }
}

/// 下载进度。
class UpdateProgress {
  const UpdateProgress({required this.received, required this.total});

  /// 已接收字节数。
  final int received;

  /// 总字节数，未知时为 0。
  final int total;

  /// 下载进度比例（0~1），总长度未知时返回 null。
  double? get ratio => total <= 0 ? null : (received / total).clamp(0, 1);
}

/// 更新过程中的可读错误。
class UpdateException implements Exception {
  const UpdateException(this.message);

  /// 可直接展示给用户的错误文案。
  final String message;

  @override
  String toString() => message;
}

/// 内置更新服务：检查版本、下载并校验安装包。
class UpdateService {
  UpdateService._();

  /// 检查是否有新版本。
  ///
  /// 参数：[currentVersionCode] 当前安装包的 versionCode。
  /// 返回：更新检查结果；包名未上架或接口返回 404 时视为无更新。
  /// 异常：网络不可用、超时或服务端异常时抛出 [UpdateException]。
  static Future<UpdateCheckResult> checkForUpdate(int currentVersionCode) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final uri = Uri.parse('$updateBaseUrl/api/update/check').replace(
        queryParameters: {
          'packageName': appPackageName,
          'versionCode': '$currentVersionCode',
        },
      );
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request
          .close()
          .timeout(const Duration(seconds: 15));
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode == 404) {
        return UpdateCheckResult.noUpdate('NOT_FOUND');
      }
      if (response.statusCode == 429) {
        throw const UpdateException('检查过于频繁，请稍后重试');
      }
      if (response.statusCode != 200) {
        throw UpdateException('服务器返回 ${response.statusCode}');
      }
      final json = jsonDecode(body);
      if (json is! Map<String, dynamic>) {
        throw const UpdateException('更新数据格式异常');
      }
      return UpdateCheckResult.fromJson(
        json,
        currentVersionCode: currentVersionCode,
      );
    } on UpdateException {
      rethrow;
    } on SocketException {
      throw const UpdateException('网络不可用，请检查网络后重试');
    } on TimeoutException {
      throw const UpdateException('检查更新超时，请稍后重试');
    } on FormatException {
      throw const UpdateException('更新数据格式异常');
    } finally {
      client.close(force: true);
    }
  }

  /// 下载并校验安装包。
  ///
  /// 参数：[release] 目标版本；[onProgress] 下载进度回调（可选）。
  /// 返回：校验通过的 APK 文件（位于应用缓存目录）。
  /// 异常：链接过期、网络失败或 SHA-256 不一致时抛出 [UpdateException]。
  static Future<File> downloadApk(
    AppRelease release, {
    void Function(UpdateProgress progress)? onProgress,
  }) async {
    final dir = await getTemporaryDirectory();
    final safeName = release.versionName.replaceAll(RegExp(r'[^\w.\-]'), '_');
    final file = File(p.join(dir.path, '包裹管家-$safeName-${release.versionCode}.apk'));
    if (await file.exists()) await file.delete();

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    IOSink? sink;
    try {
      final request = await client.getUrl(Uri.parse(release.downloadUrl));
      final response = await request
          .close()
          .timeout(const Duration(seconds: 30));
      if (response.statusCode == 410) {
        throw const UpdateException('下载链接已过期，请重新检查更新');
      }
      if (response.statusCode != 200) {
        throw UpdateException('下载失败（${response.statusCode}）');
      }
      final total = response.contentLength > 0
          ? response.contentLength
          : release.fileSize;
      sink = file.openWrite();
      final digestSink = _DigestSink();
      final hasher = sha256.startChunkedConversion(digestSink);
      var received = 0;
      await for (final chunk in response) {
        sink.add(chunk);
        hasher.add(chunk);
        received += chunk.length;
        onProgress?.call(UpdateProgress(received: received, total: total));
      }
      await sink.flush();
      await sink.close();
      sink = null;
      hasher.close();
      final digest = digestSink.value?.toString() ?? '';
      if (digest.toLowerCase() != release.sha256.trim().toLowerCase()) {
        await file.delete();
        throw const UpdateException('安装包校验失败，请重新下载');
      }
      return file;
    } on UpdateException {
      rethrow;
    } on SocketException {
      throw const UpdateException('下载中断，请检查网络后重试');
    } on TimeoutException {
      throw const UpdateException('下载超时，请重新下载');
    } finally {
      if (sink != null) await sink.close();
      client.close(force: true);
    }
  }
}

/// 收集 SHA-256 摘要的 Sink，避免整包载入内存。
class _DigestSink implements Sink<Digest> {
  /// 最后一次写入的摘要。
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
