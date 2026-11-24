import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';
import 'tracking.dart';

/// 平台种子数据：首次建库时写入，用户可继续自建。
const _seedPlatforms = <(String, int)>[
  ('淘宝', 0xFFFF5000),
  ('拼多多', 0xFFE02E24),
  ('京东', 0xFFE1251B),
  ('1688', 0xFFFF6A00),
  ('抖音', 0xFF161823),
  ('小红书', 0xFFFF2442),
  ('其他', 0xFF64748B),
];

/// 本地 SQLite 数据层（P1 单机版）。
///
/// 所有写操作先落本地库并写审计日志，离线可用；后续 P2 在此基础上
/// 增加 change_log 与同步队列，不改动现有表语义。
class AppDatabase {
  AppDatabase._();

  /// 全局单例。
  static final AppDatabase instance = AppDatabase._();

  Database? _db;
  final Uuid _uuid = const Uuid();

  /// 获取数据库连接（首次调用时建库并写入种子数据）。
  Future<Database> get database async {
    if (_db != null) return _db!;
    final dir = await getDatabasesPath();
    final path = p.join(dir, 'packkeeper.db');
    _db = await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
    );
    return _db!;
  }

  /// 建表并写入平台种子数据。
  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE platforms (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL UNIQUE,
        color INTEGER NOT NULL,
        sort INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE accounts (
        id TEXT PRIMARY KEY,
        platform_id TEXT NOT NULL,
        alias TEXT NOT NULL,
        owner TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL DEFAULT 'active',
        note TEXT NOT NULL DEFAULT '',
        created_at INTEGER NOT NULL,
        FOREIGN KEY (platform_id) REFERENCES platforms (id)
      )
    ''');
    await db.execute('''
      CREATE TABLE parcels (
        id TEXT PRIMARY KEY,
        tracking_no TEXT NOT NULL UNIQUE,
        carrier TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL DEFAULT 'pending',
        source TEXT NOT NULL DEFAULT 'manual',
        scanned_at INTEGER NOT NULL,
        scanned_by TEXT NOT NULL DEFAULT '',
        ocr_raw TEXT NOT NULL DEFAULT '',
        receiver_tail TEXT NOT NULL DEFAULT '',
        address_text TEXT NOT NULL DEFAULT '',
        media_path TEXT NOT NULL DEFAULT '',
        account_id TEXT,
        order_id TEXT,
        note TEXT NOT NULL DEFAULT '',
        FOREIGN KEY (account_id) REFERENCES accounts (id)
      )
    ''');
    await db.execute('''
      CREATE TABLE orders (
        id TEXT PRIMARY KEY,
        account_id TEXT NOT NULL,
        platform_order_no TEXT NOT NULL DEFAULT '',
        title TEXT NOT NULL DEFAULT '',
        amount REAL,
        address_text TEXT NOT NULL DEFAULT '',
        tracking_no TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL DEFAULT 'created',
        ordered_at INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        FOREIGN KEY (account_id) REFERENCES accounts (id)
      )
    ''');
    await db.execute('''
      CREATE TABLE scan_events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tracking_no TEXT NOT NULL,
        source TEXT NOT NULL,
        ts INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE audit_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        action TEXT NOT NULL,
        target_type TEXT NOT NULL,
        target_id TEXT NOT NULL,
        detail TEXT NOT NULL DEFAULT '',
        ts INTEGER NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX idx_parcels_status ON parcels (status)');
    await db.execute('CREATE INDEX idx_parcels_scanned ON parcels (scanned_at)');
    await db.execute('CREATE INDEX idx_accounts_platform ON accounts (platform_id)');
    await db.execute('CREATE INDEX idx_orders_tracking ON orders (tracking_no)');

    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = db.batch();
    for (var i = 0; i < _seedPlatforms.length; i++) {
      final seed = _seedPlatforms[i];
      batch.insert('platforms', {
        'id': _uuid.v4(),
        'name': seed.$1,
        'color': seed.$2,
        'sort': i,
        'created_at': now,
      });
    }
    await batch.commit(noResult: true);
  }

  /// 查询全部平台，按排序值升序。
  Future<List<ShopPlatform>> platforms() async {
    final db = await database;
    final rows = await db.query('platforms', orderBy: 'sort ASC, created_at ASC');
    return rows.map(ShopPlatform.fromMap).toList();
  }

  /// 新增平台。
  ///
  /// 返回：新平台的主键。
  Future<String> addPlatform(String name, int color) async {
    final db = await database;
    final id = _uuid.v4();
    final maxSort = await db.rawQuery('SELECT MAX(sort) AS m FROM platforms');
    final nextSort = ((maxSort.first['m'] as int?) ?? 0) + 1;
    await db.insert('platforms', {
      'id': id,
      'name': name.trim(),
      'color': color,
      'sort': nextSort,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
    return id;
  }

  /// 查询账号台账（联表带出平台信息）。
  ///
  /// 参数：[platformId] 可选平台过滤；[keyword] 可选别名/归属人模糊搜索。
  Future<List<AccountView>> accountViews({
    String? platformId,
    String? keyword,
  }) async {
    final db = await database;
    final where = <String>[];
    final args = <Object?>[];
    if (platformId != null && platformId.isNotEmpty) {
      where.add('a.platform_id = ?');
      args.add(platformId);
    }
    if (keyword != null && keyword.trim().isNotEmpty) {
      where.add('(a.alias LIKE ? OR a.owner LIKE ?)');
      final like = '%${keyword.trim()}%';
      args.add(like);
      args.add(like);
    }
    final rows = await db.rawQuery(
      '''
      SELECT a.*, p.name AS platform_name, p.color AS platform_color, p.sort AS platform_sort
      FROM accounts a
      JOIN platforms p ON p.id = a.platform_id
      ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'}
      ORDER BY p.sort ASC, a.created_at ASC
      ''',
      args,
    );
    return rows.map((row) {
      return AccountView(
        account: AccountModel.fromMap(row),
        platform: ShopPlatform(
          id: row['platform_id'] as String,
          name: row['platform_name'] as String,
          color: (row['platform_color'] as int?) ?? 0xFF64748B,
          sort: (row['platform_sort'] as int?) ?? 0,
        ),
      );
    }).toList();
  }

  /// 新增平台账号。
  ///
  /// 参数：[platformId] 所属平台；[alias] 账号别名；[owner] 归属员工；
  /// [note] 备注。返回新账号主键。
  Future<String> addAccount({
    required String platformId,
    required String alias,
    String owner = '',
    String note = '',
  }) async {
    final db = await database;
    final id = _uuid.v4();
    await db.insert('accounts', {
      'id': id,
      'platform_id': platformId,
      'alias': alias.trim(),
      'owner': owner.trim(),
      'status': 'active',
      'note': note.trim(),
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
    await _audit(db, 'account.create', 'account', id, alias.trim());
    return id;
  }

  /// 更新平台账号信息。
  ///
  /// 参数：[id] 账号主键；[platformId] 所属平台；[alias] 账号别名；
  /// [owner] 归属员工；[note] 备注；[status] 状态（active/disabled）。
  Future<void> updateAccount({
    required String id,
    required String platformId,
    required String alias,
    String owner = '',
    String note = '',
    String status = 'active',
  }) async {
    final db = await database;
    await db.update(
      'accounts',
      {
        'platform_id': platformId,
        'alias': alias.trim(),
        'owner': owner.trim(),
        'note': note.trim(),
        'status': status,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    await _audit(db, 'account.update', 'account', id, alias.trim());
  }

  /// 按状态与关键词查询包裹。
  ///
  /// 参数：[status] 可选状态过滤；[keyword] 可选运单号模糊搜索；[limit] 上限。
  Future<List<ParcelModel>> parcels({
    ParcelStatus? status,
    String? keyword,
    int limit = 300,
  }) async {
    final db = await database;
    final where = <String>[];
    final args = <Object?>[];
    if (status != null) {
      where.add('status = ?');
      args.add(status.name);
    }
    if (keyword != null && keyword.trim().isNotEmpty) {
      where.add('tracking_no LIKE ?');
      args.add('%${keyword.trim().toUpperCase()}%');
    }
    final rows = await db.query(
      'parcels',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'scanned_at DESC',
      limit: limit,
    );
    return rows.map(ParcelModel.fromMap).toList();
  }

  /// 查询最近入库的包裹，用于首页。
  Future<List<ParcelModel>> recentParcels({int limit = 5}) async {
    final db = await database;
    final rows = await db.query(
      'parcels',
      orderBy: 'scanned_at DESC',
      limit: limit,
    );
    return rows.map(ParcelModel.fromMap).toList();
  }

  /// 按运单号查包裹，不存在返回 null。
  Future<ParcelModel?> findByTracking(String trackingNo) async {
    final db = await database;
    final normalized = parseTracking(trackingNo).normalized;
    final rows = await db.query(
      'parcels',
      where: 'tracking_no = ?',
      whereArgs: [normalized],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return ParcelModel.fromMap(rows.first);
  }

  /// 入库一个包裹。
  ///
  /// 参数：[trackingNo] 原始运单号；[source] 来源；[mediaPath] 面单图路径；
  /// [ocrRaw] OCR 原文；[receiverTail] 收件人尾号；[addressText] 地址线索。
  /// 返回：入库结果，已存在时 created 为 false 并返回已有记录。
  Future<ParcelUpsertResult> addParcel({
    required String trackingNo,
    required ParcelSource source,
    String mediaPath = '',
    String ocrRaw = '',
    String receiverTail = '',
    String addressText = '',
    String scannedBy = '本机',
  }) async {
    final db = await database;
    final info = parseTracking(trackingNo);
    final existing = await findByTracking(info.normalized);
    if (existing != null) {
      return ParcelUpsertResult(parcel: existing, created: false);
    }

    final id = _uuid.v4();
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('parcels', {
      'id': id,
      'tracking_no': info.normalized,
      'carrier': info.carrier,
      'status': ParcelStatus.pending.name,
      'source': source.name,
      'scanned_at': now,
      'scanned_by': scannedBy,
      'ocr_raw': ocrRaw,
      'receiver_tail': receiverTail,
      'address_text': addressText,
      'media_path': mediaPath,
      'note': '',
    });
    await db.insert('scan_events', {
      'tracking_no': info.normalized,
      'source': source.name,
      'ts': now,
    });
    await _audit(db, 'parcel.create', 'parcel', id, info.normalized);

    // 已存在同单号的代下单记录时自动关联，无需再人工分配。
    final orderRows = await db.query(
      'orders',
      where: 'tracking_no = ?',
      whereArgs: [info.normalized],
      limit: 1,
    );
    if (orderRows.isNotEmpty) {
      final order = OrderModel.fromMap(orderRows.first);
      await db.update(
        'parcels',
        {
          'account_id': order.accountId,
          'order_id': order.id,
          'status': ParcelStatus.assigned.name,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    }

    final saved = await db.query(
      'parcels',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return ParcelUpsertResult(
      parcel: ParcelModel.fromMap(saved.first),
      created: true,
    );
  }

  /// 批量把包裹分配到某个账号。
  ///
  /// 参数：[ids] 包裹主键列表；[accountId] 目标账号；[orderId] 可选订单。
  Future<void> assignParcels(
    List<String> ids,
    String accountId, {
    String? orderId,
  }) async {
    if (ids.isEmpty) return;
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = db.batch();
    for (final id in ids) {
      batch.update(
        'parcels',
        {
          'account_id': accountId,
          'order_id': orderId,
          'status': ParcelStatus.assigned.name,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      batch.insert('audit_logs', {
        'action': 'parcel.assign',
        'target_type': 'parcel',
        'target_id': id,
        'detail': 'account=$accountId',
        'ts': now,
      });
    }
    await batch.commit(noResult: true);
  }

  /// 批量标记异常件。
  ///
  /// 参数：[ids] 包裹主键列表；[reason] 异常原因。
  Future<void> markException(List<String> ids, {String reason = ''}) async {
    if (ids.isEmpty) return;
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = db.batch();
    for (final id in ids) {
      batch.update(
        'parcels',
        {'status': ParcelStatus.exception.name, 'note': reason},
        where: 'id = ?',
        whereArgs: [id],
      );
      batch.insert('audit_logs', {
        'action': 'parcel.exception',
        'target_type': 'parcel',
        'target_id': id,
        'detail': reason,
        'ts': now,
      });
    }
    await batch.commit(noResult: true);
  }

  /// 新增代下单记录；若物流单号已存在包裹则自动关联。
  ///
  /// 参数：[accountId] 下单账号；[title] 商品标题；[amount] 金额；
  /// [platformOrderNo] 平台订单号；[addressText] 收货地址；[trackingNo] 物流单号。
  /// 返回：订单主键。
  Future<String> addOrder({
    required String accountId,
    String title = '',
    double? amount,
    String platformOrderNo = '',
    String addressText = '',
    String trackingNo = '',
  }) async {
    final db = await database;
    final id = _uuid.v4();
    final now = DateTime.now().millisecondsSinceEpoch;
    final info = parseTracking(trackingNo);
    await db.insert('orders', {
      'id': id,
      'account_id': accountId,
      'platform_order_no': platformOrderNo.trim(),
      'title': title.trim(),
      'amount': amount,
      'address_text': addressText.trim(),
      'tracking_no': info.normalized,
      'status': 'created',
      'ordered_at': now,
      'created_at': now,
    });
    await _audit(db, 'order.create', 'order', id, info.normalized);

    if (info.normalized.isNotEmpty) {
      final parcel = await findByTracking(info.normalized);
      if (parcel != null) {
        await db.update(
          'parcels',
          {
            'account_id': accountId,
            'order_id': id,
            'status': ParcelStatus.assigned.name,
          },
          where: 'id = ?',
          whereArgs: [parcel.id],
        );
        await _audit(db, 'parcel.assigned_by_order', 'parcel', parcel.id, id);
      }
    }
    return id;
  }

  /// 首页统计：今日扫描、待认领、已分配、账号数、订单数。
  Future<DashboardStats> stats() async {
    final db = await database;
    final now = DateTime.now();
    final dayStart = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
    final today = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM parcels WHERE scanned_at >= ?',
      [dayStart],
    );
    final pending = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM parcels WHERE status = ?',
      [ParcelStatus.pending.name],
    );
    final assigned = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM parcels WHERE status != ?',
      [ParcelStatus.pending.name],
    );
    final accounts = await db.rawQuery('SELECT COUNT(*) AS c FROM accounts');
    final orders = await db.rawQuery('SELECT COUNT(*) AS c FROM orders');
    return DashboardStats(
      todayScanned: _countOf(today),
      pending: _countOf(pending),
      assigned: _countOf(assigned),
      accountCount: _countOf(accounts),
      orderCount: _countOf(orders),
    );
  }

  /// 读取 COUNT(*) 查询结果。
  int _countOf(List<Map<String, Object?>> rows) {
    if (rows.isEmpty) return 0;
    return (rows.first['c'] as int?) ?? 0;
  }

  /// 写一条审计日志。
  Future<void> _audit(
    Database db,
    String action,
    String targetType,
    String targetId,
    String detail,
  ) async {
    await db.insert('audit_logs', {
      'action': action,
      'target_type': targetType,
      'target_id': targetId,
      'detail': detail,
      'ts': DateTime.now().millisecondsSinceEpoch,
    });
  }
}
