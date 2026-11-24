/// 包裹状态机。
enum ParcelStatus {
  pending('待认领'),
  assigned('已分配'),
  inbound('已入库'),
  outbound('已出库'),
  done('已完成'),
  exception('异常件');

  const ParcelStatus(this.label);

  /// 中文展示名。
  final String label;

  /// 从数据库字符串还原状态。
  static ParcelStatus fromDb(String value) {
    return ParcelStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => ParcelStatus.pending,
    );
  }
}

/// 包裹来源。
enum ParcelSource {
  barcode('扫码'),
  ocr('面单识别'),
  manual('手输');

  const ParcelSource(this.label);

  final String label;

  static ParcelSource fromDb(String value) {
    return ParcelSource.values.firstWhere(
      (e) => e.name == value,
      orElse: () => ParcelSource.manual,
    );
  }
}

/// 电商平台（淘宝/拼多多/京东等），可由用户自建。
class ShopPlatform {
  const ShopPlatform({
    required this.id,
    required this.name,
    required this.color,
    required this.sort,
  });

  final String id;
  final String name;

  /// ARGB 颜色值，用于列表标识。
  final int color;
  final int sort;

  factory ShopPlatform.fromMap(Map<String, Object?> map) {
    return ShopPlatform(
      id: map['id'] as String,
      name: map['name'] as String,
      color: (map['color'] as int?) ?? 0xFF64748B,
      sort: (map['sort'] as int?) ?? 0,
    );
  }
}

/// 平台账号台账：不存密码，只存别名与归属人。
class AccountModel {
  const AccountModel({
    required this.id,
    required this.platformId,
    required this.alias,
    required this.owner,
    required this.status,
    required this.note,
    required this.createdAt,
  });

  final String id;
  final String platformId;
  final String alias;
  final String owner;
  final String status;
  final String note;
  final int createdAt;

  factory AccountModel.fromMap(Map<String, Object?> map) {
    return AccountModel(
      id: map['id'] as String,
      platformId: map['platform_id'] as String,
      alias: map['alias'] as String,
      owner: (map['owner'] as String?) ?? '',
      status: (map['status'] as String?) ?? 'active',
      note: (map['note'] as String?) ?? '',
      createdAt: (map['created_at'] as int?) ?? 0,
    );
  }
}

/// 账号 + 平台信息的联表视图，供列表与下拉选择使用。
class AccountView {
  const AccountView({required this.account, required this.platform});

  final AccountModel account;
  final ShopPlatform platform;

  /// 展示文案：平台 · 账号别名。
  String get title => '${platform.name} · ${account.alias}';
}

/// 包裹记录。
class ParcelModel {
  const ParcelModel({
    required this.id,
    required this.trackingNo,
    required this.carrier,
    required this.status,
    required this.source,
    required this.scannedAt,
    required this.scannedBy,
    required this.ocrRaw,
    required this.receiverTail,
    required this.addressText,
    required this.mediaPath,
    required this.accountId,
    required this.orderId,
    required this.note,
  });

  final String id;
  final String trackingNo;
  final String carrier;
  final ParcelStatus status;
  final ParcelSource source;
  final int scannedAt;
  final String scannedBy;
  final String ocrRaw;
  final String receiverTail;
  final String addressText;
  final String mediaPath;
  final String? accountId;
  final String? orderId;
  final String note;

  factory ParcelModel.fromMap(Map<String, Object?> map) {
    return ParcelModel(
      id: map['id'] as String,
      trackingNo: map['tracking_no'] as String,
      carrier: (map['carrier'] as String?) ?? '',
      status: ParcelStatus.fromDb((map['status'] as String?) ?? 'pending'),
      source: ParcelSource.fromDb((map['source'] as String?) ?? 'manual'),
      scannedAt: (map['scanned_at'] as int?) ?? 0,
      scannedBy: (map['scanned_by'] as String?) ?? '',
      ocrRaw: (map['ocr_raw'] as String?) ?? '',
      receiverTail: (map['receiver_tail'] as String?) ?? '',
      addressText: (map['address_text'] as String?) ?? '',
      mediaPath: (map['media_path'] as String?) ?? '',
      accountId: map['account_id'] as String?,
      orderId: map['order_id'] as String?,
      note: (map['note'] as String?) ?? '',
    );
  }
}

/// 代下单记录。
class OrderModel {
  const OrderModel({
    required this.id,
    required this.accountId,
    required this.platformOrderNo,
    required this.title,
    required this.amount,
    required this.addressText,
    required this.trackingNo,
    required this.status,
    required this.orderedAt,
  });

  final String id;
  final String accountId;
  final String platformOrderNo;
  final String title;
  final double? amount;
  final String addressText;
  final String trackingNo;
  final String status;
  final int orderedAt;

  factory OrderModel.fromMap(Map<String, Object?> map) {
    return OrderModel(
      id: map['id'] as String,
      accountId: map['account_id'] as String,
      platformOrderNo: (map['platform_order_no'] as String?) ?? '',
      title: (map['title'] as String?) ?? '',
      amount: (map['amount'] as num?)?.toDouble(),
      addressText: (map['address_text'] as String?) ?? '',
      trackingNo: (map['tracking_no'] as String?) ?? '',
      status: (map['status'] as String?) ?? 'created',
      orderedAt: (map['ordered_at'] as int?) ?? 0,
    );
  }
}

/// 首页统计快照。
class DashboardStats {
  const DashboardStats({
    required this.todayScanned,
    required this.pending,
    required this.assigned,
    required this.accountCount,
    required this.orderCount,
  });

  final int todayScanned;
  final int pending;
  final int assigned;
  final int accountCount;
  final int orderCount;
}

/// 单个包裹入库结果，区分新建与已存在。
class ParcelUpsertResult {
  const ParcelUpsertResult({required this.parcel, required this.created});

  final ParcelModel parcel;
  final bool created;
}
