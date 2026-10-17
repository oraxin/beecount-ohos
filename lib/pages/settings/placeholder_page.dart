import 'package:flutter/material.dart';

import '../../styles/tokens.dart';
import '../../widgets/ui/ui.dart';

/// 「待更新」占位页 —— OHOS 版专用。
///
/// 使用帮助 / 更新日志 / 隐私政策等内容页暂未提供，统一跳转到本页展示
/// 空状态，避免暴露在线文档站。内容就绪后把对应入口改回真实页面即可。
class PlaceholderPage extends StatelessWidget {
  const PlaceholderPage({super.key, required this.title});

  /// 页面标题（顶部导航栏文字，如「使用帮助」「更新日志」「隐私政策」）
  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BeeTokens.scaffoldBackground(context),
      body: Column(
        children: [
          PrimaryHeader(
            title: title,
            showBack: true,
          ),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.hourglass_empty_rounded,
                    size: 48,
                    color: BeeTokens.textTertiary(context),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '待更新',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: BeeTokens.textSecondary(context),
                        ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
