# resume-filler

通过 **Kimi WebBridge** 控制真实浏览器填写招聘/简历/网申表单（百度人才、OPPO 校招等）的实战经验与踩坑记录，封装为可复用 skill，分发到多个 AI agent 工具。

> 每条经验均来自真实踩坑，覆盖：WebBridge 连接与升级、复用已打开标签、Element UI/Plus 表单定位、React 受控组件赋值、下拉/级联/日期选择器交互、长文本多栏拆分、填充后验证。

## 快速开始

```bash
# 安装到当前机器上的所有 agent（claude-code / codex / omp / opencode / kimi-code）
bash webbridge-form-filling/install.sh
```

也可以手动把对应目录复制到各 agent 的 skills 目录：

| Agent | 分发版 | 目标目录 |
|---|---|---|
| Claude Code | `dist/claude-code/` | `~/.claude/skills/` |
| Codex | `dist/codex/` | `~/.codex/skills/` |
| OMP | `dist/omp/` | `~/.omp/agent/skills/` |
| opencode | `dist/opencode/` | `~/.opencode/skills/` |
| kimi-code | `dist/kimi-code/` | `~/.kimi-code/skills/` |

## 仓库结构

```
resume-filler/
├── README.md
└── webbridge-form-filling/
    ├── SKILL.md          # 规范版（源码，kimi-code 格式）
    ├── install.sh        # 一键分发到全部 5 个 agent
    └── dist/             # 各 agent 的分发版（frontmatter 遵循各自格式）
        ├── claude-code/SKILL.md
        ├── codex/SKILL.md
        ├── omp/SKILL.md
        ├── opencode/SKILL.md
        └── kimi-code/SKILL.md
```

## skill 要点速览

1. **连接与升级** — daemon 掉了自己 `start`；版本不匹配跑 `kimi-webbridge upgrade`
2. **复用已打开标签** — `find_tab + active:true`，URL 匹配用域名（不带超长 query）；`session` 全程一致
3. **摸清表单结构** — 用 `evaluate` 抓 `.el-form-item` label→输入框映射，别死磕 snapshot；给输入框打 `data-*` 标记；警惕可见 textarea + 隐藏镜像
4. **React 受控组件** — textarea 的 `fill` 会报 `Uncaught`，改用原生 setter + input/change 事件
5. **下拉选择器** — 合成 click 打不开；依次试键盘 ArrowDown → CDP 真实鼠标；多面板并存时定位可见的那个；远程搜索型下拉用 CDP `insertText`
6. **日期选择器** — 直接填值 + Enter，不用点日历格子
7. **多项目拆分** — 先读原文切块，逐卡片填；无对应栏目时明确告知
8. **必填与收尾** — 只问关键缺失信息；不擅自点保存/投递
9. **请求体构造** — 中文长文本用 Python 写 JSON + `curl --data-binary @file`

## 维护

- 修改经验请先改根目录 `SKILL.md`（规范版），再同步到 `dist/*/SKILL.md`（注意各 agent 的 frontmatter 格式差异）。
- 分发版格式差异：Claude Code 含 `version` + 中文双引号 description；Codex 极简 name+description；OMP 用 `description: |` 块状；opencode 单行双引号 description；kimi-code 含 `metadata.version`。
