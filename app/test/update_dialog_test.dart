import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:packkeeper/core/theme.dart';
import 'package:packkeeper/core/update_service.dart';
import 'package:packkeeper/widgets/update_dialog.dart';

/// 更新弹窗的展示与强制更新交互测试。
void main() {
  /// 构造测试用发布信息。
  ///
  /// 参数：[versionCode] 远端版本号；[minSupported] 最低支持版本号。
  /// 返回：用于弹窗渲染的发布版本。
  AppRelease buildRelease({
    int versionCode = 4029,
    int? minSupported = 1000,
  }) {
    return AppRelease(
      versionName: '1.0.1',
      versionCode: versionCode,
      changelog: '修复导入崩溃\n优化列表加载',
      fileSize: 104857600,
      sha256: 'abc123',
      downloadUrl: 'https://example.com/app.apk',
      minSupportedVersionCode: minSupported,
    );
  }

  testWidgets('普通更新可稍后处理', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: UpdateDialog(
          release: buildRelease(),
          currentVersion: '1.0.0',
          force: false,
        ),
      ),
    );

    expect(find.textContaining('发现新版本 v1.0.1'), findsOneWidget);
    expect(find.text('更新内容'), findsOneWidget);
    expect(find.textContaining('修复导入崩溃'), findsOneWidget);
    expect(find.text('稍后更新'), findsOneWidget);
    expect(find.text('立即更新'), findsOneWidget);
  });

  testWidgets('强制更新隐藏稍后按钮并展示说明', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: UpdateDialog(
          release: buildRelease(minSupported: 5000),
          currentVersion: '1.0.0',
          force: true,
          reason: '当前版本过低，请更新后继续使用',
        ),
      ),
    );

    expect(find.text('稍后更新'), findsNothing);
    expect(find.text('立即更新'), findsOneWidget);
    expect(find.text('当前版本过低，请更新后继续使用'), findsOneWidget);
  });
}
