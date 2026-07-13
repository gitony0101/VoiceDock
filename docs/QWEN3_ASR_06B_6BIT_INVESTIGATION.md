# Qwen3-ASR 0.6B 6-bit 集成调查报告

**调查日期**: 2026-07-10  
**调查范围**: 只读分析，未修改任何源码  
**目标模型**: `mlx-community/Qwen3-ASR-0.6B-6bit`  
**回滚基线**: `mlx-community/nemotron-3.5-asr-streaming-0.6b-8bit`

---

## 1. 执行摘要 (Executive Conclusion)

### ✅ 核心结论

| 问题 | 答案 | 证据来源 |
|------|------|----------|
| 当前 mlx-audio-swift 是否支持 Qwen3-ASR? | **是，已完整支持** | `Sources/MLXAudioSTT/Models/Qwen3ASR/Qwen3ASR.swift` |
| 是否需要依赖升级? | **否** | 当前 revision `3f6b055` 包含完整实现 |
| 是否支持本地目录加载? | **是** | `fromModelDirectory(URL)` 公开 API |
| 6-bit 量化是否需要特殊处理? | **否** | `config.perLayerQuantization` 自动处理 |
| 是否支持中文/英文/混合? | **是** | 语言映射表 + `extractLanguage()`/`mergeLanguages()` |
| 推荐存储架构 | `~/Library/Application Support/VoiceDock/Models/Qwen3-ASR-0.6B-6bit/` | 设计报告第 8 节 |
| 是否必须用 `fromModelDirectory`? | **是** | 目标路径不在 `HubCache.default` 下 |

### 🎯 推荐实施方案

创建独立 `Qwen3ASRProvider` 实现，显式调用：
```swift
let modelDir = URL(fileURLWithPath: "~/Library/Application Support/VoiceDock/Models/Qwen3-ASR-0.6B-6bit".expandingTildeInPlace)
model = try await Qwen3ASRModel.fromModelDirectory(modelDir)
```

保留 `MLXAudioSTTProvider` (Nemotron) 作为回滚基线。

---

## 2. 当前依赖版本 (Current Dependency Versions)

### Package.swift 锁定

```swift
// VoiceDock/Package.swift
.package(url: "https://github.com/Blaizzy/mlx-audio-swift.git", revision: "3f6b0553188a921f635df54b5e20442001037336"),
.package(url: "https://github.com/ml-explore/mlx-swift.git", exact: "0.31.4")
```

### Package.resolved 确认

| 包 | Identity | Revision | Version |
|----|----------|----------|---------|
| mlx-audio-swift | `mlx-audio-swift` | `3f6b0553188a921f635df54b5e20442001037336` | branch: main |
| mlx-swift | `mlx-swift` | `dc43e62d7055353c7f99fa071a4e71d29dfddc44` | 0.31.4 |
| swift-huggingface | `swift-huggingface` | `b721959445b617d0bf03910b2b4aced345fd93bf` | 0.9.0 |
| swift-transformers | `swift-transformers` | `2fa33e1f5e7131a7fc64c28e6d161dcec0d24820` | 1.3.3 |

### Checkout 验证

```bash
$ git -C ./build/derived-data/SourcePackages/checkouts/mlx-audio-swift rev-parse HEAD
3f6b0553188a921f635df54b5e20442001037336

$ git -C ./build/derived-data/SourcePackages/checkouts/mlx-audio-swift log --oneline -1
3f6b055 Fix Qwen3-TTS CustomVoice voice parsing (#186)
```

---

## 3. 当前 Nemotron 物理路径 (Current Nemotron Physical Path)

### 实际下载目录 (ModelUtils 写入位置)

```
~/.cache/huggingface/hub/mlx-audio/mlx-community_nemotron-3.5-asr-streaming-0.6b-8bit/
├── config.json        (156 KB, -rw-------)
├── model.safetensors  (721 MB, -rw-------)
└── vocab.txt          (76 KB, -rw-------)
```

**总大小**: 721 MB  
**文件类型**: 实体文件 (非符号链接)

### Hugging Face Hub 缓存 (内部 blobs/snapshots 结构)

```
~/.cache/huggingface/hub/models--mlx-community--nemotron-3.5-asr-streaming-0.6b-8bit/
├── blobs/
│   ├── 1a57cbb1f31251413547ebb48441a6d1867a6d186cd7a59  (76 KB, vocab.txt)
│   ├── 3acd1f4328b1e0207b61b62f33252f7192f98923  (156 KB, config.json)
│   └── a64a4da048e7d28dde4cd4ff61ce59308a63314bb5563e73e06c24aae50ea941  (721 MB, model.safetensors)
├── refs/
│   └── main  (contains commit hash)
└── snapshots/
    └── 7279359e4481b5e9e185a318bd618e429c6d86cd/
        ├── config.json        → ../../blobs/...
        ├── model.safetensors  → ../../blobs/...
        └── vocab.txt          → ../../blobs/...
```

**注意**: `snapshots/` 下文件本机为实体副本 (非 symlink)，因 `createSymlink()` 失败回退为 `copy`。

### HF 环境变量状态

```bash
HF_HOME=
HF_HUB_CACHE=
HUGGINGFACE_HUB_CACHE=
XDG_CACHE_HOME=
TRANSFORMERS_CACHE=
```

**默认 cache 路径**: `~/.cache/huggingface/hub/` (非沙盒 macOS 应用)

---

## 4. 当前缓存机制 (Current Caching Mechanism)

### ModelUtils.resolveOrDownloadModel 流程

1. **构造下载目标路径**:
   ```swift
   let modelSubdir = repoID.description.replacingOccurrences(of: "/", with: "_")
   let modelDir = cache.cacheDirectory
       .appendingPathComponent("mlx-audio")
       .appendingPathComponent(modelSubdir)
   // 例如: ~/.cache/huggingface/hub/mlx-audio/mlx-community_nemotron-...
   ```

2. **检查本地缓存**:
   - `fileExists(atPath: modelDir.path)`
   - 存在 `.safetensors` 非零文件
   - `config.json` 可解析为有效 JSON
   - 命中则直接返回本地 `modelDir`

3. **下载逻辑** (缓存未命中时):
   - 使用 `HubClient.downloadSnapshot()`
   - 写入 `cache.cacheDirectory/mlx-audio/<repo_underscore>/`
   - 下载后验证非零文件存在

### HubCache.default 位置解析顺序

`CacheLocationProvider` 按以下优先级确定 `cacheDirectory`:

1. `HF_HUB_CACHE` 环境变量
2. `HF_HOME` 环境变量 + `/hub`
3. `~/.cache/huggingface/hub/` (非沙盒 macOS)
4. `Library/Caches/huggingface/hub/` (沙盒 Apple 应用)

VoiceDock 未启用沙盒 (`ENABLE_HARDENED_RUNTIME: NO`)，默认使用 `~/.cache/huggingface/hub/`。

---

## 5. Qwen3-ASR 支持状态 (Qwen3-ASR Support Status)

### 源码位置

```
./build/derived-data/SourcePackages/checkouts/mlx-audio-swift/
└── Sources/MLXAudioSTT/Models/Qwen3ASR/
    ├── Qwen3ASR.swift           (主模型实现，1842 行)
    ├── Qwen3ForcedAligner.swift (力对齐模型，598 行)
    └── README.md                (文档)
    └── (私有目录，含配置等)
```

### 支持模型列表 (README.md 第 14-19 行)

```
ASR (0.6B):
- mlx-community/Qwen3-ASR-0.6B-bf16
- mlx-community/Qwen3-ASR-0.6B-8bit
- mlx-community/Qwen3-ASR-0.6B-6bit  ← 目标模型
- mlx-community/Qwen3-ASR-0.6B-4bit
```

### Hugging Face 仓库验证

**URL**: https://huggingface.co/mlx-community/Qwen3-ASR-0.6B-6bit

| 文件 | 大小 |
|------|------|
| `model.safetensors` | 857 MB |
| `model.safetensors.index.json` | 71.8 kB |
| `tokenizer_config.json` | 12.5 kB |
| `merges.txt` | 1.67 MB |
| `vocab.json` | 2.78 MB |
| `config.json` | 7.19 kB |
| `preprocessor_config.json` | 330 B |
| `generation_config.json` | 142 B |
| `chat_template.json` | 1.16 kB |

**总大小**: ~862 MB  
**许可证**: Apache-2.0  
**存储格式**: Safetensors (MLX 兼容)

---

## 6. 依赖升级需求分析 (Upgrade Requirement Analysis)

### 结论：无需升级

| 检查项 | 状态 | 证据 |
|--------|------|------|
| Qwen3ASR.swift 是否存在 | ✅ 存在 | `Sources/MLXAudioSTT/Models/Qwen3ASR/Qwen3ASR.swift` |
| `fromPretrained` 签名 | ✅ 支持 | 第 1761 行：`public static func fromPretrained(_ modelPath: String, cache: HubCache = .default)` |
| `fromModelDirectory` | ✅ 支持 | 第 1786 行：`public static func fromModelDirectory(_ modelDir: URL)` |
| `generate(audio:)` | ✅ 支持 | 第 1334 行 |
| `generateStream` | ✅ 支持 | 第 1417 行 |
| 6-bit 量化处理 | ✅ 支持 | 第 1820-1831 行：`if perLayerQuantization != nil { quantize(...) }` |
| 语言支持 | ✅ 中文/英文/混合 | 第 75-81 行语言映射表 |

### 潜在风险 (如升级)

若升级 `mlx-audio-swift`，可能导致:
1. `mlx-swift` 最低版本要求变化 → 需同步升级
2. API breaking changes → `MLXAudioSTTProvider` 需适配
3. Swift 6 并发检查更严格 → 需验证 actor 边界

**建议**: 保持当前 revision，直至 Qwen 集成验证完成。

---

## 7. 本地路径加载支持 (Local Path Loading Support)

### Qwen3ASRModel.fromModelDirectory

**签名** (Qwen3ASR.swift:1786):
```swift
public static func fromModelDirectory(_ modelDir: URL) async throws -> Qwen3ASRModel
```

**必需文件** (函数内部检查):
- `config.json` (第 1788-1790 行)
- `*.safetensors` (第 1807-1813 行)
- 自动生成 `tokenizer.json` (第 1799 行，若缺失)

**完整流程**:
```
1. 读取 config.json → Qwen3ASRConfig
2. 获取 perLayerQuantization (6-bit 关键)
3. 生成 tokenizer.json (Qwen3 ASR 模型不附带)
4. 加载 tokenizer: AutoTokenizer.from(modelFolder:)
5. 加载所有 .safetensors 文件 → weights 字典
6. 量化 (若 perLayerQuantization != nil)
7. model.update(parameters: ...) 载入权重
8. eval(model) → 返回
```

### 与 Nemotron 对比

| 模型 | fromPretrained 接受 | fromModelDirectory/fromDirectory |
|------|---------------------|----------------------------------|
| Qwen3ASRModel | `String` repo ID | `URL` (显式路径) |
| NemotronASRModel | `String` repo ID | `URL` (fromDirectory) |

**关键差异**:
- `fromPretrained` 只接受 repo ID 字符串 (如 `"mlx-community/Qwen3-ASR-0.6B-6bit"`)
- `fromPretrained` 内部调用 `resolveOrDownloadModel` → 下载到 `HubCache.cacheDirectory/mlx-audio/...`
- 若使用自定义路径 (`~/Library/Application Support/VoiceDock/Models/...`)，**必须显式调用 `fromModelDirectory`**

---

## 8. 推荐模型存储架构 (Recommended Model Storage Architecture)

### 目标路径

```
~/Library/Application Support/VoiceDock/Models/
├── Qwen3-ASR-0.6B-6bit/
│   ├── config.json
│   ├── model.safetensors
│   ├── tokenizer_config.json
│   ├── merges.txt
│   ├── vocab.json
│   └── ... (全部 HF repo 文件)
└── nemotron-3.5-asr-streaming-0.6b-8bit/  (可选回滚副本)
```

### 设计理由

| 需求 | 方案 | 理由 |
|------|------|------|
| 确定性路径 | `~/Library/Application Support/VoiceDock/Models/<repo-name>/` | 用户可 Finder 访问，可独立管理 |
| 检查模型是否安装 | 检查目录存在 + `config.json` + `model.safetensors` 非零 | 与 `resolveOrDownloadModel` 逻辑一致 |
| 下载模型 | 独立下载流程 (非 `fromPretrained` 隐式下载) | 可显示进度、可取消、可重试 |
| 验证下载完成 | 检查所有 `.safetensors` 文件 size > 0 | 防止损坏/不完整 |
| 清理不完整下载 | 检测到失败 → 删除整个目录 | 避免脏数据 |
| Finder 可见 | 用户友好路径 | `open ~/Library/Application\ Support/VoiceDock/Models/` |
| 删除模型 | `FileManager.removeItem(at:)` | 整目录删除 |
| 保留 Nemotron | 独立目录共存 | 互不干扰，安全回滚 |
| 防止重复下载 | 下载前检查目录已存在且有效 | 避免浪费带宽/时间 |

### 与 HubCache 的兼容性

若使用 `HubCache(cacheDirectory: customURL)` 指定自定义路径:
```swift
let customCache = HubCache(cacheDirectory: URL(fileURLWithPath: "~/Library/Application Support/VoiceDock/Models".expandingTildeInPlace))
let model = try await Qwen3ASRModel.fromPretrained("mlx-community/Qwen3-ASR-0.6B-6bit", cache: customCache)
// 会下载到: ~/Library/Application Support/VoiceDock/Models/mlx-audio/mlx-community_Qwen3-ASR-0.6B-6bit/
```

**但推荐显式路径控制**:
```swift
let modelDir = URL(fileURLWithPath: "~/Library/Application Support/VoiceDock/Models/Qwen3-ASR-0.6B-6bit".expandingTildeInPlace)
let model = try await Qwen3ASRModel.fromModelDirectory(modelDir)
```

---

## 9. 提议实现文件 (Proposed Implementation Files)

### Phase 2: 实现阶段预计修改/新建文件

| 文件 | 操作 | 职责 |
|------|------|------|
| `VoiceDockCore/Sources/Qwen3ASRProvider.swift` | 新建 | `ASRProvider` 实现，调用 `Qwen3ASRModel.fromModelDirectory` |
| `VoiceDockCore/Sources/ASRModelType.swift` | 新建 | 枚举：`.qwen3_0_6B_6bit`, `.nemotron_0_6B_8bit` |
| `VoiceDockCore/Sources/ModelManager.swift` | 新建 | 模型安装检查/下载/验证/删除 |
| `VoiceDockCore/Sources/MLXAudioSTTProvider.swift` | 保留 | 回滚基线，不改默认模型名 |
| `VoiceDockApp/Models/DefaultASRModel.swift` | 新建 | 默认模型配置 (当前 = Nemotron，验证后改 Qwen) |
| `Package.swift` | 可能修改 | 若需升级 `mlx-audio-swift` (目前不需要) |
| `~/Library/Application Support/VoiceDock/Models/Qwen3-ASR-0.6B-6bit/` | 新建目录 | Qwen 模型存储 |

### 关键实现决策

1. **ASRProvider 协议无需修改**:
   ```swift
   public protocol ASRProvider: Actor {
       func load() async throws
       func warmup() async throws
       func transcribe(audio: [Float]) async throws -> String
       func unload() async
   }
   ```
   Qwen3 的 `generate(audio:)` 返回 `STTOutput`，有 `.text` 属性 → 适配简单。

2. **language 参数策略**:
   - Qwen3 `generate` 接受 `language: String? = nil`
   - `nil` → 自动检测 (中英混合识别)
   - 当前 `MLXAudioSTTProvider` 不传 `language` → Qwen3 可直接兼容

3. **warmup 实现**:
   - Nemotron: 16kHz 静音 1 秒 (`MLXArray(repeating: 0, count: 16_000)`)
   - Qwen3: 同样 16kHz 输入，相同暖机策略

---

## 10. 升级与回归风险 (Upgrade and Regression Risks)

### 若升级 mlx-audio-swift

| 风险 | 概率 | 影响 | 缓解措施 |
|------|------|------|----------|
| `mlx-swift` 最低版本变化 | 中 | 需同步升级 | 检查 `mlx-audio-swift/Package.swift` 依赖 |
| `Qwen3ASRModel.fromModelDirectory` 签名变化 | 低 | 编译失败 | 锁定 revision 或 semver tag |
| `generate` 返回类型变化 | 低 | 运行时崩溃 | 验证 `STTOutput.text` 存在 |
| Swift 6 并发检查 | 中 | 新警告/错误 | 验证 actor 隔离边界 |
| Nemotron 加载失败 | 低 | 回滚基线失效 | 物理验证 Nemotron 仍正常工作 |

### 当前 Revision 稳定性

```bash
$ git -C ./build/derived-data/SourcePackages/checkouts/mlx-audio-swift log --oneline -10
3f6b055 Fix Qwen3-TTS CustomVoice voice parsing (#186)
...
```

当前 pinned 到 branch `main` 的特定 commit，**非 tag**。优点是最新兼容 Qwen3，风险是 main 分支可能引入不稳定变更。

**建议**: 若 Qwen 集成验证通过，考虑锁定到稳定 tag (若有)。

---

## 11. 下一步实施阶段 (Exact Next Implementation Phase)

### Phase 2: 实现路线图

按以下顺序执行：

#### 2.1 兼容性验证 (必读)
- [ ] 确认 `mlx-audio-swift` revision 支持 Qwen3 (✅ 已完成)
- [ ] 确认本地绝对路径加载方式 (✅ 已完成：`fromModelDirectory`)
- [ ] 下载 Qwen 模型到目标目录
- [ ] 验证模型文件完整性 (config.json 可解析 + safetensors 非零)

#### 2.2 Qwen3ASRProvider 实现
- [ ] 新建 `Qwen3ASRProvider: ASRProvider`
- [ ] 实现 `load()` → `Qwen3ASRModel.fromModelDirectory`
- [ ] 实现 `warmup()` → 16kHz 静音 1 秒
- [ ] 实现 `transcribe(audio:)` → `model.generate(audio:).text`
- [ ] 实现 `unload()` → `model = nil`

#### 2.3 SessionCoordinator 集成
- [ ] 不改 `SessionCoordinator.swift` (依赖注入保持不变)
- [ ] 应用启动时选择默认 ASRProvider (当前 = Nemotron)
- [ ] 添加模型选择 UI/配置 (可选，MVP 后)

#### 2.4 验证测试
- [ ] 英文语音测试
- [ ]  Mandarin 中文测试
- [ ] 中英混合测试
- [ ] 技术术语测试
- [ ] 加载时间对比 (Qwen vs Nemotron)
- [ ] 转录时间对比
- [ ] 峰值内存对比
- [ ] 松手到粘贴延迟对比

#### 2.5 默认值切换
- [ ] 验证通过后，修改默认 ASRProvider = Qwen3
- [ ] 保留 Nemotron 为回滚选项

---

## 12. 证据索引 (Evidence Index)

### 文件路径与行号

| 符号 | 文件 | 行号 |
|------|------|------|
| `Qwen3ASRModel.fromPretrained` | `Sources/MLXAudioSTT/Models/Qwen3ASR/Qwen3ASR.swift` | 1761 |
| `Qwen3ASRModel.fromModelDirectory` | `Sources/MLXAudioSTT/Models/Qwen3ASR/Qwen3ASR.swift` | 1786 |
| `Qwen3ASRModel.generate(audio:)` | `Sources/MLXAudioSTT/Models/Qwen3ASR/Qwen3ASR.swift` | 1334 |
| `Qwen3ASRModel.generateStream` | `Sources/MLXAudioSTT/Models/Qwen3ASR/Qwen3ASR.swift` | 1417 |
| 6-bit 量化处理 | `Sources/MLXAudioSTT/Models/Qwen3ASR/Qwen3ASR.swift` | 1820-1831 |
| 语言映射表 | `Sources/MLXAudioSTT/Models/Qwen3ASR/Qwen3ASR.swift` | 75-81 |
| `NemotronASRModel.fromPretrained` | `Sources/MLXAudioSTT/Models/NemotronASR/NemotronASRModel.swift` | 431 |
| `ModelUtils.resolveOrDownloadModel` | `Sources/MLXAudioCore/ModelUtils.swift` | 38-66 |
| `HubCache.default` | `Sources/HuggingFace/Hub/HubCache.swift` | 73 |
| `HubCache.cacheDirectory` | `Sources/HuggingFace/Hub/HubCache.swift` | 76 |
| `CacheLocationProvider` | `Sources/HuggingFace/Shared/CacheLocationProvider.swift` | 165-196 |

### 命令记录

```bash
# 确认 mlx-audio-swift revision
git -C ./build/derived-data/SourcePackages/checkouts/mlx-audio-swift rev-parse HEAD
# 输出：3f6b0553188a921f635df54b5e20442001037336

# 查找 Qwen3ASR 源码
grep -rln "Qwen3ASRModel\|Qwen3ASR" ./build/derived-data/SourcePackages/checkouts/mlx-audio-swift/Sources
# 输出: Sources/MLXAudioSTT/Models/Qwen3ASR/Qwen3ASR.swift, README.md, Qwen3ForcedAligner.swift

# 定位 Nemotron 物理路径
ls -la ~/.cache/huggingface/hub/mlx-audio/mlx-community_nemotron-3.5-asr-streaming-0.6b-8bit/

# 确认 Package.resolved 锁定
grep -A4 '"identity" : "mlx-audio-swift"' Package.resolved
```

---

## 简明摘要 (Concise Summary)

| 问题 | 答案 |
|------|------|
| **当前 Nemotron 模型路径** | `~/.cache/huggingface/hub/mlx-audio/mlx-community_nemotron-3.5-asr-streaming-0.6b-8bit/` (721 MB) |
| **当前 mlx-audio-swift 是否支持 Qwen3-ASR** | ✅ **是**，revision `3f6b055` 含完整 `Qwen3ASRModel` 实现 |
| **是否需要升级** | ❌ **否**，当前版本已支持 |
| **是否支持本地目录加载** | ✅ **是**，`Qwen3ASRModel.fromModelDirectory(URL)` |
| **最安全的下一步** | 1. 下载 Qwen 模型到 `~/Library/Application Support/VoiceDock/Models/Qwen3-ASR-0.6B-6bit/`<br>2. 新建 `Qwen3ASRProvider: ASRProvider`<br>3. 保留 Nemotron 为回滚基线<br>4. 完成中英混合验证后再切换默认值 |

---

**调查状态**: ✅ Phase 1 只读调查完成  
**下一步**: Phase 2 实现 (需 owner 授权编辑源码)