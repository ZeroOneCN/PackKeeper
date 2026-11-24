import 'package:flutter/foundation.dart';

/// 数据库变更信号：任何写操作后自增，页面监听后重新加载。
final ValueNotifier<int> dbRevision = ValueNotifier<int>(0);

/// 通知界面数据已变更。
void bumpDbRevision() {
  dbRevision.value = dbRevision.value + 1;
}
