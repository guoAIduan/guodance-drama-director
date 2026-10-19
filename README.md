# Guodance Drama Director

Guodance 是一套面向竖屏短剧的 AI 导演工作流：从剧本体检、角色与场景资产锁定、段级分镜，到 Seedance 提示词、生成质检、配音口型、剪辑调色和平台交付，一条链路跑完。

默认视频主引擎是 **Seedance**（2.5 或当前可用版本）；Guodance 负责导演方法、生产流程和质量控制。两者解耦，换成其他图生视频模型也能用。

## 它解决什么

- 剧本能拍：把文学描述改成可拍动作、可生成镜头。
- 角色不换脸：角色定脸、三视图、服装、场景板、道具全编号。
- 抽卡率更低：分镜阶段做 0–100 可生成性评分，低于 60 直接改写。
- 表演不假：目标—障碍—战术、听戏、微表情时间学、台词气口。
- 一键可续跑：`state.json` 记录每段提示词、take、质检分与预算。
- 出片能上线：双版本成片、字幕、封面、标题文案、AI 标识与平台规格。

## 目录

```
guodance-drama-director/
├── SKILL.md                 主入口与生产线
├── references/              14 个专业模块
├── assets/templates/        10 个项目模板
├── scripts/                 6 个 PowerShell 工具
└── agents/openai.yaml       UI 元数据
```

## 安装

把整个 `guodance-drama-director` 文件夹放到 Codex 的技能目录：

Windows:

```powershell
Copy-Item -Recurse .\guodance-drama-director "$env:USERPROFILE\.codex\skills\guodance-drama-director"
```

macOS / Linux:

```bash
cp -R guodance-drama-director ~/.codex/skills/
```

重新打开会话后，技能列表里会出现 **Guodance 短剧导演**。

## 使用

显式调用：

```text
$guodance-drama-director
```

自然语言触发：

```text
用 Guodance 把这份剧本做成一集 90 秒竖屏短剧，先出先导片，确认后批量。
```

## 环境

- Windows PowerShell 5.1+（脚本）
- ffmpeg / ffprobe（拼接、接触表、响度；没有也能出提示词包）
- 一个图生视频模型（默认 Seedance）
- 图像生成与 TTS（可选；没有会交付可回填的资产包与配音脚本）

## 快速开始

```powershell
# 1. 建项目
powershell -File scripts\new-project.ps1 -Title "祠堂" -Root "D:\drama" -Episode EP01 -TargetSeconds 90

# 2. 校验分镜
powershell -File scripts\validate-shotlist.ps1 -Path "D:\drama\drama-xxx\shotlist.csv" -TargetSeconds 90

# 3. 校验提示词
powershell -File scripts\lint-prompts.ps1 -Project "D:\drama\drama-xxx"

# 4. 合成（先 dry-run 看命令）
powershell -File scripts\assemble.ps1 -Project "D:\drama\drama-xxx" -DryRun

# 5. 接触表 / 技术参数
powershell -File scripts\qc-sheet.ps1 -Project "D:\drama\drama-xxx" -Pairs D01:D02

# 6. 字幕
powershell -File scripts\make-srt.ps1 -Project "D:\drama\drama-xxx"
```

## 工作流

```
剧本体检 → 视觉圣经 → 资产锁定 → 段级分镜 → 预审
→ 先导片 → 批量生成 → 配音口型 → 剪辑调色 → 质检交付
```

只有四个闸门：剧本/资产（条件）、先导片（默认停一次）、红镜头（可打包确认）、终审（可选）。说“全自动”则按 QC 自动拍板。

## 说明

- `Guodance` 是导演工作流品牌名，`Seedance` 是默认视频生成引擎，不混用。
- 一键出片仍需要视频模型、TTS 与 ffmpeg；缺工具时交付可直接投喂的生成包，不假装成片已完成。
- 仓库暂未声明开源许可证。添加 `LICENSE` 前，默认保留所有权利；如需 MIT / Apache-2.0，请仓库所有者补充。
