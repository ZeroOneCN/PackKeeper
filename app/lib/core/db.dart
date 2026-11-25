import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';
import 'tracking.dart';

/// 平台种子数据：首次建库时写入，用户可继续自建。
const _seedPlatforms = <(String, int)>[
  ('京东', 0xFFE1251B),
  ('淘宝', 0xFFFF5000),
  ('抖音', 0xFF161823),
  ('拼多多', 0xFFE02E24),
  ('小红书', 0xFFFF2442),
  ('1688', 0xFFFF6A00),
  ('其他', 0xFF64748B),
];

/// 平台默认展示顺序（账号台账等处统一按此排序）。
const _platformOrder = <String>[
  '京东',
  '淘宝',
  '抖音',
  '拼多多',
  '小红书',
  '1688',
  '其他',
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
      version: 4,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
    );
    return _db!;
  }

  /// 数据库升级：v1 → v2 新增商品库与订单成本/路径字段；v2 → v3 重排平台顺序。
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE products (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          spec TEXT NOT NULL DEFAULT '',
          cost REAL,
          price REAL,
          note TEXT NOT NULL DEFAULT '',
          created_at INTEGER NOT NULL
        )
      ''');
      await db.execute('ALTER TABLE orders ADD COLUMN product_id TEXT');
      await db.execute('ALTER TABLE orders ADD COLUMN cost REAL');
      await db.execute(
        "ALTER TABLE orders ADD COLUMN route TEXT NOT NULL DEFAULT 'warehouse'",
      );
    }
    if (oldVersion < 3) {
      await _applyPlatformOrder(db);
    }
    if (oldVersion < 4) {
      await db.execute('''
        CREATE TABLE shipments (
          id TEXT PRIMARY KEY,
          carrier TEXT NOT NULL DEFAULT '',
          tracking_no TEXT NOT NULL DEFAULT '',
          fee REAL NOT NULL DEFAULT 0,
          shipped_at INTEGER NOT NULL,
          note TEXT NOT NULL DEFAULT '',
          created_at INTEGER NOT NULL
        )
      ''');
      await db.execute('ALTER TABLE parcels ADD COLUMN shipment_id TEXT');
      await db.execute(
        'CREATE INDEX idx_parcels_shipment ON parcels (shipment_id)',
      );
    }
  }

  /// 按 [_platformOrder] 重排现有平台，其余自建平台排在末尾。
  ///
  /// 参数：[db] 数据库连接。
  Future<void> _applyPlatformOrder(DatabaseExecutor db) async {
    for (var i = 0; i < _platformOrder.length; i++) {
      await db.update(
        'platforms',
        {'sort': i},
        where: 'name = ?',
        whereArgs: [_platformOrder[i]],
      );
    }
    final placeholders = List.filled(_platformOrder.length, '?').join(', ');
    final others = await db.query(
      'platforms',
      columns: ['id'],
      where: 'name NOT IN ($placeholders)',
      whereArgs: _platformOrder,
      orderBy: 'sort ASC, created_at ASC',
    );
    for (var i = 0; i < others.length; i++) {
      await db.update(
        'platforms',
        {'sort': 100 + i},
        where: 'id = ?',
        whereArgs: [others[i]['id']],
      );
    }
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
        shipment_id TEXT,
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
        product_id TEXT,
        cost REAL,
        route TEXT NOT NULL DEFAULT 'warehouse',
        FOREIGN KEY (account_id) REFERENCES accounts (id)
      )
    ''');
    await db.execute('''
      CREATE TABLE products (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        spec TEXT NOT NULL DEFAULT '',
        cost REAL,
        price REAL,
        note TEXT NOT NULL DEFAULT '',
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE shipments (
        id TEXT PRIMARY KEY,
        carrier TEXT NOT NULL DEFAULT '',
        tracking_no TEXT NOT NULL DEFAULT '',
        fee REAL NOT NULL DEFAULT 0,
        shipped_at INTEGER NOT NULL,
        note TEXT NOT NULL DEFAULT '',
        created_at INTEGER NOT NULL
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
    await db.execute(
      'CREATE INDEX idx_parcels_shipment ON parcels (shipment_id)',
    );
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

  /// 重命名平台。
  ///
  /// 参数：[id] 平台主键；[name] 新名称（重名会抛数据库唯一约束异常）。
  Future<void> renamePlatform({required String id, required String name}) async {
    final db = await database;
    await db.update(
      'platforms',
      {'name': name.trim()},
      where: 'id = ?',
      whereArgs: [id],
    );
    await _audit(db, 'platform.update', 'platform', id, name.trim());
  }

  /// 删除平台。
  ///
  /// 参数：[id] 平台主键。平台下仍有账号时抛出 [StateError]。
  Future<void> deletePlatform(String id) async {
    final db = await database;
    final count = Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM accounts WHERE platform_id = ?',
            [id],
          ),
        ) ??
        0;
    if (count > 0) {
      throw StateError('该平台下还有 $count 个账号，无法删除');
    }
    final rows = await db.query(
      'platforms',
      columns: ['name'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return;
    await db.delete('platforms', where: 'id = ?', whereArgs: [id]);
    await _audit(
      db,
      'platform.delete',
      'platform',
      id,
      (rows.first['name'] as String?) ?? '',
    );
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

  /// 删除平台账号。
  ///
  /// 参数：[id] 账号主键。
  /// 该账号下的包裹会退回待认领池；若账号仍关联代下单订单则抛出
  /// [StateError]，由界面提示用户先处理订单。
  Future<void> deleteAccount(String id) async {
    final db = await database;
    final orderCount = Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM orders WHERE account_id = ?',
            [id],
          ),
        ) ??
        0;
    if (orderCount > 0) {
      throw StateError('该账号下还有 $orderCount 笔代下单订单，无法删除');
    }
    final rows = await db.query(
      'accounts',
      columns: ['alias'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return;
    await db.transaction((txn) async {
      await txn.update(
        'parcels',
        {'account_id': null, 'status': ParcelStatus.pending.name},
        where: 'account_id = ?',
        whereArgs: [id],
      );
      await txn.delete('accounts', where: 'id = ?', whereArgs: [id]);
    });
    await _audit(
      db,
      'account.delete',
      'account',
      id,
      (rows.first['alias'] as String?) ?? '',
    );
  }

  /// 删除一条包裹记录（待认领池清理误扫件）。
  ///
  /// 参数：[id] 包裹主键。
  Future<void> deleteParcel(String id) async {
    final db = await database;
    final rows = await db.query(
      'parcels',
      columns: ['tracking_no'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return;
    await db.delete('parcels', where: 'id = ?', whereArgs: [id]);
    await _audit(
      db,
      'parcel.delete',
      'parcel',
      id,
      (rows.first['tracking_no'] as String?) ?? '',
    );
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

  /// 可加入转寄批次的包裹：尚未寄出、未完成且未关联批次。
  Future<List<ParcelModel>> shipableParcels() async {
    final db = await database;
    final rows = await db.query(
      'parcels',
      where: 'shipment_id IS NULL AND status IN (?, ?, ?)',
      whereArgs: [
        ParcelStatus.pending.name,
        ParcelStatus.assigned.name,
        ParcelStatus.inbound.name,
      ],
      orderBy: 'scanned_at DESC',
      limit: 500,
    );
    return rows.map(ParcelModel.fromMap).toList();
  }

  /// 查询转寄批次列表（带包裹数量）。
  ///
  /// 参数：[keyword] 可选快递公司/运单号/备注模糊搜索。
  Future<List<ShipmentView>> shipments({String keyword = ''}) async {
    final db = await database;
    final where = <String>[];
    final args = <Object?>[];
    final trimmed = keyword.trim();
    if (trimmed.isNotEmpty) {
      where.add('(s.carrier LIKE ? OR s.tracking_no LIKE ? OR s.note LIKE ?)');
      final like = '%$trimmed%';
      args.addAll([like, like, like]);
    }
    final rows = await db.rawQuery(
      '''
      SELECT s.*,
             (SELECT COUNT(*) FROM parcels p WHERE p.shipment_id = s.id) AS parcel_count,
             (SELECT COUNT(*) FROM parcels p
                JOIN orders o ON o.id = p.order_id
               WHERE p.shipment_id = s.id) AS order_count
      FROM shipments s
      ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'}
      ORDER BY s.shipped_at DESC, s.created_at DESC
      ''',
      args,
    );
    return rows
        .map(
          (row) => ShipmentView(
            shipment: ShipmentModel.fromMap(row),
            parcelCount: (row['parcel_count'] as int?) ?? 0,
            orderCount: (row['order_count'] as int?) ?? 0,
          ),
        )
        .toList();
  }

  /// 查询批次已关联的包裹主键集合。
  ///
  /// 参数：[shipmentId] 批次主键。
  Future<Set<String>> shipmentParcelIds(String shipmentId) async {
    final db = await database;
    final rows = await db.query(
      'parcels',
      columns: ['id'],
      where: 'shipment_id = ?',
      whereArgs: [shipmentId],
    );
    return rows.map((row) => row['id'] as String).toSet();
  }

  /// 查询批次内已关联的包裹。
  ///
  /// 参数：[shipmentId] 批次主键。
  Future<List<ParcelModel>> shipmentParcels(String shipmentId) async {
    final db = await database;
    final rows = await db.query(
      'parcels',
      where: 'shipment_id = ?',
      whereArgs: [shipmentId],
      orderBy: 'scanned_at DESC',
    );
    return rows.map(ParcelModel.fromMap).toList();
  }

  /// 查询批次内包裹及其关联订单，供批次详情展示。
  ///
  /// 参数：[shipmentId] 批次主键。
  Future<List<ShipmentParcelView>> shipmentParcelViews(String shipmentId) async {
    final db = await database;
    final rows = await db.rawQuery(
      '''
      SELECT p.*,
             o.title AS order_title,
             o.amount AS order_amount,
             a.alias AS account_alias,
             pl.name AS platform_name
      FROM parcels p
      LEFT JOIN orders o ON o.id = p.order_id
      LEFT JOIN accounts a ON a.id = p.account_id
      LEFT JOIN platforms pl ON pl.id = a.platform_id
      WHERE p.shipment_id = ?
      ORDER BY p.scanned_at DESC
      ''',
      [shipmentId],
    );
    return rows
        .map(
          (row) => ShipmentParcelView(
            parcel: ParcelModel.fromMap(row),
            orderTitle: (row['order_title'] as String?) ?? '',
            platformName: (row['platform_name'] as String?) ?? '',
            accountAlias: (row['account_alias'] as String?) ?? '',
            amount: (row['order_amount'] as num?)?.toDouble(),
          ),
        )
        .toList();
  }

  /// 调整批次内包裹：移除已选包裹并加入新包裹。
  ///
  /// 参数：[shipmentId] 批次主键；[addIds] 新增包裹；[removeIds] 移出包裹。
  /// 移出的包裹恢复为已入库，新增的包裹置为已出库。
  Future<void> setShipmentParcels({
    required String shipmentId,
    List<String> addIds = const [],
    List<String> removeIds = const [],
  }) async {
    if (addIds.isEmpty && removeIds.isEmpty) return;
    final db = await database;
    await db.transaction((txn) async {
      if (removeIds.isNotEmpty) {
        final placeholders = List.filled(removeIds.length, '?').join(', ');
        await txn.rawUpdate(
          'UPDATE parcels SET shipment_id = NULL, status = ? '
          'WHERE shipment_id = ? AND id IN ($placeholders)',
          [ParcelStatus.inbound.name, shipmentId, ...removeIds],
        );
      }
      if (addIds.isNotEmpty) {
        final placeholders = List.filled(addIds.length, '?').join(', ');
        await txn.rawUpdate(
          'UPDATE parcels SET shipment_id = ?, status = ? WHERE id IN ($placeholders)',
          [shipmentId, ParcelStatus.outbound.name, ...addIds],
        );
      }
      await _audit(
        txn,
        'shipment.parcels',
        'shipment',
        shipmentId,
        '新增 ${addIds.length} 件，移出 ${removeIds.length} 件',
      );
    });
  }

  /// 查询可绑定订单的包裹：尚未关联订单且不是异常件。
  ///
  /// 参数：[keyword] 可选运单号/快递公司模糊搜索。
  Future<List<ParcelModel>> unboundParcels({String keyword = ''}) async {
    final db = await database;
    final where = <String>['order_id IS NULL', 'status <> ?'];
    final args = <Object?>[ParcelStatus.exception.name];
    final trimmed = keyword.trim();
    if (trimmed.isNotEmpty) {
      where.add('(tracking_no LIKE ? OR carrier LIKE ?)');
      args.addAll(['%$trimmed%', '%$trimmed%']);
    }
    final rows = await db.query(
      'parcels',
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'scanned_at DESC',
      limit: 300,
    );
    return rows.map(ParcelModel.fromMap).toList();
  }

  /// 新建转寄批次：写入批次并把所选包裹置为已出库。
  ///
  /// 参数：[carrier] 快递公司；[trackingNo] 运单号；[fee] 快递费；
  /// [shippedAt] 寄出时间；[note] 备注；[parcelIds] 关联包裹主键。
  /// 返回：新批次主键。
  Future<String> addShipment({
    required String carrier,
    required String trackingNo,
    required double fee,
    required int shippedAt,
    String note = '',
    required List<String> parcelIds,
  }) async {
    final db = await database;
    final id = _uuid.v4();
    await db.transaction((txn) async {
      await txn.insert('shipments', {
        'id': id,
        'carrier': carrier.trim(),
        'tracking_no': trackingNo.trim(),
        'fee': fee,
        'shipped_at': shippedAt,
        'note': note.trim(),
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
      if (parcelIds.isNotEmpty) {
        final placeholders = List.filled(parcelIds.length, '?').join(', ');
        await txn.rawUpdate(
          'UPDATE parcels SET shipment_id = ?, status = ? WHERE id IN ($placeholders)',
          [id, ParcelStatus.outbound.name, ...parcelIds],
        );
      }
      await _audit(
        txn,
        'shipment.create',
        'shipment',
        id,
        '${carrier.trim()} ${trackingNo.trim()} 运费 ${fee.toStringAsFixed(2)}',
      );
    });
    return id;
  }

  /// 修改转寄批次的基础信息。
  ///
  /// 参数：[id] 批次主键；[carrier] 快递公司；[trackingNo] 运单号；
  /// [fee] 快递费；[shippedAt] 寄出时间；[note] 备注。
  Future<void> updateShipment({
    required String id,
    required String carrier,
    required String trackingNo,
    required double fee,
    required int shippedAt,
    String note = '',
  }) async {
    final db = await database;
    await db.update(
      'shipments',
      {
        'carrier': carrier.trim(),
        'tracking_no': trackingNo.trim(),
        'fee': fee,
        'shipped_at': shippedAt,
        'note': note.trim(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    await _audit(
      db,
      'shipment.update',
      'shipment',
      id,
      '${carrier.trim()} ${trackingNo.trim()} 运费 ${fee.toStringAsFixed(2)}',
    );
  }

  /// 删除转寄批次：包裹保留并恢复为已入库。
  ///
  /// 参数：[id] 批次主键。
  Future<void> deleteShipment(String id) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.update(
        'parcels',
        {
          'shipment_id': null,
          'status': ParcelStatus.inbound.name,
        },
        where: 'shipment_id = ?',
        whereArgs: [id],
      );
      await txn.delete('shipments', where: 'id = ?', whereArgs: [id]);
      await _audit(txn, 'shipment.delete', 'shipment', id, '');
    });
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
  /// [platformOrderNo] 平台订单号；[addressText] 收货地址；[trackingNo] 物流单号；
  /// [productId] 关联商品；[cost] 采购成本；[route] 履约路径。
  /// 返回：订单主键。
  Future<String> addOrder({
    required String accountId,
    String title = '',
    double? amount,
    String platformOrderNo = '',
    String addressText = '',
    String trackingNo = '',
    String? productId,
    double? cost,
    OrderRoute route = OrderRoute.warehouse,
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
      'product_id': productId,
      'cost': cost,
      'route': route.name,
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

  /// 商品库列表，按创建时间倒序。
  ///
  /// 参数：[keyword] 可选商品名/规格模糊搜索。
  Future<List<ProductModel>> products({String? keyword}) async {
    final db = await database;
    final where = <String>[];
    final args = <Object?>[];
    if (keyword != null && keyword.trim().isNotEmpty) {
      where.add('(name LIKE ? OR spec LIKE ?)');
      final like = '%${keyword.trim()}%';
      args.add(like);
      args.add(like);
    }
    final rows = await db.query(
      'products',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'created_at DESC',
    );
    return rows.map(ProductModel.fromMap).toList();
  }

  /// 新增商品。
  ///
  /// 参数：[name] 商品名；[spec] 规格；[cost] 采购成本；[price] 售价；
  /// [note] 备注。返回新商品主键。
  Future<String> addProduct({
    required String name,
    String spec = '',
    double? cost,
    double? price,
    String note = '',
  }) async {
    final db = await database;
    final id = _uuid.v4();
    await db.insert('products', {
      'id': id,
      'name': name.trim(),
      'spec': spec.trim(),
      'cost': cost,
      'price': price,
      'note': note.trim(),
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
    await _audit(db, 'product.create', 'product', id, name.trim());
    return id;
  }

  /// 更新商品信息。
  ///
  /// 参数：[id] 商品主键；其余字段含义同 [addProduct]。
  Future<void> updateProduct({
    required String id,
    required String name,
    String spec = '',
    double? cost,
    double? price,
    String note = '',
  }) async {
    final db = await database;
    await db.update(
      'products',
      {
        'name': name.trim(),
        'spec': spec.trim(),
        'cost': cost,
        'price': price,
        'note': note.trim(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    await _audit(db, 'product.update', 'product', id, name.trim());
  }

  /// 删除商品；已引用该商品的订单会保留并把商品字段置空。
  ///
  /// 参数：[id] 商品主键。
  Future<void> deleteProduct(String id) async {
    final db = await database;
    final rows = await db.query(
      'products',
      columns: ['name'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return;
    await db.transaction((txn) async {
      await txn.update(
        'orders',
        {'product_id': null},
        where: 'product_id = ?',
        whereArgs: [id],
      );
      await txn.delete('products', where: 'id = ?', whereArgs: [id]);
    });
    await _audit(
      db,
      'product.delete',
      'product',
      id,
      (rows.first['name'] as String?) ?? '',
    );
  }

  /// 删除订单；已关联的包裹保留并解除关联。
  ///
  /// 参数：[id] 订单主键。
  Future<void> deleteOrder(String id) async {
    final db = await database;
    final rows = await db.query(
      'orders',
      columns: ['title', 'platform_order_no'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return;
    await db.transaction((txn) async {
      await txn.update(
        'parcels',
        {'order_id': null},
        where: 'order_id = ?',
        whereArgs: [id],
      );
      await txn.delete('orders', where: 'id = ?', whereArgs: [id]);
    });
    final title = (rows.first['title'] as String?)?.trim() ?? '';
    final label = title.isNotEmpty
        ? title
        : ((rows.first['platform_order_no'] as String?) ?? '');
    await _audit(db, 'order.delete', 'order', id, label);
  }

  /// 统计某个时间区间内的订单经营数据（销售额、成本、快递费、净利润）。
  ///
  /// 参数：[start] 统计起始时间（含）；[end] 可选结束时间（不含）。
  Future<BusinessSummary> orderSummary(DateTime start, {DateTime? end}) async {
    final db = await database;
    final args = <Object?>[start.millisecondsSinceEpoch];
    var where = 'ordered_at >= ?';
    var feeWhere = 'shipped_at >= ?';
    if (end != null) {
      where += ' AND ordered_at < ?';
      feeWhere += ' AND shipped_at < ?';
      args.add(end.millisecondsSinceEpoch);
    }
    final rows = await db.rawQuery(
      '''
      SELECT COUNT(*) AS c,
             COALESCE(SUM(amount), 0) AS sales,
             COALESCE(SUM(cost), 0) AS cost
      FROM orders WHERE $where
      ''',
      args,
    );
    final feeRows = await db.rawQuery(
      'SELECT COALESCE(SUM(fee), 0) AS fee FROM shipments WHERE $feeWhere',
      args,
    );
    final shippingFee = feeRows.isEmpty
        ? 0.0
        : (((feeRows.first['fee'] as num?) ?? 0)).toDouble();
    if (rows.isEmpty) {
      return BusinessSummary(
        orderCount: 0,
        sales: 0,
        cost: 0,
        shippingFee: shippingFee,
      );
    }
    final row = rows.first;
    return BusinessSummary(
      orderCount: (row['c'] as int?) ?? 0,
      sales: ((row['sales'] as num?) ?? 0).toDouble(),
      cost: ((row['cost'] as num?) ?? 0).toDouble(),
      shippingFee: shippingFee,
    );
  }

  /// 待补物流单号的订单（列表带账号与平台信息）。
  ///
  /// 参数：[limit] 返回上限。
  Future<List<OrderView>> pendingTrackingOrders({int limit = 20}) async {
    final db = await database;
    final rows = await db.rawQuery(
      '''
      SELECT o.*, a.alias AS account_alias, p.name AS platform_name
      FROM orders o
      JOIN accounts a ON a.id = o.account_id
      JOIN platforms p ON p.id = a.platform_id
      WHERE o.tracking_no = ''
      ORDER BY o.created_at DESC
      LIMIT ?
      ''',
      [limit],
    );
    return rows.map((row) {
      return OrderView(
        order: OrderModel.fromMap(row),
        accountAlias: (row['account_alias'] as String?) ?? '',
        platformName: (row['platform_name'] as String?) ?? '',
      );
    }).toList();
  }

  /// 查询订单列表（联表带出账号与平台信息）。
  ///
  /// 参数：[keyword] 可选关键词，匹配商品标题、平台单号、物流单号、地址与账号别名；
  /// [platformId] 可选平台过滤；[limit] 返回上限。
  Future<List<OrderView>> orderList({
    String keyword = '',
    String? platformId,
    int limit = 200,
  }) async {
    final db = await database;
    final where = <String>[];
    final args = <Object?>[];
    final trimmed = keyword.trim();
    if (trimmed.isNotEmpty) {
      where.add(
        '(o.title LIKE ? OR o.platform_order_no LIKE ? OR o.tracking_no LIKE ? '
        'OR o.address_text LIKE ? OR a.alias LIKE ?)',
      );
      final like = '%$trimmed%';
      for (var i = 0; i < 5; i++) {
        args.add(like);
      }
    }
    if (platformId != null && platformId.isNotEmpty) {
      where.add('a.platform_id = ?');
      args.add(platformId);
    }
    args.add(limit);
    final rows = await db.rawQuery(
      '''
      SELECT o.*, a.alias AS account_alias, p.name AS platform_name
      FROM orders o
      JOIN accounts a ON a.id = o.account_id
      JOIN platforms p ON p.id = a.platform_id
      ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'}
      ORDER BY o.ordered_at DESC, o.created_at DESC
      LIMIT ?
      ''',
      args,
    );
    return rows.map((row) {
      return OrderView(
        order: OrderModel.fromMap(row),
        accountAlias: (row['account_alias'] as String?) ?? '',
        platformName: (row['platform_name'] as String?) ?? '',
      );
    }).toList();
  }

  /// 查询某物流单号已被多少笔订单占用。
  ///
  /// 参数：[trackingNo] 原始物流单号（内部会做规范化）。
  Future<int> orderCountByTracking(String trackingNo) async {
    final db = await database;
    final normalized = parseTracking(trackingNo).normalized;
    if (normalized.isEmpty) return 0;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM orders WHERE tracking_no = ?',
      [normalized],
    );
    return _countOf(rows);
  }

  /// 为订单补录物流单号；若该单号已有包裹则同步建立归属。
  ///
  /// 参数：[orderId] 订单主键；[trackingNo] 物流单号。
  Future<void> updateOrderTracking({
    required String orderId,
    required String trackingNo,
  }) async {
    final db = await database;
    final info = parseTracking(trackingNo);
    final rows = await db.query(
      'orders',
      columns: ['account_id'],
      where: 'id = ?',
      whereArgs: [orderId],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final accountId = rows.first['account_id'] as String;
    await db.update(
      'orders',
      {'tracking_no': info.normalized},
      where: 'id = ?',
      whereArgs: [orderId],
    );
    await _audit(db, 'order.tracking', 'order', orderId, info.normalized);
    if (info.normalized.isEmpty) return;
    final parcel = await findByTracking(info.normalized);
    if (parcel == null) return;
    await db.update(
      'parcels',
      {
        'account_id': accountId,
        'order_id': orderId,
        'status': ParcelStatus.assigned.name,
      },
      where: 'id = ?',
      whereArgs: [parcel.id],
    );
    await _audit(db, 'parcel.assigned_by_order', 'parcel', parcel.id, orderId);
  }

  /// 导出全部业务表为可 JSON 序列化的备份数据。
  ///
  /// 返回：包含版本号与各表记录的 Map，可直接 `jsonEncode` 落盘。
  Future<Map<String, Object?>> exportAll() async {
    final db = await database;
    final data = <String, Object?>{};
    for (final table in const [
      'platforms',
      'accounts',
      'products',
      'parcels',
      'orders',
      'shipments',
      'scan_events',
      'audit_logs',
    ]) {
      data[table] = await db.query(table);
    }
    return {
      'app': 'packkeeper',
      'version': 3,
      'exported_at': DateTime.now().millisecondsSinceEpoch,
      'data': data,
    };
  }

  /// 覆盖导入备份数据（事务内先清空业务表再按外键顺序写入）。
  ///
  /// 参数：[payload] 由 [exportAll] 生成的 JSON 反序列化结果。
  /// 返回：导入的账号/订单/包裹数量。
  /// 当结构不合法时抛出 [FormatException]。
  Future<({int accounts, int orders, int parcels})> importAll(
    Map<String, Object?> payload,
  ) async {
    final data = payload['data'];
    if (data is! Map) {
      throw const FormatException('备份文件缺少 data 字段');
    }
    final tables = <String, List<Map<String, Object?>>>{};
    for (final table in const [
      'platforms',
      'accounts',
      'products',
      'parcels',
      'orders',
      'shipments',
      'scan_events',
      'audit_logs',
    ]) {
      final raw = data[table];
      if (raw is! List) continue;
      tables[table] = raw
          .whereType<Map>()
          .map((row) => row.map((k, v) => MapEntry(k.toString(), v)))
          .toList();
    }
    if (!tables.containsKey('platforms') && !tables.containsKey('accounts')) {
      throw const FormatException('备份文件缺少平台或账号数据');
    }

    final db = await database;
    await db.transaction((txn) async {
      for (final table in const [
        'parcels',
        'orders',
        'shipments',
        'products',
        'accounts',
        'platforms',
        'scan_events',
        'audit_logs',
      ]) {
        await txn.delete(table);
      }
      for (final table in const [
        'platforms',
        'products',
        'accounts',
        'shipments',
        'parcels',
        'orders',
        'scan_events',
        'audit_logs',
      ]) {
        final rows = tables[table];
        if (rows == null || rows.isEmpty) continue;
        final batch = txn.batch();
        for (final row in rows) {
          batch.insert(table, row);
        }
        await batch.commit(noResult: true);
      }
      await txn.insert('audit_logs', {
        'action': 'data.import',
        'target_type': 'database',
        'target_id': 'all',
        'detail':
            'accounts=${tables['accounts']?.length ?? 0}, '
                'orders=${tables['orders']?.length ?? 0}, '
                'parcels=${tables['parcels']?.length ?? 0}',
        'ts': DateTime.now().millisecondsSinceEpoch,
      });
      await _applyPlatformOrder(txn);
    });
    return (
      accounts: tables['accounts']?.length ?? 0,
      orders: tables['orders']?.length ?? 0,
      parcels: tables['parcels']?.length ?? 0,
    );
  }

  /// 写一条审计日志。
  Future<void> _audit(
    DatabaseExecutor db,
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
