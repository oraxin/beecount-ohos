import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:beecount/widgets/biz/bee_icon.dart';

import '../../providers.dart';
import '../../widgets/ui/ui.dart';
import '../../widgets/biz/biz.dart';
import '../../styles/tokens.dart';
import '../../services/system/logger_service.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/ui_scale_extensions.dart';
import 'placeholder_page.dart';
import 'log_center_page.dart';

/// 关于页面
class AboutPage extends ConsumerStatefulWidget {
  const AboutPage({super.key});

  @override
  ConsumerState<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends ConsumerState<AboutPage> {
  String _versionDisplay = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await _getAppInfo();
    final versionText = info.version.startsWith('dev-')
        ? '${info.version} (${info.buildNumber})'
        : info.version;
    setState(() {
      _versionDisplay = versionText;
    });
  }

  void _showDeveloperStory(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.aboutDeveloperStoryTitle),
        content: SingleChildScrollView(
          child: Text(
            l10n.aboutDeveloperStory,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: BeeTokens.textSecondary(context),
                  height: 1.7,
                ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.commonConfirm),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final primary = ref.watch(primaryColorProvider);
    final locale = Localizations.localeOf(context);

    return Scaffold(
      backgroundColor: BeeTokens.scaffoldBackground(context),
      body: Column(
        children: [
          PrimaryHeader(
            title: l10n.aboutPageTitle,
            subtitle: l10n.aboutPageSubtitle,
            showBack: true,
          ),
          Expanded(
            child: SafeArea(
              top: false,
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  16.0.scaled(context, ref),
                  8.0.scaled(context, ref),
                  16.0.scaled(context, ref),
                  16.0.scaled(context, ref),
                ),
                children: [
                  // ===== 顶部:图标 + 应用名 + 版本号(与原版一致)=====
                  Padding(
                    padding: EdgeInsets.symmetric(
                      vertical: 24.0.scaled(context, ref),
                    ),
                    child: Column(
                      children: [
                        BeeIcon(
                          color: primary,
                          size: 80.0.scaled(context, ref),
                        ),
                        SizedBox(height: 16.0.scaled(context, ref)),
                        GestureDetector(
                          onTap: () => _showDeveloperStory(context),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                l10n.appName,
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall
                                    ?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: BeeTokens.textPrimary(context),
                                    ),
                              ),
                              SizedBox(width: 4.0.scaled(context, ref)),
                              Icon(
                                Icons.auto_stories_outlined,
                                size: 18.0.scaled(context, ref),
                                color: BeeTokens.textTertiary(context),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: 8.0.scaled(context, ref)),
                        Text(
                          _versionDisplay.isEmpty
                              ? l10n.aboutPageLoadingVersion
                              : _versionDisplay,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: BeeTokens.textSecondary(context),
                                  ),
                        ),
                      ],
                    ),
                  ),
                  // ===== 功能卡 =====
                  SectionCard(
                    margin: EdgeInsets.zero,
                    child: Column(
                      children: [
                        AppListTile(
                          leading: Icons.favorite_border,
                          title: l10n.aboutSupportDevelopment,
                          subtitle: l10n.aboutSupportDevelopmentSubtitle,
                          onTap: () async {
                            final lc = locale.languageCode;
                            final docUrl = lc == 'zh'
                                ? 'https://github.com/TNT-Likely/BeeCount/blob/main/docs/donate/README_ZH.md'
                                : 'https://github.com/TNT-Likely/BeeCount/blob/main/docs/donate/README_EN.md';
                            await _tryOpenUrl(Uri.parse(docUrl));
                          },
                        ),
                        BeeTokens.cardDivider(context),
                        AppListTile(
                          leading: Icons.feedback_outlined,
                          title: l10n.mineFeedback,
                          subtitle: l10n.mineFeedbackSubtitle,
                          onTap: () => _tryOpenUrl(Uri.parse(
                              'https://github.com/TNT-Likely/BeeCount/issues')),
                        ),
                        BeeTokens.cardDivider(context),
                        AppListTile(
                          leading: Icons.bug_report_outlined,
                          title: l10n.logCenterTitle,
                          subtitle: l10n.logCenterSubtitle,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const LogCenterPage(),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  // ===== 底部:更新日志 · 隐私政策 文字链接(内容暂未提供,占位页) =====
                  SizedBox(height: 24.0.scaled(context, ref)),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _footerLink(
                        context,
                        label: l10n.aboutChangelog,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  PlaceholderPage(title: l10n.aboutChangelog),
                            ),
                          );
                        },
                      ),
                      Padding(
                        padding: EdgeInsets.symmetric(
                            horizontal: 10.0.scaled(context, ref)),
                        child: Text(
                          '·',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: BeeTokens.textTertiary(context),
                                  ),
                        ),
                      ),
                      _footerLink(
                        context,
                        label: l10n.aboutPrivacyPolicy,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => PlaceholderPage(
                                    title: l10n.aboutPrivacyPolicy)),
                          );
                        },
                      ),
                    ],
                  ),
                  SizedBox(height: 8.0.scaled(context, ref)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 底部文字链接(下划线 + 主题色),更新日志 / 隐私政策共用。
  Widget _footerLink(
    BuildContext context, {
    required String label,
    required VoidCallback onTap,
  }) {
    final primary = ref.watch(primaryColorProvider);
    return GestureDetector(
      onTap: onTap,
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: primary,
              decoration: TextDecoration.underline,
              decorationColor: primary,
            ),
      ),
    );
  }
}

// -------- 工具方法：关于与更新 --------
class _AppInfo {
  final String version;
  final String buildNumber;
  final String? commit;
  final String? buildTime;
  const _AppInfo(this.version, this.buildNumber, {this.commit, this.buildTime});
}

// 优先读取 CI 注入的 dart-define（CI_VERSION/GIT_COMMIT/BUILD_TIME），否则回退 PackageInfo
Future<_AppInfo> _getAppInfo() async {
  final p = await PackageInfo.fromPlatform();
  final commit = const String.fromEnvironment('GIT_COMMIT');
  final buildTime = const String.fromEnvironment('BUILD_TIME');
  final ciVersion = const String.fromEnvironment('CI_VERSION');

  // 版本号策略：CI版本优先，本地开发显示 "dev-{pubspec版本}"
  final version =
      ciVersion.isNotEmpty ? ciVersion : 'dev-${p.version}'; // 本地开发版本标识

  return _AppInfo(version, p.buildNumber,
      commit: commit.isEmpty ? null : commit,
      buildTime: buildTime.isEmpty ? null : buildTime);
}

/// 尝试使用多种方式打开URL，提供更好的兼容性
Future<bool> _tryOpenUrl(Uri url) async {
  try {
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
      return true;
    }
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalNonBrowserApplication);
      return true;
    }
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.platformDefault);
      return true;
    }
    logger.error('AboutPage', '无法打开URL: $url');
    return false;
  } catch (e) {
    logger.error('AboutPage', '打开URL失败: $url', e);
    return false;
  }
}
