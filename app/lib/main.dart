import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/db.dart';
import 'core/theme.dart';
import 'screens/home_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 预热数据库：首帧前完成建库与种子写入，避免首页闪空。
  await AppDatabase.instance.database;
  runApp(const PackKeeperApp());
}

/// 应用根组件。
class PackKeeperApp extends StatelessWidget {
  const PackKeeperApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '包裹管家',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const HomeShell(),
    );
  }
}
