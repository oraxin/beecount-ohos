# 版本与发布管理规范

> 本文档为所有开发（含 AI 助手）必须遵循的核心规范。

## 1. 与官方版本的关系

| 项 | 说明 |
|---|---|
| 官方仓库 | [TNT-Likely/BeeCount](https://github.com/TNT-Likely/BeeCount)（本仓库 `origin`），版本号格式 `3.8.6`（无 v 前缀） |
| 鸿蒙版基线 | 官方 `main` @ `5484496`（2026-10-16，最新 tag **3.8.6** 之后），tag：`baseline-official-3.8.6` |
| 技术底座 | CPF-Flutter `flutter_flutter` tag `3.27.5-ohos-1.0.8`（对应官方 Flutter 3.27.5，见 [wiki/08 方案](../../../wiki/08-鸿蒙版开发方案与计划.md)） |
| 上游同步 | 定期 `git fetch origin` 跟进官方 main；因 `pubspec.yaml` 已做鸿蒙版改动，rebase 时注意版本字段与依赖变更冲突 |

## 2. 版本号方案（未正式发布用 v0.x.x）

鸿蒙版版本号带 `v` 前缀，与官方无前缀格式区分：

| 版本 | 里程碑 | 状态 |
|---|---|---|
| `v0.0.1` | 工程准备：基线 + 平台检测/功能裁剪开关 + 构建模板 | ✅ |
| `v0.0.2` | UI 层功能裁剪（应用锁/更新/语音/Supabase/海报分享） | ✅ |
| `v0.1.0` | **第一个原型**：CPF-Flutter 环境跑通，真机完整运行 + Drift 建库（P0 出口） | ✅ |
| `v0.2.0` | 本地全功能（核心记账/图表/导入导出，P2 出口） | ✅ |
| `v0.2.1` | 真机走查修复：明细钱迹式改版 + drift 事务死锁（保存转圈） | ✅ |
| `v0.3.0` | 云同步 BeeCount Cloud 验证通过（push/pull 全通）+ pull 事务缺陷修复 + 品牌更名「蜜蜂记账OH」/新 Logo/界面精简 | ✅ 当前 |
| `v0.4.0` | AI 能力（对话记账/OCR 云端识别，P4 出口） | 待开发 |
| `v1.0.0` | 正式发布（AppGallery 上架，P5 出口） | 待开发 |

规则：

- v1.0.0 之前可任意改动，不保证兼容性，但**每个功能/修复都打 Tag**，方便回溯。
- 每次打 tag 时同步更新 `pubspec.yaml` 的 `version:` 字段（格式 `x.y.z+build`，`+` 后为构建号，从 1 递增）。
- tag 采用附注标签（`git tag -a`），annotation 中注明对应的官方基线/重要变更。

## 3. 分支与发布

- `main` 永远保持可发布状态，**不在上面直接写代码**。
- 把自己当成「两个人」：
  - 开发者：在功能分支写代码，随便折腾。分支命名 `feat/<主题>`、`fix/<主题>`。
  - 发布经理：在 `main` 只做合并和打 Tag。
- 所有改动走分支，禁止直接在 `main` 上 commit。
- 合并统一用 `--no-ff`，保留分支记录，方便看出哪些 commit 属于一个功能。
- 合并完成后删除本地分支 `git branch -d`，避免堆积废弃分支。

## 4. 提交信息规范

格式：`<type>(<scope>): <中文描述>`，禁止写 "update" 这类无意义信息。

| type | 用途 |
|---|---|
| `feat` | 新功能 |
| `fix` | 修 Bug |
| `docs` | 文档 |
| `chore` | 构建/杂项 |
| `ci` | CI 相关 |

示例：`feat(ohos): 启动流程按范围基线裁剪 OHOS 不提供的功能`

## 5. 标准发布流程

```bash
# 1. 功能分支开发并提交
git checkout -b feat/<主题>
git commit -m "feat(<scope>): <中文描述>"

# 2. 发布经理合并（--no-ff）并删除分支
git checkout main
git merge --no-ff feat/<主题>
git branch -d feat/<主题>

# 3. 同步 pubspec version 字段（如未随功能提交更新）

# 4. 打附注 tag
git tag -a v0.x.y -m "v0.x.y: <里程碑说明>（基线: official <版本/commit>）"

# 5. 推送（配置远程后）
# git push origin main --tags
```
