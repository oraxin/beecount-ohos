import 'platform_info.dart';

/// OHOS 平台功能裁剪开关（v1.0 范围基线）
///
/// 依据 2026-10-17 范围决策（wiki/08-鸿蒙版开发方案与计划.md §1）：
/// C/D/E 组功能不做、Supabase 同步与 AppLink 不做。被裁剪功能的
/// 开关集中在此管理，将来恢复某功能只需改这里，避免 if 散落各处。
///
/// 注意：非 OHOS 平台上所有开关均为 true，行为与官方版完全一致。
class OhosFeatureGate {
  OhosFeatureGate._();

  /// 当前平台是否为 OpenHarmony / HarmonyOS
  static bool get isOhos => PlatformInfo.isOhos;

  /// 是否初始化通知服务（C1：通知与提醒暂不提供）
  static bool get enableNotifications => !isOhos;

  /// 是否恢复/启动记账提醒监控（C1）
  static bool get enableReminders => !isOhos;

  /// 是否注册/刷新桌面小组件（D1：小组件暂不提供）
  static bool get enableHomeWidgets => !isOhos;

  /// 是否恢复截图自动识别监听（D2：OHOS 无对等能力）
  static bool get enableScreenshotMonitor => !isOhos;

  /// 是否初始化图片分享处理（C6：系统分享暂不提供）
  static bool get enableImageShareHandler => !isOhos;

  /// 是否监听 AppLink/快捷指令 URL（B6：deep link 不做）
  static bool get enableAppLinks => !isOhos;

  /// 是否启用应用锁/生物识别（C3：local_auth 无 OHOS 实现）
  static bool get enableAppLock => !isOhos;

  /// 是否启用应用内检查更新（D4：OHOS 版由 AppGallery 负责更新）
  static bool get enableInAppUpdate => !isOhos;

  /// 是否启用语音记账（C2：录音能力暂不提供）
  static bool get enableVoiceBilling => !isOhos;

  /// 是否提供 Supabase 云同步（B5：鸿蒙版不做）
  static bool get enableSupabaseSync => !isOhos;

  /// 是否提供海报系统分享出口（C6 待定项：share_plus OHOS 适配 P0 验证后再定）
  static bool get enablePosterShare => !isOhos;
}
