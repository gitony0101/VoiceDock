# VoiceDock Push-to-Talk MVP — 交付状态报告

**最后更新**: 2026-06-22  
**状态**: 🟡 代码完成，真机验证待完成

---

## 快速摘要

| 验收项 | 状态 | 证据 |
|--------|------|------|
| Debug 构建 | ✅ 通过 | `xcodebuild` 输出 |
| Release 构建 | ✅ 通过 | `xcodebuild` 输出 |
| 单元测试 | ✅ 24/24 通过 | Mock 测试 |
| 真机麦克风测试 | ⏳ 待验证 | 需 M1 设备 |
| 真机 ASR 转录 | ⏳ 待验证 | 需 Nemotron 推理 |
| 自动粘贴功能 | ⏳ 待验证 | 需 Accessibility 权限 |
| 全局快捷键 | ⏳ 部分 | Carbon 注册失败，回退 NSEvent |

---

## 项目概述

VoiceDock 是一个原生 macOS 菜单栏应用，实现一键通 (Push-to-Talk) 语音转文字功能。

**技术栈**:
- Swift 6, SwiftUI, AppKit, AVFoundation
- Blaizzy/mlx-audio-swift (MLXAudioSTT)
- mlx-community/nemotron-3.5-asr-streaming-0.6b-8bit
- macOS 14+, arm64 (Apple Silicon)

---

## 架构说明

```
VoiceDock/
├── VoiceDockApp/           # UI 层
│   ├── VoiceDockApp.swift
│   ├── AppDelegate.swift
│   ├── MenuBarView.swift
│   ├── HotKeyManager.swift
│   └── PermissionManager.swift
├── VoiceDockCore/          # 业务逻辑框架
│   ├── ASRProvider.swift
│   ├── MLXAudioSTTProvider.swift
│   ├── AudioCapture.swift
│   ├── AudioNormalizer.swift
│   ├── TranscriptDestination.swift
│   ├── SessionCoordinator.swift
│   └── VoiceDockError.swift
├── VoiceDockAppTests/      # 单元测试 (Mock-based)
└── docs/                   # 文档
    └── VOICELOCK_DEEP_AUDIT_REPORT.md
```

---

## 已完成功能

### ✅ 构建与测试

```bash
# Debug 构建
xcodebuild -project VoiceDock.xcodeproj -scheme VoiceDock \
  -configuration Debug -destination 'platform=macOS' build
# → BUILD SUCCEEDED

# Release 构建
xcodebuild -project VoiceDock.xcodeproj -scheme VoiceDock \
  -configuration Release -destination 'platform=macOS' build
# → BUILD SUCCEEDED

# 单元测试
xcodebuild -project VoiceDock.xcodeproj -scheme VoiceDock \
  -destination 'platform=macOS' test
# → Test Suite 'All tests' passed (24 tests)
```

### ✅ 代码重构

- 核心逻辑已迁移至 `VoiceDockCore/` 框架
- Git 状态已清理（旧文件删除已提交）
- 项目结构清晰化

### ✅ UI 组件

- 菜单栏图标（状态指示）
- Popover 状态显示
- 权限请求提示
- 诊断信息显示

### ✅ 权限处理

- 麦克风权限请求（预解释）
- Accessibility 权限请求（深链到系统设置）
- Info.plist 声明完整

---

## 待验证功能

### ⏳ 真机端到端测试

以下功能**代码已实现**，但**从未在真实设备上完整验证**：

1. **真实麦克风捕获**
   - 代码：`AudioCapture.start()/stop()`
   - 验证：需 M1 设备 + 真实说话

2. **Nemotron ASR 转录**
   - 代码：`MLXAudioSTTProvider.transcribe()`
   - 验证：需模型下载 + 真实推理
   - 测试覆盖：仅 `MockASRProvider`（硬编码返回值）

3. **自动粘贴功能**
   - 代码：`TranscriptDestination.paste()`
   - 依赖：Accessibility 权限
   - 现状：测试日志显示 `Accessibility not trusted`，粘贴被跳过

4. **全局快捷键**
   - 代码：`HotKeyManager` (Carbon RegisterEventHotKey)
   - 问题：错误码 -9878，回退到 NSEvent
   - 影响：仅应用内有效，后台时无效

---

## 已知问题与限制

### 1. Carbon HotKey 注册失败

**现象**:
```log
Carbon RegisterEventHotKey failed: -9878
Falling back to NSEvent monitors
```

**影响**:
- 全局快捷键（应用后台时）不工作
- 应用内快捷键正常（NSEvent local monitor）

**可能原因**:
- Accessibility 权限未授予
- macOS 沙盒限制
- 热键冲突

### 2. 粘贴功能依赖 Accessibility

**现状**:
```log
[TranscriptDestination] Accessibility not trusted; leaving transcript on clipboard
```

**影响**:
- 转录文本仅复制到剪贴板
- 不会自动粘贴到目标应用
- 用户需手动 Cmd-V

### 3. 测试覆盖率为 Mock

**问题**:
- 24 个测试全部使用 `MockASRProvider` 和 `MockAudioCapture`
- 无真实 ASR 推理测试
- 无真实音频捕获测试

**风险**:
- 测试通过 ≠ 功能可用
- 集成问题只能在真机发现

### 4. 模型下载与缓存

**首次运行**:
- 需下载 ~756 MB 模型（mlx-community/nemotron-3.5-asr-streaming-0.6b-8bit）
- 下载失败有 3 次重试
- 模型缓存位置由 MLX 管理

---

## 隐私与安全

**承诺**:
- ✅ 本地麦克风处理，无云端上传
- ✅ 无遥测代码
- ✅ 无转录历史存储
- ✅ 模型权重不包含在应用包内

**日志文件**（临时）:
- `/tmp/voicedock-ui-diagnostics.log` — UI 诊断
- `/tmp/voicedock-runtime-diagnostics.log` — 运行时诊断
- 内容：时间戳、状态转换、事件计数
- 风险：包含转录元数据（长度、时间）

---

## 使用指南

### 安装与运行

```bash
# 打开应用
open dist/VoiceDock.app

# 或通过 Xcode 运行
xcodebuild -project VoiceDock.xcodeproj -scheme VoiceDock run
```

### 权限授予

1. **麦克风权限**: 应用启动时自动请求
2. **Accessibility 权限**: 应用启动时自动请求
   - 需手动在 `系统设置 → 隐私与安全 → 辅助功能` 中授予
   - 授予后需重启应用

### 快捷键

- **默认**: `Control + Option + Space`
- **操作**: 按住说话，松开转录
- **注意**: 当前仅应用内有效（Carbon 注册失败）

### 预期行为

1. 菜单栏显示麦克风图标（绿色 = 就绪）
2. 按住快捷键 → 状态变为"Listening..."（蓝色）
3. 松开快捷键 → 状态变为"Transcribing..."（紫色）
4. 转录完成 → 文本粘贴到当前焦点应用

---

## 待完成事项

### 高优先级（交付前必须完成）

- [ ] **真机 M1 测试**
  - [ ] 英文语音转录验证
  - [ ] 中文语音转录验证
  - [ ] 混合语音转录验证
  - [ ] 性能测量（延迟、内存）
- [ ] **Accessibility 权限流程验证**
  - [ ] 确认深链正确打开系统设置
  - [ ] 确认授权后粘贴功能正常
- [ ] **Carbon HotKey 问题排查**
  - [ ] 确认错误码 -9878 根本原因
  - [ ] 修复或接受回退方案

### 中优先级（交付后可选）

- [ ] 集成测试（真实 ASR 推理）
- [ ] 日志清理机制（退出时删除临时文件）
- [ ] 热键冲突检测与提示

### 低优先级（未来版本）

- [ ] 可配置热键 UI
- [ ] 模型选择/切换
- [ ] VAD / 自动端点检测
- [ ] 部分流式转录

---

## 交付清单

| 项目 | 状态 | 位置 |
|------|------|------|
| 源代码 | ✅ | `VoiceDockApp/`, `VoiceDockCore/` |
| 构建产物 | ✅ | `dist/VoiceDock.app` |
| 单元测试 | ✅ | `VoiceDockAppTests/` |
| 架构文档 | ✅ | `docs/VOICELOCK_DEEP_AUDIT_REPORT.md` |
| 交付文档 | ✅ | 本文件 |
| 真机验证 | ⏳ | 待完成 |
| 性能报告 | ⏳ | 待完成 |

---

## 下一步行动

### 需要用户（所有者）执行

1. **在 M1 Mac 上运行应用**
   ```bash
   open dist/VoiceDock.app
   ```

2. **授予所有权限**
   - 麦克风：允许
   - Accessibility：系统设置 → 隐私与安全 → 辅助功能 → 勾选 VoiceDock

3. **测试完整流程**
   - 按住 `Control+Option+Space`
   - 说一段话（英文/中文/混合）
   - 松开快捷键
   - 验证文本是否粘贴到目标应用

4. **记录证据**
   - 截图：菜单栏状态
   - 截图：转录结果
   - 测量：按键释放到粘贴完成的时间

### 量度指标

| 指标 | 目标 | 实测 |
|------|------|------|
| 模型加载时间 | < 60s (首次) | — |
| 转录延迟 (10s 语音) | < 5s | — |
| 端到端时间 | < 10s | — |
| 内存占用 | < 2GB | — |

---

## 联系方式与反馈

**问题报告**: 发现任何问题，请提供：
1. macOS 版本
2. 错误日志（`/tmp/voicedock-*.log`）
3. 复现步骤

**功能建议**: 请标注优先级（高/中/低）

---

*最后提交*: `debf0e9 refactor: migrate core logic to VoiceDockCore framework`  
*审计追踪*: 详见 `docs/VOICELOCK_DEEP_AUDIT_REPORT.md`