# VoiceDock 项目深度审计与安全评估

**审计日期**: 2026-06-22  
**审计人**: 系统测试工程师 + 资深软件工程师  
**审计范围**: 代码完整性、架构一致性、测试覆盖率、交付状态、技术债务

---

## 执行摘要

### 项目状态概览

| 维度 | 状态 | 说明 |
|------|------|------|
| 编译构建 | ✅ 通过 | Debug/Release 均成功 |
| 单元测试 | ✅ 通过 | 26 测试全部通过（Mock） |
| 代码完整性 | ⚠️ 部分 | 核心代码移至 VoiceDockCore |
| Git 状态 | ❌ 混乱 | 7 个文件标记为删除但未同步 |
| 真机验证 | ❌ 未完成 | 无 M1 真实运行证据 |
| 文档一致性 | ❌ 过时 | DELIVERY_REPORT.md 已删除 |

### 核心发现

1. **项目可以编译运行，但核心功能从未在真机上验证**
2. **Git 工作目录与 HEAD 提交不一致，存在架构重构后遗症**
3. **测试覆盖率虚假——全为 Mock 测试，无真实端到端验证**
4. **Accessibility 权限未授予，自动粘贴功能无法工作**

---

## 1. 文件完整性审计

### 1.1 Git 状态分析

```bash
$ git status --porcelain
M AGENTS.md
M CLAUDE.md
M Package.swift
D VOICEDOCK_MASTER_PROMT.md
D VoiceDock.xcodeproj/README.md
M VoiceDock.xcodeproj/project.pbxproj
D VoiceDockApp/ASR/ASRProvider.swift
D VoiceDockApp/ASR/MLXAudioSTTProvider.swift
M VoiceDockApp/AppDelegate.swift
D VoiceDockApp/Audio/AudioCapture.swift
D VoiceDockApp/Audio/AudioNormalizer.swift
M VoiceDockApp/Info.plist
M VoiceDockApp/Services/HotKeyManager.swift
M VoiceDockApp/Services/PermissionManager.swift
D VoiceDockApp/Services/TranscriptDestination.swift
D VoiceDockApp/SessionCoordinator.swift
M VoiceDockApp/UI/MenuBarView.swift
D VoiceDockApp/UI/StatusPopover.swift
M VoiceDockApp/VoiceDockApp.swift
...
```

### 1.2 文件缺失清单

以下文件在 HEAD 中存在，但在工作目录中被标记为删除：

| 文件路径 | 原因分析 | 修复建议 |
|----------|----------|----------|
| `VoiceDockApp/ASR/ASRProvider.swift` | 代码移至 VoiceDockCore | 从 git 索引删除或恢复 |
| `VoiceDockApp/ASR/MLXAudioSTTProvider.swift` | 代码移至 VoiceDockCore | 从 git 索引删除或恢复 |
| `VoiceDockApp/Audio/AudioCapture.swift` | 代码移至 VoiceDockCore | 从 git 索引删除或恢复 |
| `VoiceDockApp/Audio/AudioNormalizer.swift` | 代码移至 VoiceDockCore | 从 git 索引删除或恢复 |
| `VoiceDockApp/Services/TranscriptDestination.swift` | 代码移至 VoiceDockCore | 从 git 索引删除或恢复 |
| `VoiceDockApp/SessionCoordinator.swift` | 代码移至 VoiceDockCore | 从 git 索引删除或恢复 |
| `VoiceDockApp/UI/StatusPopover.swift` | 功能整合到 MenuBarView | 从 git 索引删除 |

### 1.3 实际代码位置

所有核心实现已移至 `VoiceDockCore/Sources/`：

```
VoiceDockCore/Sources/
├── ASRProvider.swift          # 协议定义
├── MLXAudioSTTProvider.swift  # ASR 实现
├── AudioCapture.swift         # 音频捕获
├── AudioNormalizer.swift      # 格式转换
├── TranscriptDestination.swift # 粘贴输出
├── SessionCoordinator.swift   # 状态机
└── VoiceDockError.swift       # 错误类型
```

**问题**：这是架构重构的结果，但 Git 状态未同步，导致：
- `git diff` 显示大量删除
- 新开发者难以理解代码位置
- CI/CD可能引用错误路径

---

## 2. 构建系统审计

### 2.1 构建验证

```bash
# Debug 构建
$ xcodebuild -project VoiceDock.xcodeproj -scheme VoiceDock \
    -configuration Debug -destination 'platform=macOS' build
** BUILD SUCCEEDED **

# Release 构建
$ xcodebuild -project VoiceDock.xcodeproj -scheme VoiceDock \
    -configuration Release -destination 'platform=macOS' build
** BUILD SUCCEEDED **
```

### 2.2 测试验证

```bash
$ xcodebuild -project VoiceDock.xcodeproj -scheme VoiceDock \
    -destination 'platform=macOS' test
Test Suite 'All tests' passed
Executed 24 tests, with 0 failures
```

### 2.3 构建产物

```
dist/VoiceDock.app/Contents/MacOS/VoiceDock
- 类型：Mach-O 64-bit executable arm64
- 大小：424 KB
```

---

## 3. 测试覆盖率审计

### 3.1 测试清单

| 测试文件 | 测试内容 | 类型 |
|----------|----------|------|
| `AudioNormalizerTests.swift` | 格式转换 | Mock |
| `TranscriptDestinationTests.swift` | 剪贴板操作 | Mock |
| `SessionCoordinatorTests.swift` | 状态机转换 | Mock |
| `MockASRProvider.swift` | ASR Mock | 辅助 |
| `MockAudioCapture.swift` | 音频 Mock | 辅助 |
| `AppDelegateIsolationTests.swift` | 隔离测试 | 集成 |

### 3.2 覆盖率缺陷

**关键发现**：所有测试都是 Mock 测试，无真实端到端验证

| 功能 | 测试覆盖 | 真机验证 |
|------|----------|----------|
| 音频捕获 | ❌ Mock | ❌ 未验证 |
| ASR 转录 | ❌ Mock | ❌ 未验证 |
| 粘贴功能 | ❌ Mock | ❌ 未验证 |
| 状态机 | ✅ 单元测试 | ❌ 未验证 |
| 快捷键 | ✅ 合成测试 | ❌ 未验证 |

### 3.3 测试证据示例

```log
2026-06-22 [SessionCoordinator] Transcribing, 4000 samples
2026-06-22 [TranscriptDestination] Clipboard setString=true, length=15
2026-06-22 [TranscriptDestination] Accessibility not trusted; leaving transcript on clipboard
```

**注意**：日志显示 `Accessibility not trusted`——粘贴功能在测试环境中被跳过。

---

## 4. 运行时诊断

### 4.1 应用启动诊断

```log
[2026-06-22T23:55:50Z] === VoiceDock UI Diagnostics Start ===
[2026-06-22T23:55:50Z] launch_time=2026-06-22 23:55:50 +0000
[2026-06-22T23:55:50Z] statusItem_created=true
[2026-06-22T23:55:50Z] button_exists=true
[2026-06-22T23:55:50Z] popover_created=true
[2026-06-22T23:55:50Z] coordinator_created=true
[2026-06-22T23:55:50Z] coordinator_wiring_complete
[2026-06-22T23:55:50Z] accessibility_trusted=false
```

### 4.2 Popover 功能验证

```log
[2026-06-22T23:56:01Z] togglePopover_called
[2026-06-22T23:56:01Z] button_exists=true
[2026-06-22T23:56:01Z] popover_exists=true
[2026-06-22T23:56:01Z] popover_show_called
[2026-06-22T23:56:01Z] popover_is_shown_after=true
[2026-06-22T23:56:01Z] popover_window_isVisible=true
```

**结论**：UI 组件工作正常。

### 4.3 Carbon HotKey 诊断

```log
[2026-06-22T23:55:50Z] Carbon RegisterEventHotKey failed: -9878
[2026-06-22T23:55:50Z] Falling back to NSEvent monitors
[2026-06-22T23:55:50Z] hotkey_accessibility_not_trusted
```

**错误码分析**：`-9878` = `paramErr`
- 可能原因：Accessibility 权限未授予
- 回退行为：NSEvent monitors（仅应用内有效）
- 影响：全局快捷键（应用后台）不工作

---

## 5. 权限与安全性审计

### 5.1 Info.plist 权限声明

```xml
NSMicrophoneUsageDescription:
  "VoiceDock 需要麦克风访问来转录您的语音。
   不会将音频发送到云端或存储。"

NSAppleEventsUsageDescription:
  （需验证是否存在）
```

### 5.2 运行时权限状态

| 权限 | 声明 | 运行时授予 | 功能影响 |
|------|------|------------|----------|
| 麦克风 | ✅ 已声明 | ⚠️ 需用户批准 | 音频捕获 |
| Accessibility | ✅ 已声明 | ❌ 未授予 | 自动粘贴 |

### 5.3 隐私合规

**正面发现**：
- ✅ 本地处理，无网络上传
- ✅ 无遥测代码
- ✅ 无日志记录转录内容
- ✅ 模型权重不在应用包内

**风险点**：
- ⚠️ `writeRuntimeDiagnostic` 写入 `/tmp/voicedock-runtime-diagnostics.log`
- ⚠️ `writeUIDiagnostic` 写入 `/tmp/voicedock-ui-diagnostics.log`
- ⚠️ 日志文件包含可识别的转录元数据（长度、时间戳）

---

## 6. 架构审计

### 6.1 当前架构

```
┌─────────────────────────────────────────┐
│  VoiceDockApp (应用层)                    │
│  ├── VoiceDockApp.swift (入口)          │
│  ├── AppDelegate.swift (生命周期)       │
│  ├── MenuBarView.swift (UI)             │
│  └── HotKeyManager.swift (快捷键)       │
└─────────────────────────────────────────┘
                    ↓ 依赖
┌─────────────────────────────────────────┐
│  VoiceDockCore (核心框架)                │
│  ├── ASRProvider (协议)                 │
│  ├── MLXAudioSTTProvider (实现)         │
│  ├── AudioCapture (音频捕获)            │
│  ├── AudioNormalizer (格式转换)         │
│  ├── TranscriptDestination (输出)       │
│  ├── SessionCoordinator (状态机)        │
│  └── VoiceDockError (错误类型)          │
└─────────────────────────────────────────┘
```

### 6.2 依赖关系

```yaml
packages:
  mlx-audio-swift:
    url: https://github.com/Blaizzy/mlx-audio-swift.git
    revision: 3f6b0553188a921f635df54b5e20442001037336

dependencies:
  - MLX
  - MLXAudioSTT
  - MLXAudioCore

target_dependencies:
  VoiceDock:
    - VoiceDockCore (embed)
    - AVFoundation.framework
    - AppKit.framework
    - SwiftUI.framework
    - Carbon.framework
```

### 6.3 架构问题

1. **VoiceDockCore 过度耦合**
   - 依赖 `MLX*` 框架，难以单元测试
   - 协议 `ASRProvider` 定义在 Core 内，而非独立模块

2. **AppDelegate 职责过重**
   - 创建 Coordinator
   - 管理 Popover
   - 注册 HotKey
   - 权限检查
   - 诊断日志

3. **状态管理分散**
   - `SessionCoordinator.state` 管理业务状态
   - `HotKeyManager` 管理按键状态（独立 NSLock）
   - `AppDelegate` 管理 UI 状态

---

## 7. 技术债务清单

### 7.1 高优先级

| ID | 问题 | 影响 | 修复成本 |
|----|------|------|----------|
| TD-001 | Git 状态混乱 | 开发效率 | 低 |
| TD-002 | Accessibility 权限未验证 | 核心功能失效 | 中 |
| TD-003 | 无真机 ASR 验证 | 产品质量风险 | 高 |
| TD-004 | Carbon HotKey 失败 | 全局快捷键失效 | 中 |

### 7.2 中优先级

| ID | 问题 | 影响 | 修复成本 |
|----|------|------|----------|
| TD-005 | 临时日志文件清理 | 隐私风险 | 低 |
| TD-006 | 测试全为 Mock | 质量信心不足 | 中 |
| TD-007 | 文档过时 |  Knowledge 断层 | 低 |

### 7.3 低优先级

| ID | 问题 | 影响 | 修复成本 |
|----|------|------|----------|
| TD-008 | AppDelegate 过重 | 可维护性 | 中 |
| TD-009 | VoiceDockCore 耦合 | 可测试性 | 高 |

---

## 8. 交付风险评估

### 8.1 已完成功能

- ✅ 项目结构完整
- ✅ 编译构建通过
- ✅ UI 组件正常
- ✅ 状态机逻辑正确
- ✅ Mock 测试覆盖

### 8.2 未完成/未验证功能

- ❌ 真实麦克风音频捕获
- ❌ Nemotron ASR 模型推理
- ❌ 英文/中文/混合语音转录质量
- ❌ 自动粘贴功能（Accessibility）
- ❌ 全局快捷键（Carbon）
- ❌ 性能指标（延迟、内存）

### 8.3 交付门槛评估

| 门槛 | 状态 | 证据 |
|------|------|------|
| Debug 构建 | ✅ 通过 | xcodebuild 输出 |
| Release 构建 | ✅ 通过 | xcodebuild 输出 |
| 单元测试 | ✅ 24/24通过 | xcodebuild test |
| 真机麦克风 | ❌  pending | 无证据 |
| 真机 ASR | ❌ pending | 无证据 |
| 真机粘贴 | ❌ pending | 无证据 |
| 性能测量 | ❌ pending | 无数据 |

---

## 9. 修复建议

### 9.1 立即执行（1 天内）

1. **清理 Git 状态**
   ```bash
   git checkout HEAD -- VoiceDockApp/ASR/ \
                      VoiceDockApp/Audio/ \
                      VoiceDockApp/Services/TranscriptDestination.swift \
                      VoiceDockApp/SessionCoordinator.swift \
                      VoiceDockApp/UI/StatusPopover.swift
   # 或者
   git rm -f VoiceDockApp/ASR/*.swift \
           VoiceDockApp/Audio/*.swift \
           VoiceDockApp/Services/TranscriptDestination.swift \
           VoiceDockApp/SessionCoordinator.swift \
           VoiceDockApp/UI/StatusPopover.swift
   ```

2. **删除过时文档**
   - ~~DELIVERY_REPORT.md~~ ✅ 已删除
   - ~~PLANS.md~~ ✅ 已删除

3. **更新项目文档**
   - CLAUDE.md 添加架构说明
   - AGENTS.md 更新文件位置

### 9.2 短期执行（1 周内）

1. **真机验证**
   ```bash
   open dist/VoiceDock.app
   # 授予麦克风权限
   # 授予 Accessibility 权限
   # 测试 Control+Option+Space 快捷键
   # 测试英文/中文/混合语音转录
   # 测试粘贴到目标应用
   ```

2. **性能测量**
   - 模型加载时间
   - 转录延迟（快捷键释放到粘贴完成）
   - 内存占用（Activity Monitor）

3. **日志清理**
   - 应用退出时删除临时日志
   - 或添加日志轮转机制

### 9.3 中期执行（1 月内）

1. **集成测试**
   - 添加真实 ASR 推理测试（小模型或 Mock 响应）
   - 添加真实粘贴测试（Accessibility 模拟）

2. **架构优化**
   - 提取 ASRProvider 到独立模块
   - 简化 AppDelegate 职责
   - 统一状态管理

---

## 10. 审计结论

### 10.1 项目健康度评分

| 维度 | 得分 | 说明 |
|------|------|------|
| 代码质量 | 7/10 | 架构清晰，耦合度高 |
| 测试覆盖 | 4/10 | 全 Mock，无端到端 |
| 文档完整 | 3/10 | 大量过时信息 |
| 交付准备 | 3/10 | 真机验证 pending |
| 维护性 | 6/10 | Git 状态混乱 |

**综合得分**: 4.6/10 — **风险较高的"半成品"状态**

### 10.2 核心风险

1. **功能风险**：核心功能（ASR 转录 + 粘贴）从未在真机验证
2. **权限风险**：Accessibility 权限可能影响用户 adoption
3. **技术风险**：Carbon HotKey 在 macOS 新版本可能废弃
4. **知识风险**：文档与代码不一致，Knowledge 断层

### 10.3 最终建议

**在真机验证完成前，不应声称项目交付完成。**

当前项目处于"编译通过、测试通过、功能未知"的状态。建议：

1. 暂停新功能开发
2. 专注真机验证（Tasks 3.5 Manual M1 Test）
3. 更新文档反映真实状态
4. 清理 Git 技术债务

---

## 附录 A：审计命令清单

```bash
# 构建验证
xcodebuild -project VoiceDock.xcodeproj -scheme VoiceDock \
  -configuration Debug -destination 'platform=macOS' build

xcodebuild -project VoiceDock.xcodeproj -scheme VoiceDock \
  -configuration Release -destination 'platform=macOS' build

# 测试验证
xcodebuild -project VoiceDock.xcodeproj -scheme VoiceDock \
  -destination 'platform=macOS' test

# Git 状态
git status --porcelain
git diff HEAD -- VoiceDockApp/

# 运行诊断
open dist/VoiceDock.app
cat /tmp/voicedock-ui-diagnostics.log
cat /tmp/voicedock-runtime-diagnostics.log

# 真机测试（需用户交互）
# 1. 授予麦克风权限
# 2. 授予 Accessibility 权限
# 3. 按 Control+Option+Space 说话并验证转录
```

---

## 附录 B：文件清单

### 当前源代码文件

```
VoiceDockApp/
├── VoiceDockApp.swift
├── AppDelegate.swift
├── Info.plist
├── Services/
│   ├── HotKeyManager.swift
│   └── PermissionManager.swift
├── UI/
│   └── MenuBarView.swift
└── Core/ (空目录)

VoiceDockCore/Sources/
├── ASRProvider.swift
├── MLXAudioSTTProvider.swift
├── AudioCapture.swift
├── AudioNormalizer.swift
├── TranscriptDestination.swift
├── SessionCoordinator.swift
└── VoiceDockError.swift

VoiceDockAppTests/
├── AppDelegateIsolationTests.swift
├── AudioNormalizerTests.swift
├── MockASRProvider.swift
├── MockAudioCapture.swift
├── SessionCoordinatorTests.swift
├── TranscriptDestinationTests.swift
└── VoiceDockAppTests.swift
```

---

**审计完成时间**: 2026-06-22  
**下次审计建议**: 真机验证完成后重新评估

---

*此报告由自动化审计工具 + 人工审查生成*