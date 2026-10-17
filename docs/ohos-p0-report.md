# OHOS P0 验证报告 + v0.1.0 构建适配记录

> 对应 [wiki/08-鸿蒙版开发方案与计划.md](../../wiki/08-鸿蒙版开发方案与计划.md) 的 P0 阶段出口。
> 验证日期：2026-10-17。

## 1. 环境结论

| 项 | 结论 |
|---|---|
| Flutter SDK | CPF-Flutter `3.27.5-ohos-1.0.8`（D:\flutter-ohos\flutter_flutter，与系统标准版 3.38.9 共存） |
| Dart | 3.6.2（兼容项目 `^3.6.0`） |
| IDE/SDK | DevEco Studio 26.0.0.851（SDK API 26）；embedding 1.0.8 依赖 API 24/26 符号，低版本 SDK 编译不过 |
| 真机 | 5JH9K25609001702，OpenHarmony 7.0.0.105 / API 26 / ohos-arm64 |
| 签名 | 复用 AGC 调试证书（bundleName com.example.myapplication 与 Profile 一致） |
| 工具链切换 | `tool/ohos/ohos-env.ps1`（会话级 PATH/镜像/PUB_CACHE） |

## 2. P0 验证清单结果

| # | 验证项 | 结果 |
|---|---|---|
| 1 | hello world 真机运行 | ✅ `flutter devices` 识别 ohos 设备，安装启动成功 |
| 2 | 平台检测 | ✅ 真机 `Platform.operatingSystem` 返回 `'ohos'`，`PlatformInfo.isOhos` 无需修改 |
| 3a | Drift 路径A：sqlite3 FFI（NativeDatabase） | ❌ sqlite3 包 2.9.4 `_defaultOpen` 对 `'ohos'` 直接 throw，`overrideFor` 无效 |
| 3b | Drift 路径B：SqfliteQueryExecutor（sqflite RDB） | ✅ schemaVersion=33 建库/插入/join 全通 |
| 4 | 插件对表 | ✅ path_provider_ohos / shared_preferences_ohos 来自 CPF flutter_packages master；sqflite 来自 openharmony-sig `br_v2.3.3+1_ohos` |
| 5 | 主干编译 | ✅ `flutter build hap --debug` 产出已签名 HAP（见 §3 适配点） |

**结论性决策**：OHOS 数据库走 sqflite RDB 驱动（drift_sqflite 桥），25 表定义/仓储层零改动。

## 3. v0.1.0 主工程适配点（feat/ohos-app-shell）

1. **平台壳**：`flutter create --platforms ohos` 生成 `ohos/`；`app.json5` bundleName
   与 AGC Profile 对齐；`build-profile.json5` 配 AGC 调试签名。
2. **数据库分发**：`lib/data/db.dart` `_openConnection()` 按 `PlatformInfo.isOhos`
   分发——ohos 走 `SqfliteQueryExecutor(path: 'beecount.sqlite')`，其他平台
   `NativeDatabase.createInBackground` 不变。
3. **依赖注入**：根目录 `pubspec_overrides.yaml`（不提交）注入 sqflite OHOS 实现 +
   OHOS 平台包；`pubspec.yaml` 仅新增纯 Dart 的 `drift_sqflite` 与版本号 0.1.0+1。
4. **编译适配**（CPF 的 TargetPlatform 枚举新增 `ohos` 值 / gen-l10n 差异）：
   - `packages/flutter_cloud_sync/.../beecount_cloud_provider.dart`：设备元信息
     switch 补 `TargetPlatform.ohos` case（device_info_plus 无 OHOS 实现，仅标记平台）。
   - `lib/services/system/update_service.dart`：`AppLocalizations.current`（新版
     gen-l10n 才有的静态查找器）改为占位符 `__UPDATE_ALREADY_LATEST_SIMPLE__`，
     展示层经 `_localizeUpdateMessage(context, ...)` 本地化，与 UpdateChecker 同模式。

## 4. 构建期踩坑记录（Windows）

| 坑 | 现象 | 处置 |
|---|---|---|
| 跨盘 srcPath | hvigor `00303231 The srcPath is not a relative path` | `path.relative` 跨盘（项目 D: / pub 缓存 C:）无法相对化 → `PUB_CACHE` 指到 D: 真实目录 |
| junction 失效 | hvigor `00303149 Path not found`（路径明明存在） | hvigor 校验 `realpathSync.native(path) === path`，junction 被解析回 C: → 必须真实目录，不能用链接 |
| pin 被顶掉 | `Color.toARGB32` 编译错（image_cropper_platform_interface 7.2.0） | pubspec_overrides.yaml 会**整体替换** pubspec.yaml 的 dependency_overrides → 官方 pin 需在模板镜像 |
| 枚举穷尽性 | `TargetPlatform.ohos` 使既有 switch 非穷尽 | 逐处补 ohos case |
| flutter 命令假死 | flutter.bat 卡锁重试无输出 | 受限执行环境拦截子进程/缓存写入导致 shared.bat 静默重试；flutter/pub/hvigor 需在正常权限终端运行 |

## 5. 真机验收（v0.1.0）

- 安装：`hdc install build\ohos\hap\entry-default-signed.hap` ✅
- 启动：`hdc shell aa start -a EntryAbility -b com.example.myapplication` ✅
- 截图确认：首页完整渲染（账本/月份统计/预算提示/空状态/底部导航），
  "默认账本"由 SeedService 写入并从数据库读出 → **DB 读写链路真机验证通过** ✅
- 已知限制：通知/小组件/截图记账/分享/Supabase 等按 OhosFeatureGate 裁剪（v0.0.1/v0.0.2）；
  图像压缩/裁剪等 OHOS 插件待 v0.2.0 补齐。

## 6. v0.2.0 插件适配记录（feat/ohos-local-full）

> 2026-10-17。CPF 插件分支名经 gitcode API（/api/v5/repos/...）逐一核实。

### 6.1 依赖注入矩阵（pubspec_overrides.yaml）

| 插件 | 官方版本 | OHOS 来源（ref） | 说明 |
|---|---|---|---|
| file_picker | ^8.1.2 → 8.0.7 | fluttertpc_file_picker `br_v8.0.7_ohos`（包在仓库根） | v8 系最新适配分支 |
| share_plus | ^12.0.1（同版） | flutter_plus_plugins `br_share_plus-v12.0.1_ohos` | 与官方完全同版本，无需降级 |
| image_cropper | ^10.0.0 → 9.1.0 | fluttertpc_image_cropper `br_v9.1.0_ohos` | interface 与 pin 7.1.0 匹配 |
| connectivity_plus | ^6.1.0 → 7.0.0 | flutter_plus_plugins `br_connectivity_plus-v7.0.0_ohos` | 仅云同步网络提示用 |
| package_info_plus | ^8.0.2 → 9.0.0 | flutter_plus_plugins `br_package_info_plus-v9.0.0_ohos` | 版本号展示 |
| url_launcher_ohos / image_picker_ohos | — | flutter_packages `master` | 联合插件 OHOS 实现显式注入 |

解析冲突处置（新增 3 个教训）：

| 坑 | 现象 | 处置 |
|---|---|---|
| web 版本冲突 | file_picker 8.0.7 声明 `web ^0.5.1`、share_plus 12.0.1 声明 `web ^1.0.0`，pub 解析失败 | override 统一 `web: ^1.0.0`——两者在非 web 平台走条件 import stub，不触碰 package:web 1.0 破坏面 |
| 传递 git 源 | share_plus_platform_interface 把 path_provider 声明为 git 源，与主工程 hosted 冲突 | override `path_provider: ^2.1.4` 钉回 hosted（OHOS 能力由 path_provider_ohos 提供） |
| 单仓双层目录 | `packages/package_info_plus/pubspec.yaml not found` | flutter_plus_plugins 结构为 `packages/<plugin>/<plugin>`，path 必须写到内层 |

### 6.2 webview 降级（help_center / privacy_policy）

CPF 暂无 webview_flutter OHOS 适配。`HelpCenterPage` / `PrivacyPolicyPage` 在
OHOS 上不初始化 WebViewController，页面主体降级为"在浏览器中打开"兜底页
（复用 `helpCenterOpenInBrowser` 文案与 `_openInBrowser()` 逻辑），所有调用方
（mine/help/about/login/AI 隐私弹窗）零改动。

### 6.3 构建结果

- `flutter build hap --debug` 一次通过（58s，降版本 API 无编译冲突）
- 真机功能走查：待办（记账增删改查/图表/CSV 导入导出/头像选择与裁剪）
