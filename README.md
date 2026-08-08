# resume-filler

把真实招聘、简历、网申页面的填表经验沉淀成 `webbridge-form-filling` skill，并分发到多个 AI agent 工具。

这个仓库不是通用表单自动化框架，而是一份可复用的实战规程：复用用户已登录浏览器，读取可靠简历来源，小批量填入字段，逐项回读验证，并在保存/提交前停下。

## 适用场景

- 用 Kimi WebBridge 驱动用户真实浏览器填写招聘系统、简历中心、网申表单。
- 处理 Element UI / Element Plus、React/Vue 受控输入、远程搜索下拉、级联、日期选择器。
- 把简历长文本拆到项目描述、项目职责、技能、个人总结等对应栏目。
- 在百度人才、OPPO 校招等页面中复用已验证过的定位、填入和验证策略。

## 安装

```bash
# 安装到当前机器上已存在的全部 agent 目录
bash webbridge-form-filling/install.sh

# 只安装到指定 agent
bash webbridge-form-filling/install.sh --agent omp
bash webbridge-form-filling/install.sh --agent codex

# 预演，不写入文件
bash webbridge-form-filling/install.sh --agent codex --dry-run
```

支持的 agent 名称：`claude-code`、`codex`、`omp`、`opencode`、`kimi-code`。

也可以手动复制对应分发目录：

| Agent | 分发版 | 目标目录 |
|---|---|---|
| Claude Code | `webbridge-form-filling/dist/claude-code/` | `~/.claude/skills/` |
| Codex | `webbridge-form-filling/dist/codex/` | `~/.codex/skills/` |
| OMP | `webbridge-form-filling/dist/omp/` | `~/.omp/agent/skills/` |
| opencode | `webbridge-form-filling/dist/opencode/` | `~/.opencode/skills/` |
| kimi-code | `webbridge-form-filling/dist/kimi-code/` | `~/.kimi-code/skills/` |

## 使用边界

- 先读 `kimi-webbridge`，再读 `webbridge-form-filling`；两者配套使用。
- 用户说“填简历”“填表单”“网申”“把当前网页补全”等，默认复用当前浏览器标签页。
- 信息源只来自用户提供的简历、JSON、页面已有值或明确指示；不编造公司、岗位、院系、籍贯、证件号、日期等事实。
- 填入必须走真实可见控件和事件链；不要直接篡改 Vue/React 内部 props/model 当作完成。
- 每个区块填完都要回读验证字段值、长度、下拉回显和卡片数量。
- 除非用户明确授权，不点击保存、下一步、提交、投递。

## Skill 要点

1. **连接与标签页**：daemon 不通时启动；扩展未连接时短重试；优先复用已打开标签和同一 session。
2. **表单扫描**：用 DOM / `evaluate` 建立 label → input 映射，给目标控件打 `data-*` 标记；动态卡片展开后重新打标。
3. **受控输入**：`fill` 失败时用原生 setter + `input/change/blur` 事件；可见值变化不等于框架状态已更新。
4. **下拉选择**：按键盘、真实鼠标、可见 dropdown 面板逐级升级；远程搜索下拉用真实输入触发候选。
5. **日期字段**：优先使用已有来源；按控件格式直接输入并确认，不为缺失月份或项目日期编造值。
6. **多项目卡片**：先切分原文，再按卡片局部输入填；新增卡片后重新扫描，避免项目错位。
7. **OPPO 专项**：短路径恢复页面、按模块标题找编辑按钮、先打开“有”再填项目、学校远程搜索精确选择。

## 仓库结构

```text
resume-filler/
├── README.md
└── webbridge-form-filling/
    ├── SKILL.md              # 规范版，唯一正文来源
    ├── agents/openai.yaml    # Codex UI 元数据来源
    ├── install.sh            # 安装全部或指定 agent
    ├── scripts/
    │   └── sync_dist.py      # 确定性生成 / 检查分发版
    ├── tests/
    │   └── install_test.sh   # 安装器烟测
    └── dist/                 # 各 agent 分发版，仅 frontmatter 不同
        ├── claude-code/SKILL.md
        ├── codex/SKILL.md
        ├── kimi-code/SKILL.md
        ├── omp/SKILL.md
        └── opencode/SKILL.md
```

## 维护流程

只编辑规范版：

```bash
$EDITOR webbridge-form-filling/SKILL.md
python3 webbridge-form-filling/scripts/sync_dist.py
```

提交前运行与 CI 相同的检查：

```bash
python3 webbridge-form-filling/scripts/sync_dist.py --check
bash -n webbridge-form-filling/install.sh webbridge-form-filling/tests/install_test.sh
bash webbridge-form-filling/tests/install_test.sh
```

不要手改 `dist/`。分发版正文必须与 `SKILL.md` 一致，只允许 frontmatter 适配不同 agent。
