import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/db.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../styles/tokens.dart';
import '../../utils/category_utils.dart';
import '../../utils/transaction_edit_utils.dart';
import '../ui/ui.dart';
import '../category_icon.dart' show CategoryIconWidget;
import 'amount_text.dart';
import 'tag_chip.dart';
import '../../pages/transaction/category_detail_page.dart';
import '../../pages/tag/tag_detail_page.dart';
import '../../pages/attachment/attachment_preview_page.dart';

/// 账单详情底部面板（钱迹式）：顶部「账单详情」+ 复制/修改/删除操作 pill，
/// 下方白卡逐行列出 金额/分类/账户/时间/标签/图片/备注。
///
/// 修改/复制/删除的回调使用调用方（列表页）的 context/ref 执行——面板先
/// pop 自己，再由外部 context 走既有编辑/复制/删除链路。
Future<void> showTransactionDetailSheet(
  BuildContext context,
  WidgetRef ref, {
  required Transaction transaction,
  Category? category,
  String? accountName,
  String? toAccountName,
  List<Tag> tags = const [],
  int attachmentCount = 0,
  VoidCallback? onAttachmentTap,
}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: BeeTokens.surfaceSheet(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => _DetailBody(
      transaction: transaction,
      category: category,
      accountName: accountName,
      toAccountName: toAccountName,
      tags: tags,
      attachmentCount: attachmentCount,
      onAttachmentTap: onAttachmentTap,
      onEdit: () async {
        Navigator.of(context).pop();
        await TransactionEditUtils.editTransaction(
            context, ref, transaction, category);
      },
      onCopy: () async {
        Navigator.of(context).pop();
        await TransactionEditUtils.copyTransaction(context, ref, transaction);
      },
      onDelete: () async {
        Navigator.of(context).pop();
        await TransactionEditUtils.deleteTransaction(context, ref, transaction);
      },
    ),
  );
}

class _DetailBody extends ConsumerWidget {
  final Transaction transaction;
  final Category? category;
  final String? accountName;
  final String? toAccountName;
  final List<Tag> tags;
  final int attachmentCount;
  final VoidCallback? onAttachmentTap;
  final Future<void> Function() onEdit;
  final Future<void> Function() onCopy;
  final Future<void> Function() onDelete;

  const _DetailBody({
    required this.transaction,
    this.category,
    this.accountName,
    this.toAccountName,
    this.tags = const [],
    this.attachmentCount = 0,
    this.onAttachmentTap,
    required this.onEdit,
    required this.onCopy,
    required this.onDelete,
  });

  bool get _isTransfer => transaction.type == 'transfer';

  Color _amountColor(BuildContext context, WidgetRef ref) {
    if (_isTransfer) return BeeTokens.textPrimary(context);
    final base = transaction.type == 'expense'
        ? BeeTokens.expenseColor(context, ref)
        : BeeTokens.incomeColor(context, ref);
    // 与明细行同款加深，保证白底可读
    return BeeTokens.isDark(context)
        ? Color.lerp(base, Colors.white, 0.15)!
        : Color.lerp(base, Colors.black, 0.2)!;
  }

  /// 详情行：label 左、value 右，行高宽松（钱迹式留白）
  Widget _row(
    BuildContext context, {
    required String label,
    required Widget value,
    VoidCallback? onTap,
    bool divider = true,
  }) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 15,
              color: BeeTokens.textPrimary(context),
            ),
          ),
          const Spacer(),
          value,
        ],
      ),
    );
    return Column(
      children: [
        onTap != null ? InkWell(onTap: onTap, child: row) : row,
        if (divider)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Divider(
                height: 1, thickness: 0.5, color: BeeTokens.divider(context)),
          ),
      ],
    );
  }

  Widget _chevron(BuildContext context) => Icon(
        Icons.chevron_right,
        size: 18,
        color: BeeTokens.iconSecondary(context),
      );

  /// 顶部操作 pill（复制/修改/删除）
  Widget _actionPill(
    BuildContext context, {
    required String label,
    required Color fg,
    required Color bg,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: fg,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    final expenseColor = BeeTokens.expenseColor(context, ref);

    final isForeign = transaction.currencyCode != null &&
        transaction.currencyCode!.isNotEmpty &&
        transaction.currencyCode!.toUpperCase() !=
            (ref.watch(currentLedgerProvider).asData?.value?.currency ?? 'CNY')
                .toUpperCase();

    String? categoryName;
    if (!_isTransfer && category != null) {
      categoryName = CategoryUtils.getDisplayName(category!.name, context);
    }

    final note = transaction.note;

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 标题 + 操作行
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Row(
              children: [
                Text(
                  l10n.billDetailTitle,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: BeeTokens.textPrimary(context),
                  ),
                ),
                const Spacer(),
                _actionPill(
                  context,
                  label: l10n.commonDuplicate,
                  fg: BeeTokens.textPrimary(context),
                  bg: BeeTokens.surfaceKey(context),
                  onTap: () => onCopy(),
                ),
                const SizedBox(width: 8),
                _actionPill(
                  context,
                  label: l10n.commonEdit,
                  fg: BeeTokens.textPrimary(context),
                  bg: BeeTokens.surfaceKey(context),
                  onTap: () => onEdit(),
                ),
                const SizedBox(width: 8),
                _actionPill(
                  context,
                  label: l10n.commonDelete,
                  fg: expenseColor,
                  bg: expenseColor.withValues(alpha: 0.1),
                  onTap: () => onDelete(),
                ),
              ],
            ),
          ),
          // 详情白卡
          Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            decoration: BoxDecoration(
              color: BeeTokens.surface(context),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                _row(
                  context,
                  label: l10n.detailFieldAmount,
                  divider: true,
                  value: AmountText(
                    value: transaction.type == 'expense'
                        ? -transaction.amount
                        : transaction.amount,
                    signed: !_isTransfer,
                    showCurrency: isForeign,
                    currencyCode: transaction.currencyCode,
                    decimals: 2,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: _amountColor(context, ref),
                    ),
                  ),
                ),
                if (categoryName != null)
                  _row(
                    context,
                    label: l10n.detailFieldCategory,
                    value: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CategoryIconWidget(category: category, size: 18),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            categoryName,
                            style: TextStyle(
                              fontSize: 15,
                              color: BeeTokens.textPrimary(context),
                            ),
                          ),
                        ),
                        _chevron(context),
                      ],
                    ),
                    onTap: category!.id > 0
                        ? () {
                            Navigator.of(context).pop();
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => CategoryDetailPage(
                                  categoryId: category!.id,
                                  categoryName: categoryName!,
                                ),
                              ),
                            );
                          }
                        : null,
                  ),
                if (!_isTransfer && accountName != null)
                  _row(
                    context,
                    label: transaction.type == 'expense'
                        ? l10n.detailFieldAccountExpense
                        : l10n.detailFieldAccountIncome,
                    value: Text(
                      accountName!,
                      style: TextStyle(
                        fontSize: 15,
                        color: BeeTokens.textPrimary(context),
                      ),
                    ),
                  ),
                if (_isTransfer && accountName != null)
                  _row(
                    context,
                    label: l10n.detailFieldTransferOut,
                    value: Text(
                      accountName!,
                      style: TextStyle(
                        fontSize: 15,
                        color: BeeTokens.textPrimary(context),
                      ),
                    ),
                  ),
                if (_isTransfer && toAccountName != null)
                  _row(
                    context,
                    label: l10n.detailFieldTransferIn,
                    value: Text(
                      toAccountName!,
                      style: TextStyle(
                        fontSize: 15,
                        color: BeeTokens.textPrimary(context),
                      ),
                    ),
                  ),
                _row(
                  context,
                  label: l10n.detailFieldTime,
                  value: Text(
                    DateFormat('yyyy-MM-dd HH:mm')
                        .format(transaction.happenedAt.toLocal()),
                    style: TextStyle(
                      fontSize: 15,
                      color: BeeTokens.textPrimary(context),
                    ),
                  ),
                ),
                if (tags.isNotEmpty)
                  _row(
                    context,
                    label: l10n.detailFieldTags,
                    value: Flexible(
                      child: Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          for (final tag in tags)
                            TagChip(
                              name: tag.name,
                              color: tag.color,
                              size: TagChipSize.small,
                              onTap: tag.id > 0
                                  ? () {
                                      Navigator.of(context).pop();
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => TagDetailPage(
                                            tagId: tag.id,
                                            tagName: tag.name,
                                          ),
                                        ),
                                      );
                                    }
                                  : null,
                            ),
                        ],
                      ),
                    ),
                  ),
                if (attachmentCount > 0)
                  _row(
                    context,
                    label: l10n.detailFieldAttachments,
                    value: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.image_outlined,
                          size: 16,
                          color: primary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$attachmentCount',
                          style: TextStyle(
                            fontSize: 15,
                            color: primary,
                          ),
                        ),
                      ],
                    ),
                    onTap: onAttachmentTap,
                  ),
                if (note != null && note.isNotEmpty)
                  _row(
                    context,
                    label: l10n.detailFieldNote,
                    divider: false,
                    value: Container(
                      constraints: const BoxConstraints(maxWidth: 220),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: BeeTokens.surfaceInput(context),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        note,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 14,
                          color: BeeTokens.textPrimary(context),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
