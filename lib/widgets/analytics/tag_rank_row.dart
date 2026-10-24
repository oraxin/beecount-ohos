import 'package:flutter/material.dart';
import '../../styles/tokens.dart';
import '../biz/biz.dart';
import '../../pages/tag/tag_detail_page.dart';

/// 标签排行行 — 展示方式与分类排行（CategoryRankRow 一级行）一致：
/// 圆形容器 + 名称 + 金额 + 占比 + 进度条。标签无图标，容器中心以
/// 标签色圆点示意；无色标签回退主题色。
class TagRankRow extends StatelessWidget {
  final int id; // 标签 ID（共享账本 synthetic tag 为负，不响应点击）
  final String name;
  final String? color; // 标签色（hex 字符串）
  final double value;
  final double percent; // 0..1（相对当前周期类型总额）

  const TagRankRow({
    super.key,
    required this.id,
    required this.name,
    this.color,
    required this.value,
    required this.percent,
  });

  Color _parseColor(BuildContext context) {
    final raw = color;
    if (raw == null || raw.isEmpty) {
      return Theme.of(context).colorScheme.primary;
    }
    try {
      String hex = raw;
      if (hex.startsWith('#')) hex = hex.substring(1);
      if (hex.length == 6) hex = 'FF$hex';
      return Color(int.parse(hex, radix: 16));
    } catch (_) {
      return Theme.of(context).colorScheme.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tagColor = _parseColor(context);
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 10.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: tagColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: tagColor,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontSize: 14,
                            ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    AmountText(
                      value: value,
                      signed: false,
                      decimals: 0,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '${(percent * 100).toStringAsFixed(1)}%',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: BeeTokens.textTertiary(context),
                        fontSize: 12,
                      ),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Stack(
                    children: [
                      Container(
                        height: 6,
                        color: tagColor.withValues(alpha: 0.15),
                      ),
                      FractionallySizedBox(
                        widthFactor: percent.clamp(0, 1),
                        child: Container(
                          height: 6,
                          color: tagColor.withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (id <= 0) return row;
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TagDetailPage(tagId: id, tagName: name),
        ),
      ),
      child: row,
    );
  }
}
