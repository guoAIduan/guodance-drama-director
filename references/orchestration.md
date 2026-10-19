# 编排、预算与断点续跑

“一键出片”不是一次模型调用，是一条**不会丢状态、不会重复烧钱、坏了能续跑**的生产线。

## 状态机

```
intake → script → bible → assets → shotlist → preflight
      → pilot → batch → audio → edit → qc → delivery
```

每个阶段只有五种状态：`pending / running / done / blocked / skipped`。

进入下一阶段的条件是上一阶段 `done`，不是“差不多”。

## state.json

放在项目根目录 `state.json`，所有断点以它为准：

```json
{
  "version": 1,
  "project": "EP01",
  "spec": {
    "aspect": "9:16",
    "width": 1080,
    "height": 1920,
    "fps": 30,
    "target_seconds": 90
  },
  "mode": {
    "delivery": ["broadcast", "clean"],
    "auto": true
  },
  "model": {
    "name": "Seedance",
    "max_segment_seconds": 8,
    "max_refs": 2,
    "first_last_frame": true,
    "native_audio": false
  },
  "stages": {
    "brief": {"status": "done", "artifact": "brief.md"},
    "script": {"status": "done", "artifact": "script.md"},
    "bible": {"status": "done", "artifact": "bible.md"},
    "assets": {"status": "done", "artifact": "assets/manifest.json"},
    "shotlist": {"status": "done", "artifact": "shotlist.csv"},
    "preflight": {"status": "done", "report": "qc/preflight.txt"},
    "pilot": {"status": "approved", "segment": "D01"},
    "batch": {"status": "running", "done": 6, "total": 13},
    "audio": {"status": "pending"},
    "edit": {"status": "pending"},
    "qc": {"status": "pending"},
    "delivery": {"status": "pending"}
  },
  "segments": {
    "D01": {
      "scene": "S01",
      "prompt_hash": "a1b2c3",
      "assets": ["CH_SY_v03", "SC_CT_v01"],
      "takes": [
        {"id": "take1", "file": "clips/D01_take1.mp4", "qc": 88, "status": "pass"}
      ],
      "selected": "take1",
      "status": "approved"
    }
  },
  "budget": {
    "max_takes": 2,
    "red_max_takes": 3,
    "calls_used": 7,
    "calls_cap": 26
  },
  "gates": {
    "G2": {"status": "approved", "note": "先导片脸/表演/口型达标"}
  },
  "decisions": [
    {"at": "2026-10-19T10:00:00+08:00", "decision": "单集 90 秒，9:16，都市悬疑", "reason": "用户未指定，按默认"}
  ]
}
```

## 阶段契约

| 阶段 | 输入 | 输出 | 完成标准 |
|---|---|---|---|
| intake | 用户剧本/大纲/一句话 | `brief.md` | 规格、受众、交付、预算写清 |
| script | brief + 原文 | `script.md` | 有体检分、P0/P1 清单、可拍分场稿 |
| bible | script | `bible.md` | 人物/场景/道具/时间线/视觉锁齐全 |
| assets | bible | `assets/` + `manifest.json` | 每个角色/场景有锁定参考图 |
| shotlist | script + bible | `shotlist.csv` | 字段完整，红镜头标注 |
| preflight | shotlist | `qc/preflight.txt` | 校验脚本零 ERROR |
| pilot | 提示词 + 资产 | 1 段样片 + QC | 脸/表演/口型/光四项达标 |
| batch | 全部提示词 | `clips/` + 状态 | 每段有 take 与结论 |
| audio | 台词 + 画面 | `audio/` | 对白、口型、混音达标 |
| edit | EDL + clips + audio | 时间线/成片 | 时长、节奏、字幕正确 |
| qc | 成片 | `qc/report.md` | 无 Critical，分数达标 |
| delivery | 成片 + 物料 | `delivery/` | 平台规格、标识、文案齐全 |

## 闸门策略

| 闸门 | `auto` 模式 | `ask` 模式 | 全自动 |
|---|---|---|---|
| G1 剧本 | 仅在改主线/加角色/合规红线时问 | 必问 | 不问，记录假设 |
| G2 先导片 | 必问（默认只停这一次） | 必问 | 按 QC 自动选最佳 |
| G3 红镜头 | 打包给用户看一次 | 逐段确认 | 自动通过，报告留档 |
| G4 终审 | 可跳过 | 必问 | 跳过 |

提问只问一个具体问题，带推荐选项：

```
先导片 D01 已出。脸 4.5/5、表演 4/5、口型 4/5，唯一问题是结尾手部略僵。
建议：按此风格批量，D01 重抽一次收尾。是否按此执行？
```

不要问“你觉得怎么样”。给判断、给建议、给代价。

## 预算

估算公式：

```
段数 ≈ 目标时长 / 8（向上取整）+ 2
调用数 ≈ 段数 × 1.5
时间 ≈ 调用数 × (1–4 分钟) + 质检时间
```

90 秒单集：约 13 段，约 20 次调用，40–90 分钟。

默认上限：

- 普通段 2 次；
- 红镜头 3 次；
- 先导片 2 次；
- 总调用不超过估算的 1.3 倍。

超限时停下来报告，不要“再试最后一次”无限循环。

## 断点续跑

每段记录三样：`prompt_hash`、`assets`、`model`。

- 三者都没变且 `status=approved`：跳过，不重生成。
- 提示词变了：旧 take 保留，但标记 `stale`，需重新 QC。
- 资产升版：受影响段全部标记 `stale`。
- 模型换版本：先导片重做，批量段标记待复核。

重跑命令只跑 `pending / stale / failed`，不要全量重来。

## 多集模式

一部短剧不要每集重建一套资产。用“系列层 + 单集层”：

```
series/
├── bible.md              全剧人物/场景/视觉锁
├── assets/               共享角色图、场景板、道具图
├── manifest.json
├── EP01/                 单集项目（brief/shotlist/clips/...）
├── EP02/
└── series-state.json     跨集一致性、造型变化、资产版本
```

规则：

- EP01 先做先导片，锁定脸、造型、光、镜头组；EP02 起直接复用。
- 角色换装/受伤/年龄变化，写进 `series-state.json` 的造型时间线，不覆盖旧图。
- 每集独立 `state.json`，系列层只存共享资产与跨集连续性。
- 新集开机前，先比对上一集尾帧与本集首帧的人物状态（服装/伤痕/发型）。
- 批量生产时，先做完 EP01 全流程并复盘抽卡率，再决定 EP02 的段长与重抽预算。

## 决策日志

自动模式下，每个假设写进 `decisions`：

- 为什么选这个题材基调；
- 为什么把某场拆成 3 段；
- 为什么删掉某句台词；
- 为什么某个红镜头降级。

用户不需要看全过程，但出问题时要能追溯。

## 工具能力矩阵

| 能力 | 有 | 没有时 |
|---|---|---|
| 视频生成 | 直接跑 | 交付提示词包 + 回填目录 |
| 图像生成 | 生成角色/场景板 | 输出设定文字 + 搜集清单 |
| TTS | 生成对白 | 输出带时间码的配音脚本 |
| 口型对齐 | 精确对齐 | 原生口型 + 标注风险 |
| ffmpeg | 自动合成/质检 | 输出 EDL + 剪映步骤 |
| 字幕 | 生成 SRT/硬字幕 | 输出纯文本台词 |
| 音乐 | 生成/授权曲库 | 输出音乐情绪点清单 |

缺工具时，先完成能完成的，再明确报告缺口。不要因为一个工具缺失就停整条线。

## 错误处理

| 类型 | 处理 |
|---|---|
| 工具报错/超时 | 重试 2 次，指数退避；仍失败走降级 |
| 生成失败（QC 不过） | 按 `retry-playbook.md` 诊断重抽 |
| 资产缺失 | 回 assets 阶段补，不能拿低清图凑 |
| 分镜矛盾 | 回 shotlist 改，不要带病生成 |
| 用户改需求 | 评估影响范围，标 stale，不要偷偷全重做 |
| 合规风险 | 立即停，说明风险与替代方案 |

## 一键执行顺序

用户说“直接出片”时，按这个顺序连续执行，不逐段请示：

1. 建项目目录，写 `brief.md`、`state.json`。
2. 剧本体检与生产化改写，写 `script.md`。
3. 写 `bible.md`，列资产清单。
4. 生成/整理角色、场景、道具参考图，写 `manifest.json`。
5. 先做角色试音与台词时长草稿，再写 `shotlist.csv`，跑校验，修到零 ERROR。
6. 编译每段提示词，写 `prompts/`。
7. 生成先导片，QC，向用户报一次（G2）。
8. 批量生成，逐段 QC/重抽，红镜头打包（G3）。
9. TTS、口型、环境、BGM、混音。
10. 按 EDL 拼接，出 `broadcast` 与 `clean`。
11. 全片 QC，修可修的，列不可修的。
12. 出封面、字幕、`publish.md`，终检。

中间不要停下来问“是否继续”。只有 G2/G3、合规红线、预算超限、需求变更才停。

## 最终报告

```
已完成：EP01，92 秒，9:16，1080×1920，30fps
交付：broadcast / clean / srt / cover / publish.md
质检：13 段通过 11，重抽后通过 2，无 Critical
声音：-14.2 LUFS，口型偏差 ≤2 帧
风险：D07 打斗接触改为声音+反应，剧情信息保留
工程：state.json 可续跑，D07 可单独重抽
```

报告只写结果、证据、风险、下一步。不要复述流程。

## 不要做的事

- 不要在状态没写入时开始下一阶段。
- 不要因为“反正能重抽”就跳过预审。
- 不要重生成已通过的段。
- 不要隐瞒失败段。
- 不要把“降级”说成“完成”。
- 不要在用户不知情时改剧情。
- 不要用对话记忆代替 `state.json`。
