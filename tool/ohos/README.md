# OHOS 构建与 P0 环境搭建指引

> 对应 [wiki/08-鸿蒙版开发方案与计划.md](../../../wiki/08-鸿蒙版开发方案与计划.md) 的 P0 阶段。

## 1. 获取 CPF-Flutter SDK

```powershell
# Flutter-OH SDK（3.27 系列最新稳定）
git clone https://gitcode.com/CPF-Flutter/flutter_flutter.git
git -C flutter_flutter checkout 3.27.5-ohos-1.0.8

# 环境变量（示例，按实际路径调整）
# PATH=<sdk>/bin;$PATH
# export OHOS_SDK_HOME=<DevEco Studio SDK 路径>
# export TOOL_HOME=<hvigor 工具链>
```

配套资源：

| 资源 | 地址 |
|---|---|
| Engine（3.27 线） | https://gitcode.com/CPF-Flutter/flutter_engine |
| 官方插件适配 | https://gitcode.com/CPF-Flutter/flutter_packages |
| 三方库适配总表 | https://gitcode.com/CPF-Flutter/docs/blob/main/ThirdpartyLibrarites.md |
| 文档与示例 | https://gitcode.com/CPF-Flutter/flutter_samples（docs/ohos、troubleshooting） |

## 2. 插件映射（pubspec_overrides）

本仓库 `pubspec.yaml` 保持与上游一致；OHOS 构建时把
`tool/ohos/pubspec_overrides.yaml.template` 复制为仓库根目录的
`pubspec_overrides.yaml`（该文件不提交，避免影响 Android/iOS 构建）：

```powershell
Copy-Item tool\ohos\pubspec_overrides.yaml.template pubspec_overrides.yaml
```

模板中 CPF 插件以 git 依赖形式指向 CPF-Flutter 仓库的 3.27 分支。
P0 逐项核对分支名与版本后启用（模板内已按 2026-10-17 查证的适配清单填写，
部分条目需确认分支是否存在）。

## 3. P0 验证清单（go/no-go）

1. hello world 真机/模拟器运行（`flutter devices` 能识别 ohos 设备）
2. **平台检测**：真机打印 `Platform.operatingSystem`，确认返回 `ohos`
   （若返回 `android`，修改 `lib/utils/platform_info.dart` 的 `isOhos`）
3. **Drift 双路径**：sqlite3 FFI 直连；兜底 sqflite 驱动 + CPF flutter_sqflite
   （RDB）。验收：25 表建库（schemaVersion 33）+ 增删改查
4. 官方插件对表：flutter_packages 3.27 分支核对 shared_preferences /
   path_provider / connectivity_plus / url_launcher / image_picker
5. 待定项结论：share_plus 10.1.1（海报出口）、flutter_image_compress 替代、
   webview_flutter 使用场景
6. 主干编译：`flutter build hap --debug` 产出 HAP

验证结果记入 `docs/ohos-p0-report.md`（P0 完成时创建）。
