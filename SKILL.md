---
name: guodance-drama-director
description: Guodance 短剧导演：把剧本、大纲或故事点做成可发布的竖屏 AI 短剧成片。剧本可拍性诊断 → 角色与场景资产锁定 → 段级分镜 → Seedance 提示词 → 生成与质检重抽 → 配音口型 → 混音字幕 → 平台交付。含先导片闸门、可生成性评分、断点续跑与预算控制。当用户要“Guodance 短剧 / AI 短剧一键出片 / 剧本变短剧 / Seedance 短剧 / 短剧成片 / AI 导演拍短剧”时使用。纯剧本创作或剧本诊断走 duanju-hitmaker；品牌广告片走 viral-ad-director 或 cg-ad-director。
metadata:
  short-description: Guodance：从剧本到可发布短剧成片的 AI 导演流水线
---

# Guodance Drama Director

Guodance 是一套短剧导演工作流。把一集或一部剧本做成能直接发布的竖屏短剧。默认视频主引擎是 Seedance（2.5 或当前可用版本，图生视频 + 角色参考图 + 首尾帧），但流水线与工具解耦：有视频模型就跑到成片，没有就交付可直接投喂的生成包。多集共用系列 bible 与资产，做法见 `references/orchestration.md` 的“多集模式”。

## 什么叫“出片”

不是生成了一堆镜头，而是五件事同时成立：

- **叙事**：前 3 秒有钩子，每 15 秒有信息增量，集末有卡点。
- **视觉**：同一角色跨镜不换脸，轴线、光照、道具、服化连续。
- **表演**：像人在演，不像在念稿；有听戏、有反应、有停顿。
- **声音**：对白清楚、口型对得上、有环境声与音乐、响度达标。
- **交付**：成片 + 封面 + 标题文案 + 质检报告 + 可重抽的工程文件。

缺任何一项都不算完成。宁可明确报告“哪一段没过”，也不要悄悄把坏镜头拼进成片。

## 先定三件事

用户没指定就用默认值，开工时一句话声明假设，不要连问十个问题。

| 参数 | 默认 | 何时改 |
|---|---|---|
| 规格 | 9:16，1080×1920，30fps，单集 60–90 秒 | 用户指定横屏、时长或平台 |
| 交付 | `broadcast`（对白 + BGM + 环境音 + 可选字幕）+ `clean`（纯对白干声） | 用户只要素材、只要无声画面，或明确不要 BGM（只交 clean） |
| 自动化 | `auto`：只在先导片停一次；用户说“全自动”则连这次也跳过 | 用户要逐镜确认 |

自动化程度不改变质量闸门，只改变谁来拍板。

## 开工第一屏

正式动手前，用不超过 12 行说清：

1. 一句话卖点与情绪承诺；
2. 规格、预计段数、预计生成次数、时间成本；
3. 题材与视觉方向（一句话）；
4. 四个闸门里哪些需要用户拍板；
5. 当前缺什么工具、会走哪条降级路径。

然后直接开工。不要用“是否需要我继续”代替工作。

## 生产线

严格按顺序。每段的完成标准写在表里，不达标不进下一段。

| 阶段 | 做什么 | 完成标准 | 读什么 | 闸门 |
|---|---|---|---|---|
| 0 立项 | 定规格、受众、交付模式、预算 | 参数写进项目根目录 `brief.md` | `references/orchestration.md` | — |
| 1 剧本体检 | 判断完整度；诊断钩子/节奏/逻辑/合规；生产化改写 | 有总分、P0/P1 清单、可拍分场稿 | `references/story-craft.md` | G1 |
| 2 视觉圣经 | 题材基调、色彩脚本、镜头系统、资产清单 | `bible.md` 可直接给美术/生成用 | `references/genre-visual.md`、`references/asset-bible.md` | — |
| 3 资产锁定 | 角色三视图、表情、服装、场景板、道具 | 每个角色/场景有可用参考图与编号 | `references/asset-bible.md` | G1 |
| 4 分镜 | 按情绪节拍拆镜，标表演、台词、构图、光影；用 TTS 草稿校准台词时长 | 分镜表通过校验，红镜头已标 | `references/shot-language.md`、`references/performance-direction.md` | — |
| 5 预审 | 连续性、轴线、可生成性、台词时长 | `validate-shotlist.ps1` 零 ERROR | `references/continuity-checklist.md` | — |
| 6 提示词 | 段级编译，挂参考图、首尾帧、负面词 | 自检 10 条全过，`lint-prompts.ps1` 零 ERROR | `references/prompt-playbook.md`、`references/scene-block-template.md` | — |
| 7 先导片 | 只生成 1 段高难度样片 | 脸、表演、光影、口型四项达标 | 同上 + `references/qc-rubric.md` | **G2** |
| 8 批量生成 | 逐段生成、质检、诊断、重抽 | 每段有 take 记录与通过结论 | `references/retry-playbook.md`、`references/qc-rubric.md` | G3 |
| 9 声音 | 最终 TTS、口型对齐、环境、BGM、混音 | 响度与口型达标，clean 轨保留 | `references/audio-post.md` | — |
| 10 剪辑交付 | 按 EDL 拼接、调色、字幕、封面、平台适配 | 技术质检通过，物料齐全 | `references/edit-craft.md`、`references/platform-delivery.md` | G4 |

## 生成单位：镜 / 段 / 场 / 集

不要按“同场景合并成一条长视频”来排——模型单次生成有上限。统一用四层单位，所有文档和脚本都按这个口径：

| 单位 | 定义 | 时长 | 例子 |
|---|---|---|---|
| 镜 shot | 一个机位、一次连续拍摄 | 1.5–6 秒 | 特写：手指按住信封 |
| 段 segment | **一次模型调用**，可含 1–3 镜 | 4–12 秒，默认 8 秒 | 两句对话 + 一个反应镜 |
| 场 scene | 同一地点、同一时间、同一光线状态 | 3–8 段 | 祠堂对峙 |
| 集 episode | 一次交付 | 60–120 秒 | EP01 |

合并成一段的条件，必须全部满足：

- 同一地点、同一时间、同一光线方向；
- 动作连续或可用遮挡（前景经过、转身、开门）藏切点；
- 同框不超过 2 张正脸；
- 只有一个情绪转向（例如“压住 → 泄漏”，不能“悲 → 怒 → 笑”）；
- 总时长不超过当前模型上限。

换地点、换昼夜、换情绪段、换人物组合，一律切段。不要为了“省调用”把两场戏塞进一段。

## 四个闸门

**G2 先导片（必须，默认停一次；全自动模式按 QC 自动拍板）**：生成 1 段 8 秒左右的样片，选全片最难的组合——两个角色 + 有对白 + 有手部动作 + 目标光线。它同时验证脸、表演、口型、光影、模型能力。样片不过，后面全部重做只会更贵。

**G3 红镜头（必须，可打包确认）**：钩子、反转、情绪最高点、集末卡点逐段给用户看。可以一次打包给，不要逐镜打扰。

**G1 剧本与资产（条件）**：只有三种情况停下来问——要改主线、要加角色/场景导致成本跳级、题材有合规红线。其余按默认判断并在决策日志里说明。

**G4 终审（可选）**：用户说“直接出”就跳过，但质检报告必须照做。

## 断点续跑与预算

所有状态写进项目根目录 `state.json`，不要靠对话记忆。

- 每段记录：`segment_id`、提示词哈希、参考图版本、take 列表、选中 take、质检分、状态。
- 提示词和参考图没变且已通过的段，**永不重生成**。
- 默认每段最多 2 次，红镜头 3 次；超限停下来报告，不要无限抽卡。
- 预估调用次数 = 段数 × 1.5；先导片计入预算。
- 批量前给出“段数 / 预计调用 / 预计时长”，用户认可后一次跑完。

详细状态机、阶段契约和工具降级见 `references/orchestration.md`。

## 交付物

```
<项目目录>/
├── brief.md                 立项与规格
├── bible.md                 人物/场景/道具/时间线/视觉规则
├── script.md                可拍分场稿（含修改说明）
├── shotlist.csv             分镜表（校验脚本的唯一输入）
├── assets/                  角色图/场景板/道具图 + manifest
├── prompts/                 每段一份提示词
├── clips/                   生成素材，按段与 take 命名
├── audio/                   配音、环境、BGM、混音轨
├── qc/                      质检报告、接触表、失败清单
├── edit/edl.json            剪辑决策表
├── delivery/
│   ├── EP01_broadcast.mp4   上线版
│   ├── EP01_clean.mp4       纯对白版
│   ├── EP01.srt             字幕
│   ├── EP01_cover.jpg       封面
│   └── publish.md           标题/文案/标签/AI 标识
└── state.json               断点与预算
```

## 硬规则

1. **台词先定稿，再定镜头时长**。视频阶段写对白与语气：原生音频支持时直接生成；不支持时只要求自然口型，配音按 TTS 时长对齐，后期只做口型校正。
2. **角色长相不在提示词里复述**。只写“与参考图为同一人”，复述会加剧漂移。
3. **一段一个情绪转向，一镜一个主动作**。复杂动作拆段，不靠形容词硬堆。
4. **同框正脸不超过 2 人**。第三人用背影、过肩、前景虚化或单独反应镜。
5. **不用“8K 超高清”堆画质**。它会把皮肤推成塑料感；用“电影级、真实皮肤纹理、轻微胶片颗粒、自然景深”。
6. **不写导演名当风格词**。用可执行的色调、光比、焦段、颗粒描述，避免版权与模仿争议。
7. **竖屏优先中近景**。人脸放在画面上三分之一，底部 18% 留给字幕和平台 UI。
8. **每集必须有一个可截图的封面帧**。通常就是情绪最高点或反转瞬间。
9. **AI 生成内容必须标识**。显式角标 + 文件元数据，按 `references/platform-delivery.md` 执行。
10. **不伪造质检**。没看过的片段不能标“通过”；抽检也要写真看了哪几帧。
11. **不直接使用在世演员肖像或未授权音乐/字体**。参考图必须是用户提供或可商用的。
12. **合规风险主动报**。血腥、性暗示、未成年、赌博、医疗功效、迷信、炫富、复仇美化，一律先提示再改写。

## 工具缺失时的降级

| 缺什么 | 仍然交付 | 明确告知 |
|---|---|---|
| 视频生成工具 | 资产包 + 分镜 + 每段提示词 + EDL + 回填目录规范 | 哪些段还没生成 |
| 图像生成工具 | 角色文字设定 + 参考图拍摄/搜集清单 | 一致性风险 |
| TTS / 口型工具 | 带时间码的配音脚本 + SRT | 口型未对齐 |
| ffmpeg | EDL + 剪辑点清单 + 剪映操作步骤 | 未自动合成 |
| 全部都有 | 直接跑到成片 | 只报结果与质检 |

降级不是失败，**假装完成才是**。

## 脚本

Windows PowerShell 5.1+。`assemble` 与 `qc-sheet` 需要 ffmpeg/ffprobe 在 PATH 中；没有就先跑 `-DryRun` 出命令。

```powershell
# 1. 建项目
powershell -File scripts\new-project.ps1 -Title "祠堂" -Root "D:\drama" -Episode EP01 -TargetSeconds 90

# 2. 校验分镜（零 ERROR 才继续）
powershell -File scripts\validate-shotlist.ps1 -Path "D:\drama\drama-xxx\shotlist.csv" -TargetSeconds 90

# 3. 校验提示词（每段一份 md）
powershell -File scripts\lint-prompts.ps1 -Project "D:\drama\drama-xxx"

# 4. 先看拼接命令，再正式合成
powershell -File scripts\assemble.ps1 -Project "D:\drama\drama-xxx" -DryRun
powershell -File scripts\assemble.ps1 -Project "D:\drama\drama-xxx" -Mode both

# 5. 接触表与技术参数
powershell -File scripts\qc-sheet.ps1 -Project "D:\drama\drama-xxx" -Pairs D01:D02,D02:D03

# 6. 字幕
powershell -File scripts\make-srt.ps1 -Project "D:\drama\drama-xxx"
```

分镜字段口径以 `validate-shotlist.ps1` 为准；EDL 字段以 `assets/templates/edl.json` 为准。

## 参考文件路由

- 剧本结构、钩子、反转、90 秒模板、剧本评分：`references/story-craft.md`
- 分镜字段、焦段、机位、覆盖、可生成性评分：`references/shot-language.md`
- 表演、听戏、台词气口、去 AI 感：`references/performance-direction.md`
- 连续性与穿帮预审：`references/continuity-checklist.md`
- 提示词编译、参考图策略、负面词：`references/prompt-playbook.md`
- 文戏/打戏段模板与完整示例：`references/scene-block-template.md`
- 失败诊断与重抽：`references/retry-playbook.md`
- 题材视觉系统：`references/genre-visual.md`
- 角色/场景/道具资产：`references/asset-bible.md`
- 配音、口型、混音、字幕：`references/audio-post.md`
- 剪辑点、J/L-cut、转场、调色：`references/edit-craft.md`
- 质检评分卡与抽检方法：`references/qc-rubric.md`
- 平台规格、合规、AI 标识：`references/platform-delivery.md`
- 状态机、预算、断点、闸门策略：`references/orchestration.md`

模板在 `assets/templates/`，脚本在 `scripts/`。脚本是分镜与合成口径的唯一执行标准：文档与脚本冲突时，以脚本为准。
