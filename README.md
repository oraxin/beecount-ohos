# 蜜蜂记账 OH（BeeCount for HarmonyOS）

<div align="center">

![Platform](https://img.shields.io/badge/platform-HarmonyOS-0A59F7?logo=harmonyos)
![Framework](https://img.shields.io/badge/Flutter-3.27.5--ohos-02569B?logo=flutter)
![License](https://img.shields.io/badge/license-BSL%201.1-orange)
![Release](https://img.shields.io/badge/release-v0.4.1-green)

**蜜蜂记账的鸿蒙 HarmonyOS 第三方移植版**

</div>

---

> ⚠️ **与官方项目无关联声明**
>
> 本仓库是 [BeeCount（蜜蜂记账）](https://github.com/TNT-Likely/BeeCount) 的**非官方第三方移植项目**，与官方作者及官方项目**无任何关联，未经官方授权或背书**。
>
> 官方版本仅支持 Android / iOS / Web 平台；本仓库的工作是将上游开源代码移植到 **HarmonyOS（鸿蒙）** 平台。移植过程中的功能取舍、界面调整与缺陷均由本仓库独立维护，**请勿向官方仓库反馈本移植版的问题**。

---

## 📖 简介

蜜蜂记账是一款「数据主权归用户」的轻量记账应用：离线优先、零广告、零追踪。本移植版基于 Flutter-OH（CPF-Flutter 鸿蒙适配版）框架，将上游 3.8.6 版本的完整 Flutter 代码运行到鸿蒙真机上，数据库、业务逻辑与大部分 UI 与上游保持一致。

| 项 | 说明 |
|---|---|
| 上游基线 | [TNT-Likely/BeeCount](https://github.com/TNT-Likely/BeeCount) `main`（tag `3.8.6` 之后） |
| 技术底座 | CPF-Flutter `flutter_flutter` tag `3.27.5-ohos-1.0.8` |
| 目标平台 | HarmonyOS（API 12+，`compatibleSdkVersion 5.0.0(12)`） |
| 应用标识 | `com.oraxin.beeccountoh` |

## ✨ 当前状态

以下状态基于 v0.4.1 真机（HarmonyOS 7.0）实测：

**✅ 已适配**

- 核心记账全流程：支出 / 收入 / 转账、多账本、多账户、二级分类、标签、周期记账
- 图表分析（fl_chart，含分类排行 / 标签排行）、年度报告
- CSV 导入导出、多币种与外币折算
- 云同步：BeeCount Cloud（自建服务端，真机验证 push/pull）、WebDAV / S3（代码就绪）
- AI 智能记账：对话记账 / Agent 账本查询 / OCR 云端识别（依赖智谱 GLM / OpenAI，服务端自备）
- 钱迹式明细列表（左滑编辑/删除、账单详情）与单页记账界面
- Drift 数据库经 sqflite OHOS RDB 驱动落库，25 表结构（schemaVersion 33）与上游完全一致

**❌ 不支持**（OHOS 平台限制或暂未适配，功能入口已隐藏）

- 桌面小组件、截图自动记账、语音记账、本地 OCR
- iCloud 同步、App 快捷指令（App Intents）、应用内更新
- 通知 / 语音提醒 / 锁屏访问 / 分享海报

## � 构建

### 环境要求

| 组件 | 版本 |
|---|---|
| Flutter-OH SDK | [CPF-Flutter/flutter_flutter](https://gitcode.com/CPF-Flutter/flutter_flutter) tag `3.27.5-ohos-1.0.8` |
| DevEco Studio | 26.0.0+（SDK API 26，低版本 API 22 SDK 编译不过） |
| Dart | 3.6.x（随 Flutter-OH 自带） |

详细环境搭建与踩坑记录见 [tool/ohos/README.md](tool/ohos/README.md)。

### 步骤

```powershell
# 1. 注入 OHOS 专用依赖覆盖（不提交，不影响 Android/iOS 构建）
Copy-Item tool\ohos\pubspec_overrides.yaml.template pubspec_overrides.yaml

# 2. 配置签名（二选一）
#    a) DevEco Studio 中 File > Project Structure > Signing Configs 自动签名
#    b) 复制 ohos\build-profile.json5.template 为 ohos\build-profile.json5 并填入自己的签名材料

# 3. 构建
flutter pub get
flutter build hap --debug

# 4. 安装到真机
hdc install -r build\ohos\hap\entry-default-signed.hap
```

> ⚠️ `pubspec_overrides.yaml` 存在时会**整体替换** `pubspec.yaml` 的 `dependency_overrides` 段，官方依赖 pin 已镜像在模板中。

## 📦 与上游同步

- 本仓库 `main` 为移植开发主线，版本号带 `v` 前缀（与上游无前缀格式区分），版本规范见 [docs/VERSIONING.md](docs/VERSIONING.md)
- 上游代码更新时可通过 `git fetch <上游 remote>` 合并跟进，注意 `pubspec.yaml` 版本字段与依赖变更的冲突

## � 许可证

- 上游代码采用 [BeeCount 软件许可协议（BSL 1.1）](LICENSE)：**非商业使用免费，商业使用需原作者授权**。本移植版不改变上游许可，同样遵循该协议
- 移植新增部分（`ohos/` 原生层、`tool/ohos/` 构建脚本、文档）同样以上游许可发布

## 🙏 致谢

- [BeeCount（蜜蜂记账）](https://github.com/TNT-Likely/BeeCount) — 官方项目及原作者
- [CPF-Flutter](https://gitcode.com/CPF-Flutter) — Flutter 鸿蒙适配框架与插件生态
