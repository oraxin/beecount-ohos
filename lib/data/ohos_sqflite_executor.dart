import 'dart:async';
import 'dart:io';

import 'package:drift/backends.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as s;

/// OHOS 专用的 drift-on-sqflite 执行器。
///
/// 与 `drift_sqflite` 包的 [SqfliteQueryExecutor] 唯一区别在事务策略：
/// - drift_sqflite 用 `NoTransactionDelegate` —— drift 降级为发送
///   `BEGIN TRANSACTION` / `COMMIT` 文本语句。官方 sqflite（Android/iOS）
///   能执行该文本，但 openharmony-sig 的 RDB 适配层不认识它
///   （`DatabaseException(syntax error) sql 'BEGIN TRANSACTION'`），
///   导致 OHOS 上所有 drift 事务（batch/transaction）全部失败。
/// - 这里改用 [SupportedTransactionDelegate]，走 sqflite 原生事务 API
///   （RDB 适配层的 transactionStart/Commit），真机已验证可用。
///
/// 其余逻辑（打开/批量/语句执行）与 drift_sqflite 一致；当上游包提供
/// 等价能力时可用它替换掉本文件。
class _OhosSqfliteDelegate extends DatabaseDelegate {
  late s.Database db;
  bool _isOpen = false;

  final String path;

  bool singleInstance;

  _OhosSqfliteDelegate(this.path, {this.singleInstance = true});

  @override
  late final DbVersionDelegate versionDelegate =
      _OhosSqfliteVersionDelegate(db);

  @override
  TransactionDelegate get transactionDelegate => _OhosTransactionDelegate(this);

  @override
  bool get isOpen => _isOpen;

  @override
  Future<void> open(QueryExecutorUser user) async {
    // 与 drift_sqflite 不同：不用 getDatabasesPath()，直接把相对路径交给
    // RDB 适配层解析到应用沙箱数据库目录（P0 验证结论，路径行为一致）。
    final resolvedPath = p.isAbsolute(path) ? path : path;

    final file = File(resolvedPath);
    // drift_sqflite 的 creator 钩子在 OHOS 侧用不到（SeedService 负责建数据），
    // 保持 openDatabase 行为一致即可。
    if (!file.existsSync()) {
      // sqflite 会在 open 时创建文件，无需手动处理。
    }

    db = await s.openDatabase(
      resolvedPath,
      singleInstance: singleInstance,
    );
    _isOpen = true;
  }

  @override
  Future<void> close() {
    return db.close();
  }

  @override
  Future<void> runBatched(BatchedStatements statements) async {
    final batch = db.batch();

    for (final arg in statements.arguments) {
      batch.execute(statements.statements[arg.statementIndex], arg.arguments);
    }

    await batch.apply(noResult: true);
  }

  @override
  Future<void> runCustom(String statement, List<Object?> args) {
    return db.execute(statement, args);
  }

  @override
  Future<int> runInsert(String statement, List<Object?> args) {
    return db.rawInsert(statement, args);
  }

  @override
  Future<QueryResult> runSelect(String statement, List<Object?> args) async {
    final result = await db.rawQuery(statement, args);
    return QueryResult.fromRows(result);
  }

  @override
  Future<int> runUpdate(String statement, List<Object?> args) {
    return db.rawUpdate(statement, args);
  }
}

/// sqflite 原生事务委托：事务回调期间，sqflite 会把同一 Database 上的
/// 所有调用纳入该事务并独占调用队列，因此直接把 drift 的内部 executor
/// 传给事务回调即可。
class _OhosTransactionDelegate extends SupportedTransactionDelegate {
  final _OhosSqfliteDelegate _delegate;

  _OhosTransactionDelegate(this._delegate);

  @override
  FutureOr<void> startTransaction(Future Function(QueryDelegate) run) async {
    // ⚠️ 事务回调内必须用 txn 对象执行语句：用 Database 对象会把语句排队到
    // 事务完成之后 → drift 在事务内等结果 → 死锁（真机复现：保存永久转圈）。
    await _delegate.db.transaction<void>((txn) async {
      await run(_TxnQueryDelegate(txn));
    });
  }

  @override
  FutureOr<void> Function(
    QueryDelegate outer,
    Future<void> Function(QueryDelegate) block,
  )? get startNested =>
      // sqflite 的 transaction() 不支持嵌套（嵌套调用会排队成新事务）。
      // 嵌套事务直接在外层事务内执行（SQLite 的 SAVEPOINT 文本语句在
      // RDB 适配层同样不受支持），牺牲部分回滚粒度换取可用性。
      (outer, block) => block(outer);
}

/// 事务期间的语句执行器：全部走事务回调的 [s.Transaction] 对象，
/// 保证语句真正落入当前事务（而非排队到事务之后 → 死锁）。
class _TxnQueryDelegate implements QueryDelegate {
  final s.Transaction txn;
  _TxnQueryDelegate(this.txn);

  @override
  Future<QueryResult> runSelect(String statement, List<Object?> args) async {
    final result = await txn.rawQuery(statement, args);
    return QueryResult.fromRows(result);
  }

  @override
  Future<int> runUpdate(String statement, List<Object?> args) {
    return txn.rawUpdate(statement, args);
  }

  @override
  Future<int> runInsert(String statement, List<Object?> args) {
    return txn.rawInsert(statement, args);
  }

  @override
  Future<void> runCustom(String statement, List<Object?> args) {
    return txn.execute(statement, args);
  }

  @override
  Future<void> runBatched(BatchedStatements statements) async {
    final batch = txn.batch();
    for (final arg in statements.arguments) {
      batch.execute(statements.statements[arg.statementIndex], arg.arguments);
    }
    await batch.apply(noResult: true);
  }
}

class _OhosSqfliteVersionDelegate extends DynamicVersionDelegate {
  final s.Database _db;

  _OhosSqfliteVersionDelegate(this._db);

  @override
  Future<int> get schemaVersion async {
    final result = await _db.rawQuery('PRAGMA user_version;');
    return result.single.values.first as int;
  }

  @override
  Future<void> setSchemaVersion(int version) async {
    await _db.rawUpdate('PRAGMA user_version = $version;');
  }
}

/// OHOS 上的 drift 查询执行器（sqflite/RDB 驱动 + 原生事务支持）。
class OhosSqfliteQueryExecutor extends DelegatedDatabase {
  /// A query executor that will store the database in the file declared by
  /// [path]. If [logStatements] is true, statements sent to the database will
  /// be [print]ed, which can be handy for debugging. The [singleInstance]
  /// parameter sets the corresponding parameter on [s.openDatabase].
  OhosSqfliteQueryExecutor({
    required String path,
    bool? logStatements,
    bool singleInstance = true,
  }) : super(
          _OhosSqfliteDelegate(path, singleInstance: singleInstance),
          logStatements: logStatements,
        );

  @override
  bool get isSequential => true;
}
