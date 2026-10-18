import 'package:drift/drift.dart' as d;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../providers/budget_providers.dart';
import '../../data/db.dart';
import '../../data/repositories/local/local_repository.dart';
import '../../utils/shared_ledger_picker_filter.dart';
import '../../widgets/ui/ui.dart';
import '../../widgets/biz/amount_editor_sheet.dart';
import '../../widgets/category/category_selector.dart';
import '../../widgets/transaction/transfer_form.dart';
import '../../styles/tokens.dart';
import '../../services/billing/post_processor.dart';
import '../../services/attachment_service.dart';
import '../../services/data/tx_author_service.dart';

/// 交易编辑器页面（钱迹式单页）
///
/// 顶部分段切换 支出/收入/转账；分类网格常驻上半区；底部内嵌金额面板
/// （账户 / 币种 / 备注 / 大金额 + 自绘键盘）。支持创建 / 编辑 / 复制。
/// quickAdd 参数保留兼容旧调用（现所有调用方均为 true），单页模式不再分支。
class TransactionEditorPage extends ConsumerStatefulWidget {
  final bool isCopy;
  final String initialKind; // 'expense', 'income', or 'transfer'
  final bool quickAdd;
  final int? initialCategoryId;
  final String? initialNote;
  final double? initialAmount;
  final DateTime? initialDate;
  final int? editingTransactionId;
  final int? initialAccountId;
  final int? initialToAccountId; // 转账时的目标账户
  final List<int>? initialTagIds; // 初始标签ID列表
  final bool initialExcludeFromStats; // 不计入收支，编辑模式回显
  final bool initialExcludeFromBudget; // 不计入预算，编辑模式回显
  // v30 多币种编辑回显(推隐含汇率用)
  final String? initialCurrencyCode;
  final double? initialNativeAmount;

  const TransactionEditorPage({
    super.key,
    this.isCopy = false,
    required this.initialKind,
    this.quickAdd = false,
    this.initialCategoryId,
    this.initialNote,
    this.initialAmount,
    this.initialDate,
    this.editingTransactionId,
    this.initialAccountId,
    this.initialToAccountId,
    this.initialTagIds,
    this.initialExcludeFromStats = false,
    this.initialExcludeFromBudget = false,
    this.initialCurrencyCode,
    this.initialNativeAmount,
  });

  /// Reuse business fields only; saving takes the normal creation path.
  factory TransactionEditorPage.copy({
    required Transaction source,
    required List<int> tagIds,
    DateTime? now,
  }) =>
      TransactionEditorPage(
        isCopy: true,
        initialKind: source.type,
        quickAdd: true,
        initialCategoryId: source.categorySyncIdOverride == null
            ? source.categoryId
            : syntheticIdForSyncId(source.categorySyncIdOverride!),
        initialAccountId: source.accountSyncIdOverride == null
            ? source.accountId
            : syntheticIdForSyncId(source.accountSyncIdOverride!),
        initialToAccountId: source.toAccountSyncIdOverride == null
            ? source.toAccountId
            : syntheticIdForSyncId(source.toAccountSyncIdOverride!),
        initialAmount: source.amount,
        initialDate: now ?? DateTime.now(),
        initialNote: source.note,
        initialTagIds: List.unmodifiable(tagIds),
        initialExcludeFromStats: source.excludeFromStats,
        initialExcludeFromBudget: source.excludeFromBudget,
        initialCurrencyCode: source.currencyCode,
        initialNativeAmount: source.nativeAmount,
      );

  @override
  ConsumerState<TransactionEditorPage> createState() =>
      _TransactionEditorPageState();
}

class _TransactionEditorPageState extends ConsumerState<TransactionEditorPage> {
  late String _kind; // 'expense' / 'income' / 'transfer'
  Category? _selectedCategory;
  int? _defaultAccountId; // 新建模式按类别异步解析的默认账户

  @override
  void initState() {
    super.initState();
    _kind = widget.initialKind;
    // 新建模式：异步解析默认账户（编辑/复制保持调用方传入值）
    if (_kind != 'transfer') {
      _resolveDefaultAccount();
    }
    // 编辑/复制模式：首帧后解析初始分类并选中（§7 共享账本 synthetic id 走
    // SharedLedger* 反查）；转账类型由 TransferForm 自行处理
    if (widget.initialCategoryId != null && _kind != 'transfer') {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final repo = ref.read(repositoryProvider);
        Category? c;
        if (widget.initialCategoryId! < 0 && repo is LocalRepository) {
          c = await repo.db
              .findCategoryBySyntheticId(widget.initialCategoryId!);
        } else {
          c = await repo.getCategoryById(widget.initialCategoryId!);
        }
        if (!mounted || c == null) return;
        final k = c.kind == 'income' ? 'income' : 'expense';
        setState(() {
          _kind = k;
          _selectedCategory = c;
        });
      });
    }
  }

  /// 新建模式默认账户：按当前类别（支出/收入默认账户可不同）异步解析。
  Future<void> _resolveDefaultAccount() async {
    if (widget.isCopy || widget.editingTransactionId != null) return;
    if (widget.initialAccountId != null) return;
    final ledgerId = ref.read(currentLedgerIdProvider);
    final acc = await _getDefaultAccountId(_kind, ledgerId);
    if (!mounted) return;
    setState(() => _defaultAccountId = acc);
  }

  void _switchKind(String kind) {
    if (kind == _kind) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _kind = kind;
      _selectedCategory = null;
    });
    if (kind != 'transfer') _resolveDefaultAccount();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final ledgerId = ref.read(currentLedgerIdProvider);

    return Scaffold(
      backgroundColor: BeeTokens.scaffoldBackground(context),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(context, l10n),
            Expanded(
              child: _kind == 'transfer'
                  ? TransferForm(
                      onTransferComplete: () {
                        Navigator.pop(context);
                      },
                      initialFromAccountId: widget.initialAccountId,
                      initialToAccountId: widget.initialToAccountId,
                      editingTransactionId: widget.editingTransactionId,
                      initialAmount: widget.initialAmount,
                      initialNote: widget.initialNote,
                      initialDate: widget.initialDate,
                      initialTagIds: widget.initialTagIds,
                      initialExcludeFromStats: widget.initialExcludeFromStats,
                      initialExcludeFromBudget: widget.initialExcludeFromBudget,
                      initialCurrencyCode: widget.initialCurrencyCode,
                      initialNativeAmount: widget.initialNativeAmount,
                    )
                  : Column(
                      children: [
                        // 分类网格常驻上半区（选中高亮由宿主持有）
                        Expanded(
                          child: CategorySelector(
                            key: ValueKey('cats-$_kind'),
                            kind: _kind,
                            selectedId: _selectedCategory?.id,
                            initialCategoryId: widget.initialCategoryId,
                            onCategorySelected: (c) =>
                                setState(() => _selectedCategory = c),
                          ),
                        ),
                        // 底部内嵌金额面板（钱迹式）
                        AmountEditorSheet(
                          key: ValueKey('amount-$_kind'),
                          categoryName: _selectedCategory?.name ?? '',
                          categoryId: _selectedCategory?.id,
                          categorySyncId: (_selectedCategory != null &&
                                  _selectedCategory!.id < 0)
                              ? _selectedCategory!.syncId
                              : null,
                          initialDate: widget.initialDate ?? DateTime.now(),
                          initialAmount: widget.initialAmount,
                          initialNote: widget.initialNote,
                          initialAccountId:
                              widget.initialAccountId ?? _defaultAccountId,
                          initialTagIds: widget.initialTagIds,
                          showAccountPicker: true,
                          ledgerId: ledgerId,
                          editingTransactionId: widget.editingTransactionId,
                          transactionKind: _kind,
                          initialExcludeFromStats:
                              widget.initialExcludeFromStats,
                          initialExcludeFromBudget:
                              widget.initialExcludeFromBudget,
                          initialCurrencyCode: widget.initialCurrencyCode,
                          initialNativeAmount: widget.initialNativeAmount,
                          allowContinueAdding: !widget.isCopy &&
                              widget.editingTransactionId == null,
                          embedded: true,
                          canSubmit: _selectedCategory != null,
                          onSubmit: _submitTransaction,
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// 顶部栏：X 关闭 + 支出/收入/转账 分段切换（钱迹式胶囊）
  Widget _buildHeader(BuildContext context, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: SizedBox(
        height: 44,
        child: Row(
          children: [
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: Icon(
                Icons.close_rounded,
                size: 24,
                color: BeeTokens.textPrimary(context),
              ),
            ),
            Expanded(child: Center(child: _buildSegmented(context, l10n))),
            const SizedBox(width: 48),
          ],
        ),
      ),
    );
  }

  Widget _buildSegmented(BuildContext context, AppLocalizations l10n) {
    final segments = [
      ('expense', l10n.categoryExpense),
      ('income', l10n.categoryIncome),
      ('transfer', l10n.transferTitle),
    ];
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      height: 34,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: BeeTokens.surfaceCapsule(context),
        borderRadius: BorderRadius.circular(17),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: segments.map((s) {
          final selected = _kind == s.$1;
          return GestureDetector(
            onTap: () => _switchKind(s.$1),
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected
                    ? BeeTokens.surfaceKey(context)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(15),
              ),
              child: Text(
                s.$2,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? primary : BeeTokens.textSecondary(context),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  /// 获取默认账户ID（验证币种匹配）
  Future<int?> _getDefaultAccountId(String kind, int ledgerId) async {
    try {
      // 1. 根据类型获取默认账户ID
      final defaultAccountId = kind == 'income'
          ? await ref.read(defaultIncomeAccountIdProvider.future)
          : await ref.read(defaultExpenseAccountIdProvider.future);

      if (defaultAccountId == null) return null;

      // 2. 获取账本币种
      final ledger = await ref.read(ledgerByIdProvider(ledgerId).future);
      if (ledger == null) return null;

      // 3. 获取默认账户信息
      final account =
          await ref.read(accountByIdProvider(defaultAccountId).future);
      if (account == null) return null;

      // 账户隐藏 #240 E3:默认账户已被隐藏时按「无默认」处理(defensive 兜底,
      // 正常路径下隐藏时已清 pref,这里防同步竞态等边缘情况)
      if (account.hidden) return null;

      // 4. 验证币种匹配
      if (account.currency != ledger.currency) return null;

      return defaultAccountId;
    } catch (e) {
      return null;
    }
  }

  /// 提交交易（原分类选中后的保存逻辑，迁移到单页模式）
  Future<void> _submitTransaction(AmountEditorResult res) async {
    final c = _selectedCategory;
    if (c == null) return; // canSubmit 已门控，双保险
    final kind = _kind;
    final ledgerId = ref.read(currentLedgerIdProvider);

    final repo = ref.read(repositoryProvider);
    final attachmentService = ref.read(attachmentServiceProvider);
    int transactionId;
    // §7 v25:Category 是来自 SharedLedger* 的 synthetic (id<0)时,
    // categoryId 留 null,override 走 syncId。同理对 account/toAccount。
    // res.accountId 可能也是 synthetic(Account picker 用同一规则)。
    final isSyntheticCategory = c.id < 0;
    final isSyntheticAccount = res.accountId != null && res.accountId! < 0;
    final categoryIdForWrite = isSyntheticCategory ? null : c.id;
    // synthetic / picker 返 null 时账户 id 写 null。
    // addTransaction 的 accountId 是 int?(直接传 null 即写 null);
    // updateTransaction 的 accountId 是 dynamic,dart null 被解释成
    // Value.absent(=不更新该字段) → 用户选"不选择账户"无效;必须显式
    // 传 d.Value<int?>(null) 才会真清空旧 accountId。
    final accountIdForAdd = isSyntheticAccount ? null : res.accountId;
    final accountIdForUpdate = d.Value<int?>(accountIdForAdd);
    final categoryOverride = isSyntheticCategory ? c.syncId : null;
    final accountOverride = isSyntheticAccount
        ? await _resolveSyncIdByAccountId(res.accountId!, ledgerId)
        : null;
    if (widget.editingTransactionId != null) {
      // 编辑模式：使用repository更新交易
      await repo.updateTransaction(
        id: widget.editingTransactionId!,
        type: kind,
        amount: res.amount,
        categoryId: categoryIdForWrite,
        note: res.note,
        happenedAt: res.date,
        accountId: accountIdForUpdate,
        categorySyncIdOverride: categoryOverride,
        accountSyncIdOverride: accountOverride,
        excludeFromStats: res.excludeFromStats,
        excludeFromBudget: res.excludeFromBudget,
        currencyCode: res.currencyCode,
        nativeAmount: res.nativeAmount,
      );
      transactionId = widget.editingTransactionId!;
      // 共享账本:本地 lastEditedByUserId 立即回填,UI 头像组直接展示
      // 当前 user 为编辑人(否则要等 server 下次 pull 才回来)
      await TxAuthorService.markEdited(ref, transactionId);
    } else {
      transactionId = await repo.addTransaction(
        ledgerId: ledgerId,
        type: kind,
        amount: res.amount,
        categoryId: categoryIdForWrite,
        happenedAt: res.date,
        note: res.note,
        accountId: accountIdForAdd,
        categorySyncIdOverride: categoryOverride,
        accountSyncIdOverride: accountOverride,
        excludeFromStats: res.excludeFromStats,
        excludeFromBudget: res.excludeFromBudget,
        currencyCode: res.currencyCode,
        nativeAmount: res.nativeAmount,
      );
      // 共享账本:新建本地 tx 也回填创建人 + 编辑人(同一个 user)
      await TxAuthorService.markCreated(ref, transactionId);
    }
    // 保存待上传的附件
    if (res.pendingAttachments.isNotEmpty) {
      await attachmentService.saveAttachments(
        transactionId: transactionId,
        sourceFiles: res.pendingAttachments,
        startIndex: 0,
      );
      // 刷新附件列表缓存
      ref.read(attachmentListRefreshProvider.notifier).state++;
    }
    // 更新标签关联
    // §7 共享账本:tag.id < 0 是 synthetic(Owner tag from SharedLedger*),
    // 主表 Tags 没该行,不能直接写 transaction_tags.tag_id。分两类:
    // - 正数 id → 写 transaction_tags 主表(老路径)
    // - 负数 id → 走 SharedLedgerTags 反查 syncId → 写 transaction_tag_overrides
    final normalTagIds = res.tagIds.where((id) => id >= 0).toList();
    final syntheticTagIds = res.tagIds.where((id) => id < 0).toList();

    if (normalTagIds.isNotEmpty) {
      await repo.updateTransactionTags(
        transactionId: transactionId,
        tagIds: normalTagIds,
      );
      ref.read(tagListRefreshProvider.notifier).state++;
    } else if (widget.editingTransactionId != null) {
      // 编辑模式没主表 tag → 清掉旧主表关联
      await repo.removeAllTagsFromTransaction(transactionId);
      ref.read(tagListRefreshProvider.notifier).state++;
    }

    // §7 写 override:先反查 tx.syncId + 把 synthetic tag_id 翻译成
    // Owner tag syncId,再 upsert 进 TransactionTagOverrides
    if (repo is LocalRepository) {
      final txRow = await (repo.db.select(repo.db.transactions)
            ..where((t) => t.id.equals(transactionId)))
          .getSingleOrNull();
      final txSyncId = txRow?.syncId;
      if (txSyncId != null) {
        await (repo.db.delete(repo.db.transactionTagOverrides)
              ..where((t) => t.transactionSyncId.equals(txSyncId)))
            .go();
        if (syntheticTagIds.isNotEmpty) {
          final allShared =
              await repo.db.select(repo.db.sharedLedgerTags).get();
          final now = DateTime.now().toUtc();
          for (final sid in syntheticTagIds) {
            for (final s in allShared) {
              if (syntheticIdForSyncId(s.syncId) == sid) {
                await repo.db.into(repo.db.transactionTagOverrides).insert(
                      TransactionTagOverridesCompanion.insert(
                        transactionSyncId: txSyncId,
                        tagSyncId: s.syncId,
                        createdAt: now,
                      ),
                    );
                break;
              }
            }
          }
          ref.read(tagListRefreshProvider.notifier).state++;
        }
        // 不重复 recordLedgerChange:addTransaction / updateTransaction 已登记,
        // push 时统一读 DB 最新状态,payload 自然含最新 overrides。
      }
    }
    // 统一处理：自动/手动同步与状态刷新（后台静默）
    PostProcessor.sync(ref, ledgerId: ledgerId);
    // 刷新：账本笔数与全局统计
    ref.invalidate(countsForLedgerProvider(ledgerId));
    ref.read(statsRefreshProvider.notifier).state++;
    // 刷新：预算数据
    ref.read(budgetRefreshProvider.notifier).state++;
    // 更新小组件数据（后台执行，不阻塞UI）
    if (mounted) {
      updateAppWidget(ref, context);
    }
    // 单页模式：普通保存关闭整页；「再记」留在本页继续录下一笔
    if (!res.continueAdding) {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    } else {
      if (mounted) {
        showToast(
          context,
          AppLocalizations.of(context).transactionSavedNextCategory,
        );
      }
    }
    // 反馈：轻微触感 + 系统点击音
    HapticFeedback.lightImpact();
    SystemSound.play(SystemSoundType.click);
  }

  /// §7 v25:account picker 返 synthetic Account(id<0)时,把 id 反查
  /// SharedLedgerAccounts 拿 syncId,写到 tx.accountSyncIdOverride。
  /// 失败返 null,调用方应回到 accountId int 路径(synthetic 不一致时的兜底)。
  Future<String?> _resolveSyncIdByAccountId(int accountId, int ledgerId) async {
    if (accountId >= 0) return null;
    final repo = ref.read(repositoryProvider);
    if (repo is! LocalRepository) return null;
    // 反查:本地 ledger.syncId → SharedLedgerAccounts ledgerSyncId 范围
    final ledger = await (repo.db.select(repo.db.ledgers)
          ..where((l) => l.id.equals(ledgerId)))
        .getSingleOrNull();
    if (ledger?.syncId == null) return null;
    final rows = await (repo.db.select(repo.db.sharedLedgerAccounts)
          ..where((t) => t.ledgerSyncId.equals(ledger!.syncId!)))
        .get();
    for (final r in rows) {
      if (syntheticIdForSyncId(r.syncId) == accountId) return r.syncId;
    }
    return null;
  }
}
