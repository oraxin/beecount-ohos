import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter_cloud_sync/flutter_cloud_sync.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:beecount/widgets/ui/wheel_date_picker.dart';
import '../../data/db.dart';
import '../../providers/shared_ledger_providers.dart';
import '../../styles/tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../services/data/note_history_service.dart';
import '../../models/note_history.dart';
import '../../services/attachment_service.dart';
import '../../providers.dart';
import '../../utils/ui_scale_extensions.dart';
import '../../utils/currencies.dart';
import '../../pages/tag/widgets/tag_selector.dart';
import 'note_picker_dialog.dart';
import 'account_selector.dart';
import '../currency/currency_picker_sheet.dart';
import '../currency/currency_flag.dart';
import '../ui/toast.dart';
import 'tag_chip.dart';
import '../../pages/attachment/attachment_preview_page.dart';
import '../../services/system/logger_service.dart';

/// 共享账本 tx 作者信息(创建人 + 最后编辑人)— 编辑器底部 sheet 用。
/// editingTransactionId=null(新建 tx)或非共享账本 → 返 null,widget 不渲染。
class _TxAuthorInfo {
  const _TxAuthorInfo({
    required this.creatorUserId,
    required this.lastEditedByUserId,
    required this.currentUserId,
    required this.members,
  });

  final String? creatorUserId;
  final String? lastEditedByUserId;
  final String? currentUserId;
  final List<BeeCountCloudLedgerMember> members;

  BeeCountCloudLedgerMember? memberOf(String? userId) {
    if (userId == null || userId.isEmpty) return null;
    for (final m in members) {
      if (m.userId == userId) return m;
    }
    return null;
  }
}

final _txAuthorInfoProvider =
    FutureProvider.autoDispose.family<_TxAuthorInfo?, int>((ref, txId) async {
  final repo = ref.watch(repositoryProvider);
  final tx = await repo.getTransactionById(txId);
  if (tx == null) return null;
  final ledger = await repo.getLedgerById(tx.ledgerId);
  if (ledger == null || !ledger.isShared) return null;
  final ledgerSyncId = ledger.syncId;
  if (ledgerSyncId == null || ledgerSyncId.isEmpty) return null;
  if (tx.createdByUserId == null && tx.lastEditedByUserId == null) return null;

  final cloud = await ref.watch(beecountCloudProviderInstance.future);
  if (cloud == null) return null;
  ref.watch(sharedResourceRefreshProvider);
  final me = await cloud.auth.currentUser;
  final members = await cloud.listMembers(ledgerId: ledgerSyncId);
  return _TxAuthorInfo(
    creatorUserId: tx.createdByUserId,
    lastEditedByUserId: tx.lastEditedByUserId,
    currentUserId: me?.id,
    members: members,
  );
});

/// 紧凑头像组 — UX 规则(用户指定):
///   - 创建人 != 编辑人:展示两个头像(long-press tooltip 区分"创建" / "最后编辑")
///   - 创建人 == 编辑人 == 自己:不展示(自己的 tx 看自己头像无意义)
///   - 创建人 == 编辑人 != 自己:展示一个头像(long-press tooltip "X 创建并编辑")
class _TxAuthorAvatars extends ConsumerWidget {
  const _TxAuthorAvatars({required this.editingTransactionId});

  final int editingTransactionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final infoAsync = ref.watch(_txAuthorInfoProvider(editingTransactionId));
    final info = infoAsync.valueOrNull;
    if (info == null) return const SizedBox.shrink();

    final creatorId = info.creatorUserId;
    final editorId = info.lastEditedByUserId;
    final meId = info.currentUserId;
    final sameUser = creatorId != null && creatorId == editorId;

    // 单人(创建 == 编辑)且就是自己 → 整体不显示
    if (sameUser && creatorId == meId) return const SizedBox.shrink();

    final cloud = ref.watch(beecountCloudProviderInstance).valueOrNull;
    final baseUrl = cloud?.baseUrl;

    final widgets = <Widget>[];
    if (sameUser) {
      // 同一人(非自己):展示一个头像,tooltip 提示"创建并编辑"
      widgets.add(_AvatarSlot(
        member: info.memberOf(creatorId),
        userIdFallback: creatorId,
        baseUrl: baseUrl,
        tooltipBuilder: (name) => l10n.sharedTxCreatedAndEditedBy(name),
      ));
    } else {
      // 创建人 + 编辑人是两个人:两个头像都展示
      if (creatorId != null) {
        widgets.add(_AvatarSlot(
          member: info.memberOf(creatorId),
          userIdFallback: creatorId,
          baseUrl: baseUrl,
          tooltipBuilder: (name) => l10n.sharedTxCreatedBy(name),
        ));
      }
      if (editorId != null && editorId != creatorId) {
        if (widgets.isNotEmpty) widgets.add(const SizedBox(width: 4));
        widgets.add(_AvatarSlot(
          member: info.memberOf(editorId),
          userIdFallback: editorId,
          baseUrl: baseUrl,
          tooltipBuilder: (name) => l10n.sharedTxEditedBy(name),
        ));
      }
    }
    if (widgets.isEmpty) return const SizedBox.shrink();
    return Row(mainAxisSize: MainAxisSize.min, children: widgets);
  }
}

/// 单个头像槽位 — 不管 member 是否查得到都返回一个 CircleAvatar(带 tooltip)。
/// long-press 触发 Tooltip,tooltip 文案带角色("X 创建" / "X 最后编辑" / ...)。
class _AvatarSlot extends StatelessWidget {
  const _AvatarSlot({
    required this.member,
    required this.userIdFallback,
    required this.baseUrl,
    required this.tooltipBuilder,
  });

  final BeeCountCloudLedgerMember? member;
  final String userIdFallback;
  final String? baseUrl;
  final String Function(String name) tooltipBuilder;

  @override
  Widget build(BuildContext context) {
    final m = member;
    final name = m != null
        ? (m.displayName?.isNotEmpty == true
            ? m.displayName!
            : m.email.split('@').first)
        : userIdFallback;
    final letter = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final rel = m?.avatarUrl;
    final base = baseUrl;
    final absolute = (rel != null && rel.isNotEmpty)
        ? (rel.startsWith('http') ? rel : (base != null ? '$base$rel' : null))
        : null;
    return Tooltip(
      message: tooltipBuilder(name),
      triggerMode: TooltipTriggerMode.longPress,
      child: CircleAvatar(
        radius: 11,
        backgroundColor: BeeTokens.surfaceCapsule(context),
        foregroundImage: absolute != null ? NetworkImage(absolute) : null,
        child: Text(
          letter,
          style: TextStyle(
            fontSize: 11,
            color: BeeTokens.textSecondary(context),
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

typedef AmountEditorResult = ({
  double amount,
  bool continueAdding,
  String? note,
  DateTime date,
  int? accountId,
  List<int> tagIds,
  List<File> pendingAttachments,
  bool excludeFromStats,
  bool excludeFromBudget,
  // v30 交易级多币种:交易币种(有账户=账户币种;无账户=手选,默认本位币)
  // 与折本位币快照(同币种 == amount;外币 = amount × 汇率,缺汇率已在提交前阻断)。
  String? currencyCode,
  double? nativeAmount,
});

class AmountEditorSheet extends ConsumerStatefulWidget {
  final String categoryName; // 仅用于上层提交，不在UI展示
  final int? categoryId; // 当前本地分类ID，用于筛选历史备注
  final String? categorySyncId; // 共享账本分类同步ID，用于筛选历史备注
  final DateTime initialDate;
  final double? initialAmount;
  final String? initialNote;
  final int? initialAccountId;
  final List<int>? initialTagIds; // 初始标签ID列表
  final bool showAccountPicker; // 是否显示账户选择
  final bool allowContinueAdding; // 双击完成后回到分类选择继续新建
  /// 提交回调。返回 Future 以便 sheet 等待保存完成：失败时复位提交状态，
  /// 否则「完成」按钮的 _isSubmitting 转圈永远不会消失（OHOS 真机 bug）。
  final Future<void> Function(AmountEditorResult) onSubmit;
  final int ledgerId;
  final int? editingTransactionId; // 编辑模式时的交易ID，用于显示已有附件
  final String transactionKind; // 'expense' / 'income' / 'transfer'，决定标记开关可见性
  final bool initialExcludeFromStats; // 不计入收支，编辑模式回显
  final bool initialExcludeFromBudget; // 不计入预算，编辑模式回显
  // v30 编辑模式回显:该笔的原币种与折算快照(用于推隐含汇率,只改备注时
  // 折算基准不漂移,.docs/multi-currency-ledger 01 §4.2)。
  final String? initialCurrencyCode;
  final double? initialNativeAmount;

  /// 嵌入页面模式（钱迹式单页记账）：true 时由宿主 Scaffold 的
  /// resizeToAvoidBottomInset 处理键盘，去掉底部弹窗专用的额外让位 padding。
  final bool embedded;

  /// 保存前置校验（如单页模式下必须先选分类）。false 时「保存/再记」置灰。
  final bool canSubmit;

  const AmountEditorSheet({
    super.key,
    required this.categoryName,
    this.categoryId,
    this.categorySyncId,
    required this.initialDate,
    this.initialAmount,
    this.initialNote,
    this.initialAccountId,
    this.initialTagIds,
    this.showAccountPicker = false,
    this.allowContinueAdding = false,
    required this.onSubmit,
    required this.ledgerId,
    this.editingTransactionId,
    this.transactionKind = 'expense',
    this.initialExcludeFromStats = false,
    this.initialExcludeFromBudget = false,
    this.initialCurrencyCode,
    this.initialNativeAmount,
    this.embedded = false,
    this.canSubmit = true,
  });

  @override
  ConsumerState<AmountEditorSheet> createState() => _AmountEditorSheetState();
}

class _AmountEditorSheetState extends ConsumerState<AmountEditorSheet> {
  late String _amountStr;
  late DateTime _date;
  int? _selectedAccountId;
  final bool _negative = false; // 显示用途，仅影响UI，不改变保存逻辑
  final TextEditingController _noteCtrl = TextEditingController();
  // 运算缓存：支持简单 + / - 键入累计
  double _acc = 0;
  String? _op; // 最近一次运算符，null 表示尚未进入运算模式
  // 两个运算符键各自独立的模式(false=加/减,true=乘/除),长按各自切换,互不影响。
  bool _mulKey1 = false; // 键1:+ ↔ ×
  bool _mulKey2 = false; // 键2:− ↔ ÷

  // 高频备注列表（包含使用次数）
  List<NoteHistoryEntry> _frequentNotes = [];

  // 备注框焦点节点
  final FocusNode _noteFocusNode = FocusNode();
  bool _noteFieldHasFocus = false;

  // 防重复提交标志
  bool _isSubmitting = false;

  // 已选标签ID列表
  late List<int> _selectedTagIds;

  // 待上传的附件列表（新建交易时）
  List<File> _pendingAttachments = [];

  // 交易标记（旗标弹窗）
  bool _excludeFromStats = false;
  bool _excludeFromBudget = false;

  // v30 交易级多币种(L7 自动探测 + L12 无账户手选)
  String? _pickedCurrency; // 无账户时手选的币种;null = 本位币
  String? _selectedAccountCurrency; // 所选账户的币种(异步查,null = 未选/未知)
  String? _rateStr; // 本笔汇率(字符串);编辑模式初值=隐含汇率,用户可改
  bool _rateManuallySet = false; // 手改/隐含汇率后不再被有效汇率覆盖
  bool _fetchingRate = false; // 正在自动拉取汇率(汇率行显示获取中)
  String? _rateFetchAttemptedFor; // 已自动拉过的币种(防循环重试)

  @override
  void initState() {
    super.initState();
    _date = widget.initialDate;
    _excludeFromStats = widget.initialExcludeFromStats;
    _excludeFromBudget = widget.initialExcludeFromBudget;
    _selectedAccountId = widget.initialAccountId;
    _selectedTagIds = List.from(widget.initialTagIds ?? []);
    _pickedCurrency = widget.initialCurrencyCode?.toUpperCase();
    // 编辑外币交易:汇率行初值 = 该笔隐含汇率(nativeAmount / amount),
    // 只改备注/分类时折算基准不漂移(01 §4.2)。
    final initAmount = widget.initialAmount ?? 0;
    final initNative = widget.initialNativeAmount;
    if (initNative != null && initAmount > 0 && initNative != initAmount) {
      _rateStr = (initNative / initAmount).toStringAsPrecision(6);
      _rateManuallySet = true;
    }
    if (widget.initialAccountId != null) {
      _loadAccountCurrency(widget.initialAccountId!);
    }
    // 保留原始小数（最多两位），避免编辑已有记录时小数被截断为整数
    final init = widget.initialAmount ?? 0;
    final s = init.toStringAsFixed(2);
    // 去除多余 0 和结尾的小数点
    final trimmed = s.contains('.')
        ? s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')
        : s;
    _amountStr = trimmed.isEmpty ? '0' : trimmed;
    _noteCtrl.text = widget.initialNote ?? '';

    // 监听焦点变化
    _noteFocusNode.addListener(() {
      setState(() {
        _noteFieldHasFocus = _noteFocusNode.hasFocus;
      });
    });

    // 加载最近使用的备注
    _loadRecentNotes();
  }

  @override
  void dispose() {
    _noteFocusNode.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant AmountEditorSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 嵌入页面模式：宿主切换/确认分类后，按新分类重载历史备注
    if (widget.categoryId != oldWidget.categoryId ||
        widget.categorySyncId != oldWidget.categorySyncId) {
      _loadRecentNotes();
    }
    // 嵌入页面模式：新建交易的默认账户由宿主异步解析，解析完成后注入
    // （initState 已跑过，这里补采纳；用户已手动选过账户则不打扰）
    if (widget.initialAccountId != oldWidget.initialAccountId &&
        _selectedAccountId == null &&
        widget.initialAccountId != null) {
      _selectedAccountId = widget.initialAccountId;
      _loadAccountCurrency(widget.initialAccountId!);
    }
  }

  Future<void> _loadRecentNotes() async {
    final repo = ref.read(repositoryProvider);
    final notes = await NoteHistoryService.getHistoryNotes(
      repository: repo,
      ledgerId: widget.ledgerId,
      scope: ref.read(noteHistoryScopeProvider),
      sort: ref.read(noteHistorySortProvider),
      categoryId: widget.categoryId,
      categorySyncId: widget.categorySyncId,
      limit: ref.read(noteHistoryLimitProvider),
    );
    if (!mounted) return; // 弹窗已关时不再 setState(widget 测试暴露的既有问题)
    setState(() {
      _frequentNotes = notes;
    });
  }

  Future<void> _loadAccountCurrency(int accountId) async {
    final repo = ref.read(repositoryProvider);
    // getAccountCurrencyByAnyId:正数查主表;负数是共享账本 Owner 资源的
    // synthetic id(§7),查镜像表 —— 否则成员选 Owner 外币账户会被静默
    // 解析成本位币(审查发现)。
    final currency = await repo.getAccountCurrencyByAnyId(accountId);
    if (!mounted) return;
    setState(() {
      _selectedAccountCurrency = currency;
    });
  }

  /// 交易币种(币种优先联动,第 6 条):手选币种 → 账户列表按它过滤,所选账户
  /// 币种必然一致。有账户但其币种尚在异步加载时,fallback 手选币种(而非本位
  /// 币,避免加载窗口内汇率行闪没)。
  String _txCurrency() {
    if (_selectedAccountId != null) {
      return _selectedAccountCurrency ??
          _pickedCurrency ??
          ref.read(currentLedgerCurrencyProvider);
    }
    return _pickedCurrency ?? ref.read(currentLedgerCurrencyProvider);
  }

  /// 本笔汇率:手改/隐含 > 有效汇率(effectiveRatesForLedgerProvider)。
  double? _currentRate() {
    if (_rateManuallySet) return double.tryParse(_rateStr ?? '');
    final rates = ref.read(effectiveRatesForLedgerProvider).valueOrNull;
    final er = rates?[_txCurrency()];
    return er == null ? null : double.tryParse(er.rate);
  }

  /// 外币且本地无该币种汇率时,自动拉一次(v30:记账页是汇率的新消费场景,
  /// 用户可能从没进过资产页/汇率页 → exchange_rates 表为空;且手选币种不在
  //// usedCurrencies 里,常规 refresh 不会带上它 → extraQuotes 显式传入)。
  /// 同一币种只自动试一次,失败后由用户手填(L8 缺失阻断仍兜底)。
  void _maybeAutoFetchRate() {
    final base = ref.read(currentLedgerCurrencyProvider);
    final txCurrency = _txCurrency();
    if (txCurrency == base || _rateManuallySet || _fetchingRate) return;
    if (_rateFetchAttemptedFor == txCurrency) return;
    final ratesAsync = ref.read(effectiveRatesForLedgerProvider);
    final rates = ratesAsync.valueOrNull;
    if (rates == null) return; // provider 尚未解析,等它先出结果
    if (rates.containsKey(txCurrency)) return; // 已有汇率
    _rateFetchAttemptedFor = txCurrency;
    setState(() => _fetchingRate = true);
    refreshExchangeRatesFromUi(ref, force: true, extraQuotes: {txCurrency})
        .whenComplete(() {
      if (mounted) setState(() => _fetchingRate = false);
    });
  }

  Future<void> _pickCurrency() async {
    final l10n = AppLocalizations.of(context);
    final base = ref.read(currentLedgerCurrencyProvider);
    final picked = await showCurrencyPickerSheet(
      context,
      selected: _pickedCurrency ?? base,
      primaryColor: Theme.of(context).colorScheme.primary,
      title: l10n.txCurrencyPickerTitle,
      rateBase: base, // 展示各币种对账本主币种的汇率
    );
    if (picked == null || !mounted) return;
    setState(() {
      _pickedCurrency =
          picked.toUpperCase() == base ? null : picked.toUpperCase();
      // 换币种后隐含/手改汇率作废,重新带有效汇率
      _rateStr = null;
      _rateManuallySet = false;
      // 币种优先联动(第 6 条):切币种 → 账户重置为不选,账户列表按新币种刷新
      // (AccountSelector.filterCurrency 变化触发重载)
      _selectedAccountId = null;
      _selectedAccountCurrency = null;
    });
  }

  Future<void> _editRate() async {
    final l10n = AppLocalizations.of(context);
    final ctrl = TextEditingController(
        text: _rateStr ?? _currentRate()?.toStringAsPrecision(6) ?? '');
    final entered = await showDialog<String>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text(l10n.txRateLabel),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            hintText:
                '1 ${_txCurrency()} = ? ${ref.read(currentLedgerCurrencyProvider)}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx),
            child: Text(AppLocalizations.of(dctx).commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dctx, ctrl.text.trim()),
            child: Text(AppLocalizations.of(dctx).commonConfirm),
          ),
        ],
      ),
    );
    if (entered == null || !mounted) return;
    final v = double.tryParse(entered);
    if (v == null || v <= 0) return;
    setState(() {
      _rateStr = entered;
      _rateManuallySet = true;
    });
  }

  /// 币种标(金额表达式最左):点开即选(币种优先联动:选后账户重置、账户
  /// 列表按新币种过滤)。转账不显示:转账币种恒=账户币种,选了也会被忽略。
  Widget _buildCurrencyChip(BuildContext context) {
    if (widget.transactionKind == 'transfer') return const SizedBox.shrink();
    final text = Theme.of(context).textTheme;
    ref.watch(currentLedgerCurrencyProvider); // 账本切换时重建
    final txCurrency = _txCurrency();
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: _pickCurrency,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: BeeTokens.surfaceKeySecondary(context),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 小国旗(欧元→欧盟旗;区域货币→符号占位)
            currencyFlag(context, txCurrency, width: 19, height: 14, radius: 4),
            const SizedBox(width: 5),
            Text(
              txCurrency,
              style: text.bodySmall?.copyWith(
                color: BeeTokens.textSecondary(context),
                fontWeight: FontWeight.w600,
              ),
            ),
            Icon(Icons.arrow_drop_down,
                size: 16, color: BeeTokens.iconSecondary(context)),
          ],
        ),
      ),
    );
  }

  /// 折算预览(仅外币时出现,金额下方右对齐一行,反馈9):`≈ 86.40 CNY`。
  /// 汇率数字不展示(自动拉取内部使用);获取失败时本行变错误提示,可点手填(L8)。
  Widget _buildCurrencySection(BuildContext context) {
    if (widget.transactionKind == 'transfer') return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final ledgerBase = ref.watch(currentLedgerCurrencyProvider);
    ref.watch(effectiveRatesForLedgerProvider);
    final txCurrency = _txCurrency();
    final isForeign = txCurrency != ledgerBase;
    if (!isForeign) return const SizedBox.shrink();

    final rate = _currentRate();
    if (rate == null && !_fetchingRate) {
      // 外币无汇率 → 自动拉一次(post-frame 防 build 中副作用;方法内幂等防重)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _maybeAutoFetchRate();
      });
    }
    final amount = double.tryParse(_amountStr) ?? 0.0;
    final preview = (rate != null && rate > 0) ? (amount * rate) : null;
    final rateMissing = rate == null && !_fetchingRate;

    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          InkWell(
            // 常态纯展示;仅获取失败时点击手填汇率(L8 兜底)
            onTap: rateMissing ? _editRate : null,
            child: Text(
              preview != null
                  ? l10n.txConvertedPreview(
                      preview.toStringAsFixed(2), ledgerBase)
                  : _fetchingRate
                      ? '≈ … $ledgerBase'
                      : l10n.txRateMissingHint,
              style: text.bodySmall?.copyWith(
                color: rateMissing
                    ? Theme.of(context).colorScheme.error
                    : BeeTokens.textTertiary(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _append(String s) {
    setState(() {
      if (s == '.') {
        if (_amountStr.contains('.')) return;
      }
      // 限制两位小数
      if (_amountStr.contains('.')) {
        final dot = _amountStr.indexOf('.');
        final decimals = _amountStr.length - dot - 1;
        if (s != '.' && decimals >= 2) return;
      }
      // 去除前导 0
      if (_amountStr == '0' && s != '.') {
        _amountStr = s;
      } else if (_amountStr == '-0' && s != '.') {
        _amountStr = '-$s';
      } else {
        _amountStr += s;
      }
    });
    SystemSound.play(SystemSoundType.click);
  }

  void _backspace() {
    setState(() {
      if (_amountStr.isEmpty) return;
      _amountStr = _amountStr.substring(0, _amountStr.length - 1);
      if (_amountStr.isEmpty) _amountStr = '0';
    });
    SystemSound.play(SystemSoundType.click);
  }

  Future<void> _submit({required bool continueAdding}) async {
    if (_isSubmitting || !mounted) return;

    final current = double.tryParse(_amountStr) ?? 0.0;
    final total = _op == null ? current : _compute(_acc, _op!, current);
    if (total.abs() <= 0) return;

    setState(() => _isSubmitting = true);

    // v30:折本位币快照。外币且汇率无效 → 阻断(L8)。
    final txCurrency = _txCurrency();
    final ledgerBase = ref.read(currentLedgerCurrencyProvider);
    double? nativeAmount;
    if (txCurrency == ledgerBase) {
      nativeAmount = total.abs();
    } else {
      final rate = _currentRate();
      if (rate == null || rate <= 0) {
        if (mounted) {
          setState(() => _isSubmitting = false);
          showToast(context, AppLocalizations.of(context).txRateMissingHint);
        }
        return;
      }
      nativeAmount = total.abs() * rate;
    }

    HapticFeedback.lightImpact();
    SystemSound.play(SystemSoundType.click);
    try {
      await widget.onSubmit((
        amount: total.abs(), // 始终正数
        continueAdding: continueAdding,
        note: _noteCtrl.text.isEmpty ? null : _noteCtrl.text,
        date: _date,
        accountId: _selectedAccountId,
        tagIds: _selectedTagIds,
        pendingAttachments: _pendingAttachments,
        excludeFromStats: _excludeFromStats,
        excludeFromBudget: _excludeFromBudget,
        currencyCode: txCurrency,
        nativeAmount: nativeAmount,
      ));
      // 嵌入页面模式「再记」：保存成功后清空金额与备注、待传附件（已随本笔
      // 入库），保留分类/账户/标签/旗标/日期，直接录下一笔（钱迹式）。
      if (mounted && continueAdding) {
        setState(() {
          _amountStr = '0';
          _acc = 0;
          _op = null;
          _noteCtrl.clear();
          _pendingAttachments = [];
          _isSubmitting = false;
        });
      }
    } catch (e, stack) {
      // 保存失败必须复位提交状态并给出反馈，否则「完成」按钮永久转圈
      // （数据可能已部分写入，由调用方负责一致性）。
      logger.error('AmountEditorSheet', '提交交易失败', e, stack);
      if (mounted) {
        setState(() => _isSubmitting = false);
        showToast(context, AppLocalizations.of(context).commonFailed);
      }
    }
  }

  // 旧 _toggleSign 已废弃，符号由类别含义决定

  // _setToday 移除，改为点击日历按钮选择日期

  void _pickDate() async {
    // 关闭键盘，避免选择日期后键盘重新弹出
    FocusManager.instance.primaryFocus?.unfocus();

    // 等待键盘完全关闭
    await Future.delayed(const Duration(milliseconds: 100));

    if (!mounted) return;

    final showTime = ref.read(showTransactionTimeProvider);

    if (showTime) {
      // 显示时间功能开启时，使用两步选择器（先日期后时间）
      final res = await showWheelDateTimePicker(
        context,
        initial: _date,
        maxDate: DateTime.now(),
      );
      if (res != null) setState(() => _date = res);
    } else {
      // 普通模式，只选择日期
      final res = await showWheelDatePicker(
        context,
        initial: _date,
        mode: WheelDatePickerMode.ymd,
        maxDate: DateTime.now(),
      );
      if (res != null) setState(() => _date = res);
    }
  }

  /// 用 Decimal 精确运算(避免浮点漂移,如 0.1+0.2),左到右无运算符优先级,
  /// 除零保护;结果四舍五入到最多两位小数(金额精度)。
  double _compute(double a, String op, double b) {
    final da = Decimal.parse(a.toStringAsFixed(2));
    final db = Decimal.parse(b.toStringAsFixed(2));
    final Decimal r;
    switch (op) {
      case '+':
        r = da + db;
        break;
      case '-':
        r = da - db;
        break;
      case '×':
        r = da * db;
        break;
      case '÷':
        if (db == Decimal.zero) return a; // 除零保护:保持被除数不变
        r = (da.toRational() / db.toRational())
            .toDecimal(scaleOnInfinitePrecision: 12);
        break;
      default:
        return b;
    }
    return r.round(scale: 2).toDouble();
  }

  /// 运算符显示字形(减号用真减号 −,而非连字符 -)。
  String _opGlyph(String op) {
    switch (op) {
      case '-':
        return '−';
      case '×':
        return '×';
      case '÷':
        return '÷';
      default:
        return '+';
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final text = Theme.of(context).textTheme;
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

    // 底部弹窗模式：备注框聚焦且键盘弹出时额外让位；嵌入页面模式由宿主
    // Scaffold 的 resizeToAvoidBottomInset 统一处理，不再额外加 padding。
    final extraPadding =
        (!widget.embedded && _noteFieldHasFocus && keyboardHeight > 0)
            ? 100.0
            : 0.0;

    double parsed() => double.tryParse(_amountStr) ?? 0.0;

    void applyOp(String op) {
      final cur = parsed();
      if (_op == null) {
        // 首次点击运算符，将当前值存入累加器
        _acc = cur;
      } else {
        // 左到右:先把上一个运算符算掉
        _acc = _compute(_acc, _op!, cur);
      }
      _op = op;
      _amountStr = '0';
      HapticFeedback.selectionClick();
      SystemSound.play(SystemSoundType.click);
      setState(() {});
    }

    // 计算等号：完成当前运算，将结果存入 _amountStr，清空运算状态
    void applyEquals() {
      if (_op == null) return; // 没有运算符，不执行
      final cur = parsed();
      final total = _compute(_acc, _op!, cur);
      // 格式化结果
      final s = total.abs().toStringAsFixed(2);
      final trimmed = s.contains('.')
          ? s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')
          : s;
      _amountStr = trimmed.isEmpty ? '0' : trimmed;
      _acc = 0;
      _op = null;
      HapticFeedback.selectionClick();
      SystemSound.play(SystemSoundType.click);
      setState(() {});
    }

    Widget keyBtn(String label, {Color? bg, Color? fg, VoidCallback? onTap}) {
      return Padding(
        padding: const EdgeInsets.all(5),
        child: Material(
          color: bg ?? BeeTokens.surfaceKey(context),
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Container(
              height: 54,
              alignment: Alignment.center,
              child: Text(
                label,
                style: text.titleMedium?.copyWith(
                  color: fg ?? BeeTokens.textPrimary(context),
                  fontSize: 19,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      );
    }

    // 运算符键:显示当前激活的运算符（单击应用）；长按/双击切换加减 ↔ 乘除
    // （两键独立切换，切换后立即应用另一组运算符——保留原能力，视觉对齐钱迹
    // 的单符号键盘）。
    Widget opKey(
        String addSubOp, String mulDivOp, bool isMul, VoidCallback onToggle) {
      final activeOp = isMul ? mulDivOp : addSubOp;
      return Padding(
        padding: const EdgeInsets.all(5),
        child: Material(
          color: BeeTokens.surfaceKeySecondary(context),
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => applyOp(activeOp),
            // 双击 / 长按都是「切到另一组运算符并直接应用」(一步用上另一个);
            // applyOp 内部已带触感/声音。
            onDoubleTap: () {
              onToggle();
              applyOp(isMul ? addSubOp : mulDivOp);
            },
            onLongPress: () {
              onToggle();
              applyOp(isMul ? addSubOp : mulDivOp);
            },
            child: SizedBox(
              height: 54,
              child: Center(
                child: Text(
                  _opGlyph(activeOp),
                  style: text.titleMedium?.copyWith(
                    color: BeeTokens.textPrimary(context),
                    fontSize: 22,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    String fmtDate(DateTime d) => '${d.year}/${d.month}/${d.day}';
    String fmtTime(DateTime d) =>
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}:${d.second.toString().padLeft(2, '0')}';
    final showTime = ref.watch(showTransactionTimeProvider);

    return SafeArea(
      top: false,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 100),
        padding: EdgeInsets.fromLTRB(
          widget.embedded ? 12 : 16,
          widget.embedded ? 8 : 12,
          widget.embedded ? 12 : 16,
          (widget.embedded ? 8 : 16) + extraPadding,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 共享账本作者头像（仅编辑模式 + 共享账本时显示）
            if (widget.editingTransactionId != null)
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 4),
                child: _TxAuthorAvatars(
                    editingTransactionId: widget.editingTransactionId!),
              ),
            // 快捷 chips 行（钱迹式）：日期 / 标签 / 图片 / 旗标
            _buildChipsRow(context),
            const SizedBox(height: 8),
            // 金额卡片：账户选择 + 币种 + 备注 + 大金额 + 折算预览（钱迹式）
            _buildAmountCard(context, text),
            const SizedBox(height: 8),
            // 数字键盘
            LayoutBuilder(builder: (ctx, c) {
              final w = (c.maxWidth) / 4;
              Widget dateKey() => Padding(
                    padding: const EdgeInsets.all(5),
                    child: Material(
                      color: BeeTokens.surfaceKeySecondary(context),
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          SystemSound.play(SystemSoundType.click);
                          _pickDate();
                        },
                        child: SizedBox(
                          height: 54,
                          child: Center(
                            child: showTime
                                ? Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        fmtDate(_date),
                                        style: text.labelSmall?.copyWith(
                                            color:
                                                BeeTokens.textPrimary(context),
                                            fontWeight: FontWeight.w600),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        fmtTime(_date),
                                        style: text.labelSmall?.copyWith(
                                            color: BeeTokens.textSecondary(
                                                context),
                                            fontWeight: FontWeight.w500),
                                      ),
                                    ],
                                  )
                                : Text(
                                    fmtDate(_date),
                                    style: text.labelMedium?.copyWith(
                                        color: BeeTokens.textPrimary(context),
                                        fontWeight: FontWeight.w600),
                                  ),
                          ),
                        ),
                      ),
                    ),
                  );
              // 退格键（钱迹式：数字键盘右上角）
              Widget backspaceKey() => Padding(
                    padding: const EdgeInsets.all(5),
                    child: Material(
                      color: BeeTokens.surfaceKey(context),
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: _backspace,
                        child: SizedBox(
                          height: 54,
                          child: Center(
                              child: Icon(Icons.backspace_outlined,
                                  size: 22,
                                  color: BeeTokens.textPrimary(context))),
                        ),
                      ),
                    ),
                  );
              // 「再记」键：保存当前一笔后留在本页继续录下一笔（仅新建可用；
              // 编辑/复制/转账场景该位置回退为日期键）
              Widget againKey() {
                final isEnabled = !_isSubmitting && widget.canSubmit;
                return Padding(
                  padding: const EdgeInsets.all(5),
                  child: Material(
                    color: BeeTokens.surfaceKey(context),
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: isEnabled
                          ? () => _submit(continueAdding: true)
                          : null,
                      child: SizedBox(
                        height: 54,
                        child: Center(
                          child: Text(
                            AppLocalizations.of(context).txSaveAndAgain,
                            style: TextStyle(
                              color: isEnabled
                                  ? BeeTokens.textPrimary(context)
                                  : BeeTokens.textTertiary(context),
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }

              // 「保存」键：运算模式先算等号，否则直接提交（钱迹式主色文字）
              Widget saveKey() {
                // 计算当前总额以判断是否启用保存按钮
                final cur = parsed();
                final total = _op == null ? cur : _compute(_acc, _op!, cur);

                // 判断是否处于运算模式
                final isInCalcMode = _op != null;
                final isEnabled = (isInCalcMode ? true : total.abs() > 0) &&
                    !_isSubmitting &&
                    widget.canSubmit;

                void handleTap() {
                  if (isInCalcMode) {
                    // 运算模式：先计算结果（再点一次保存提交）。
                    applyEquals();
                    return;
                  }
                  _submit(continueAdding: false);
                }

                return Padding(
                  padding: const EdgeInsets.all(5),
                  child: Material(
                    color: BeeTokens.surfaceKey(context),
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: isEnabled ? handleTap : null,
                      child: SizedBox(
                        height: 54,
                        child: Center(
                          child: _isSubmitting
                              ? SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor:
                                        AlwaysStoppedAnimation<Color>(primary),
                                  ),
                                )
                              : Text(
                                  AppLocalizations.of(context).commonSave,
                                  style: TextStyle(
                                    color: isEnabled
                                        ? primary
                                        : BeeTokens.textTertiary(context),
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                );
              }

              // 钱迹式键盘：1-9 电话排布，右上退格，右列运算符，
              // 底行「再记(或日期) / 0 / . / 保存」。
              return Column(
                children: [
                  Row(children: [
                    SizedBox(
                        width: w,
                        child: keyBtn('1', onTap: () => _append('1'))),
                    SizedBox(
                        width: w,
                        child: keyBtn('2', onTap: () => _append('2'))),
                    SizedBox(
                        width: w,
                        child: keyBtn('3', onTap: () => _append('3'))),
                    SizedBox(width: w, child: backspaceKey()),
                  ]),
                  Row(children: [
                    SizedBox(
                        width: w,
                        child: keyBtn('4', onTap: () => _append('4'))),
                    SizedBox(
                        width: w,
                        child: keyBtn('5', onTap: () => _append('5'))),
                    SizedBox(
                        width: w,
                        child: keyBtn('6', onTap: () => _append('6'))),
                    SizedBox(
                        width: w,
                        child: opKey('-', '÷', _mulKey2,
                            () => setState(() => _mulKey2 = !_mulKey2))),
                  ]),
                  Row(children: [
                    SizedBox(
                        width: w,
                        child: keyBtn('7', onTap: () => _append('7'))),
                    SizedBox(
                        width: w,
                        child: keyBtn('8', onTap: () => _append('8'))),
                    SizedBox(
                        width: w,
                        child: keyBtn('9', onTap: () => _append('9'))),
                    SizedBox(
                        width: w,
                        child: opKey('+', '×', _mulKey1,
                            () => setState(() => _mulKey1 = !_mulKey1))),
                  ]),
                  Row(children: [
                    SizedBox(
                        width: w,
                        child: widget.allowContinueAdding
                            ? againKey()
                            : dateKey()),
                    SizedBox(
                        width: w,
                        child: keyBtn('0', onTap: () => _append('0'))),
                    SizedBox(
                        width: w,
                        child: keyBtn('.', onTap: () => _append('.'))),
                    SizedBox(width: w, child: saveKey()),
                  ]),
                ],
              );
            })
          ],
        ),
      ),
    );
  }

  /// 钱迹式快捷 chips 行：日期 / 标签 / 图片 / 旗标（横向滚动胶囊）。
  Widget _buildChipsRow(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final now = DateTime.now();
    final isToday = _date.year == now.year &&
        _date.month == now.month &&
        _date.day == now.day;
    final showTime = ref.watch(showTransactionTimeProvider);
    final dateLabel =
        isToday ? l10n.calendarToday : '${_date.month}/${_date.day}';

    // §7 共享账本:用按当前 ledger 过滤后的 tags(Editor 视角下走
    // SharedLedgerTags,synthetic id 跟 tag picker 一致)。
    final allTags = ref.watch(tagsForCurrentLedgerProvider).valueOrNull ?? [];
    final selectedTags =
        allTags.where((t) => _selectedTagIds.contains(t.id)).toList();
    final tagLabel = selectedTags.isEmpty
        ? l10n.tagSelectTitle
        : selectedTags.length == 1
            ? selectedTags.first.name
            : '${selectedTags.first.name} +${selectedTags.length - 1}';

    // 附件数量：编辑模式叠加已保存附件
    int attachmentCount = _pendingAttachments.length;
    List<TransactionAttachment> savedAttachments = [];
    if (widget.editingTransactionId != null) {
      savedAttachments = ref
              .watch(
                  transactionAttachmentsProvider(widget.editingTransactionId!))
              .valueOrNull ??
          [];
      attachmentCount += savedAttachments.length;
    }

    // 旗标：转账两个标记都不适用 → 不渲染
    final kind = widget.transactionKind;
    final showFlag = kind != 'transfer';
    final flagActive = _excludeFromStats || _excludeFromBudget;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        children: [
          _chip(
            context,
            icon: Icons.calendar_today_rounded,
            label: dateLabel,
            onTap: _pickDate,
          ),
          _chip(
            context,
            icon: Icons.sell_outlined,
            label: tagLabel,
            active: selectedTags.isNotEmpty,
            onTap: () async {
              final result = await TagSelector.show(
                context,
                selectedTagIds: _selectedTagIds,
              );
              if (result != null) {
                setState(() => _selectedTagIds = result);
              }
            },
          ),
          _chip(
            context,
            icon: attachmentCount > 0 ? Icons.image : Icons.image_outlined,
            label: attachmentCount > 0 ? '$attachmentCount' : null,
            active: attachmentCount > 0,
            onTap: () => _handleAttachmentTap(savedAttachments),
          ),
          if (showFlag)
            _chip(
              context,
              icon: flagActive ? Icons.flag : Icons.outlined_flag,
              active: flagActive,
              onTap: _showFlagsDialog,
            ),
        ],
      ),
    );
  }

  /// 快捷胶囊 chip（钱迹式）：嵌入模式白底浮于灰页面，弹窗模式灰底浮于白面板。
  Widget _chip(
    BuildContext context, {
    IconData? icon,
    String? label,
    bool active = false,
    required VoidCallback onTap,
  }) {
    final color = active
        ? Theme.of(context).colorScheme.primary
        : BeeTokens.textSecondary(context);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: widget.embedded
                ? BeeTokens.surfaceKey(context)
                : BeeTokens.surfaceKeySecondary(context),
            borderRadius: BorderRadius.circular(17),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: color),
                if (label != null) const SizedBox(width: 4),
              ],
              if (label != null)
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 钱迹式金额卡片：账户行 + 币种/备注/大金额行 + 折算预览。
  Widget _buildAmountCard(BuildContext context, TextTheme text) {
    final kind = widget.transactionKind;
    final amountColor = kind == 'expense'
        ? BeeTokens.expenseColor(context, ref)
        : kind == 'income'
            ? BeeTokens.incomeColor(context, ref)
            : BeeTokens.textPrimary(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: widget.embedded
            ? BeeTokens.surfaceKey(context)
            : BeeTokens.surfaceInput(context),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 账户选择（仅在启用时显示）
          if (widget.showAccountPicker)
            Consumer(
              builder: (context, ref, _) {
                final accountFeatureAsync =
                    ref.watch(accountFeatureEnabledProvider);
                return accountFeatureAsync.when(
                  data: (enabled) {
                    if (!enabled) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: AccountSelector(
                        selectedAccountId: _selectedAccountId,
                        ledgerId: widget.ledgerId,
                        // 币种优先联动:账户列表只显示当前所选币种的账户
                        filterCurrency: _txCurrency(),
                        // 账户隐藏(#240)E1 钉住:编辑态原账户若已隐藏,补回并打灰标
                        pinnedAccountId: widget.initialAccountId,
                        onAccountSelected: (accountId) {
                          setState(() {
                            _selectedAccountId = accountId;
                            _selectedAccountCurrency = null; // 异步刷新
                          });
                          if (accountId != null) {
                            _loadAccountCurrency(accountId);
                          }
                        },
                      ),
                    );
                  },
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                );
              },
            ),
          // 备注 + 币种 + 金额
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _buildCurrencyChip(context),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  focusNode: _noteFocusNode,
                  controller: _noteCtrl,
                  style: TextStyle(
                    color: BeeTokens.textPrimary(context),
                    fontSize: 15,
                  ),
                  decoration: InputDecoration(
                    hintText: AppLocalizations.of(context).txNoteHint,
                    hintStyle: TextStyle(
                      color: BeeTokens.textTertiary(context),
                      fontSize: 15,
                    ),
                    isDense: true,
                    border: InputBorder.none,
                    filled: true,
                    fillColor: Colors.transparent,
                    contentPadding: EdgeInsets.zero,
                    // 历史备注图标作为前缀
                    prefixIcon: _frequentNotes.isNotEmpty
                        ? GestureDetector(
                            onTap: () async {
                              await showDialog(
                                context: context,
                                builder: (context) => NotePickerDialog(
                                  ledgerId: widget.ledgerId,
                                  categoryId: widget.categoryId,
                                  categorySyncId: widget.categorySyncId,
                                  onNotePicked: (note) {
                                    setState(() {
                                      _noteCtrl.text = note;
                                      _noteCtrl.selection =
                                          TextSelection.fromPosition(
                                        TextPosition(offset: note.length),
                                      );
                                    });
                                  },
                                ),
                              );
                            },
                            child: Icon(
                              Icons.history,
                              color: BeeTokens.iconSecondary(context),
                              size: 20,
                            ),
                          )
                        : null,
                    prefixIconConstraints: _frequentNotes.isNotEmpty
                        ? const BoxConstraints(minWidth: 36, minHeight: 20)
                        : null,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // 金额列：运算模式先显示表达式小字，下方大字金额（按类别着色）
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (_op != null)
                    Text(
                      '${_fmtTrim(_acc.abs())} ${_opGlyph(_op!)}',
                      style: text.bodySmall?.copyWith(
                        color: BeeTokens.textSecondary(context),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  Text(
                    _amountStr,
                    style: TextStyle(
                      fontSize: 30,
                      height: 1.1,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                      color: amountColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
          // 折算预览（仅外币时出现）
          _buildCurrencySection(context),
        ],
      ),
    );
  }

  /// 金额数值格式化：最多两位小数、去尾零。
  String _fmtTrim(double v) {
    final s = v.toStringAsFixed(2);
    final r = s.contains('.')
        ? s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')
        : s;
    return r.endsWith('.') ? r.substring(0, r.length - 1) : r;
  }

  /// 交易标记弹窗：两个标记开关。
  /// 可见性(01 §三):不计入收支 对 income/expense 显示;不计入预算 仅 expense。
  /// 转账两个开关都不显示 → 旗标图标本身不渲染,不会触发此弹窗。
  Future<void> _showFlagsDialog() async {
    final l10n = AppLocalizations.of(context);
    final primary = ref.watch(primaryColorProvider);
    final kind = widget.transactionKind;
    final showStats = kind != 'transfer';
    final showBudget = kind == 'expense';

    // 弹窗内用临时变量 + StatefulBuilder 实现实时切换,关闭时写回 sheet 状态。
    bool stats = _excludeFromStats;
    bool budget = _excludeFromBudget;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            Widget switchTile({
              required String title,
              required String hint,
              required bool value,
              required ValueChanged<bool> onChanged,
            }) {
              return SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(
                  title,
                  style: TextStyle(
                    color: BeeTokens.textPrimary(context),
                    fontSize: 15.0.scaled(context, ref),
                  ),
                ),
                subtitle: Text(
                  hint,
                  style: TextStyle(
                    color: BeeTokens.textTertiary(context),
                    fontSize: 12.0.scaled(context, ref),
                  ),
                ),
                value: value,
                activeColor: primary,
                onChanged: onChanged,
              );
            }

            return AlertDialog(
              backgroundColor: BeeTokens.surface(context),
              title: Text(
                l10n.txFlagDialogTitle,
                style: TextStyle(
                  color: BeeTokens.textPrimary(context),
                  fontSize: 17.0.scaled(context, ref),
                  fontWeight: FontWeight.w600,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showStats)
                    switchTile(
                      title: l10n.txFlagExcludeFromStats,
                      hint: l10n.txFlagExcludeFromStatsHint,
                      value: stats,
                      onChanged: (v) {
                        setDialogState(() => stats = v);
                        // 实时写回 sheet 状态,图标 active 态即时更新
                        setState(() => _excludeFromStats = v);
                      },
                    ),
                  if (showBudget)
                    switchTile(
                      title: l10n.txFlagExcludeFromBudget,
                      hint: l10n.txFlagExcludeFromBudgetHint,
                      value: budget,
                      onChanged: (v) {
                        setDialogState(() => budget = v);
                        setState(() => _excludeFromBudget = v);
                      },
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(
                    AppLocalizations.of(context).commonConfirm,
                    style: TextStyle(color: primary),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _handleAttachmentTap(
      List<TransactionAttachment> savedAttachments) async {
    final totalCount = savedAttachments.length + _pendingAttachments.length;

    if (totalCount == 0) {
      // 没有附件，直接添加
      await _showAddAttachmentOptions();
    } else {
      // 有附件，打开预览页（支持添加和删除）
      final result = await Navigator.push<List<File>?>(
        context,
        MaterialPageRoute(
          builder: (_) => AttachmentPreviewPage(
            attachments: savedAttachments,
            initialIndex: 0,
            allowDelete: true,
            allowAdd: true,
            pendingFiles: _pendingAttachments,
            transactionId: widget.editingTransactionId,
          ),
        ),
      );
      // 如果返回了新的待上传文件列表，更新状态
      if (result != null) {
        setState(() {
          _pendingAttachments = result;
        });
      }
    }
  }

  Future<void> _showAddAttachmentOptions() async {
    final l10n = AppLocalizations.of(context);
    final service = ref.read(attachmentServiceProvider);

    await showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: Text(l10n.attachmentTakePhoto),
              onTap: () async {
                Navigator.pop(context);
                final file = await service.takePhoto();
                if (file != null && mounted) {
                  if (widget.editingTransactionId != null) {
                    // 编辑模式：直接保存
                    await service.saveAttachment(
                      transactionId: widget.editingTransactionId!,
                      sourceFile: file,
                      index: 0,
                    );
                    ref.read(attachmentListRefreshProvider.notifier).state++;
                  } else {
                    // 新建模式：添加到待上传列表
                    setState(() {
                      _pendingAttachments = [..._pendingAttachments, file];
                    });
                  }
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: Text(l10n.attachmentChooseFromGallery),
              onTap: () async {
                Navigator.pop(context);
                final files = await service.pickFromGallery(
                    maxCount: 9 - _pendingAttachments.length);
                if (files.isNotEmpty && mounted) {
                  if (widget.editingTransactionId != null) {
                    // 编辑模式：直接保存
                    await service.saveAttachments(
                      transactionId: widget.editingTransactionId!,
                      sourceFiles: files,
                      startIndex: 0,
                    );
                    ref.read(attachmentListRefreshProvider.notifier).state++;
                  } else {
                    // 新建模式：添加到待上传列表
                    setState(() {
                      _pendingAttachments = [..._pendingAttachments, ...files];
                    });
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
