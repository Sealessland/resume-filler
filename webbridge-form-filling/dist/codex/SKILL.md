---
name: webbridge-form-filling
description: |
  Fill job-application, resume, and online-form pages through Kimi WebBridge in the user's real browser. Use when the user provides a recruiting-system URL or asks to “填简历”, “填表单”, complete an application, repair misplaced content, or split long resume text across fields. Covers open-tab reuse, form mapping, React controlled inputs, Element UI/Plus selects and date pickers, safe write boundaries, and post-fill verification. Use together with kimi-webbridge; this skill adds form-filling procedures rather than general browser-control instructions.
---

# WebBridge 填招聘表单实战经验

用 Kimi WebBridge 在用户已打开的招聘系统中完成可验证、可停止的表单填写。把“填入”和“提交”视为两个独立阶段。

## 执行流程

1. 读取 `kimi-webbridge` skill，复用用户当前标签页和同一 `session`。
2. 只读扫描表单，记录已有值、必填项、字数限制和重复卡片结构。
3. 建立“来源内容 → 目标字段”映射；不猜测关键事实，只询问阻塞填写的缺失信息。
4. 按区块小批量填入，每批立即回读；失败时再按本 skill 的交互阶梯升级。
5. 汇报已修改字段、未解决项和验证结果。除非用户明确授权，不点击保存、下一步、提交或投递。

## 1. 先读 kimi-webbridge

基础操作(工具表、session 规则、截图、screenshot path 等)全部以 `kimi-webbridge` skill 为准。本 skill 只讲"填表单"这一件事上的额外经验,不重复基础内容。

## 2. 连接与升级

- daemon 连不上(exit code 7 / connection refused):直接跑 `~/.kimi-webbridge/bin/kimi-webbridge start`,不要问用户。安全,幂等。
- `no extension connected`:daemon 起来了但浏览器扩展没连上。等 3–8 秒重试几次;再不行请用户刷新页面或点扩展图标。不要反复空转。
- 扩展提示 **Please update Kimi WebBridge** 或版本不匹配:跑 `~/.kimi-webbridge/bin/kimi-webbridge upgrade`(会下载新版并自动重启 daemon),然后等扩展重连。不要自己手动对版本。

## 3. 标签页：复用用户已打开的页面

- 用户说"就填我现在打开的这个页面"时,用 `find_tab` + `active:true`,不要 `navigate` 新开标签(用户会明确反感新开)。
- **URL 匹配要宽**:完整 URL 可能带超长 query 参数(`?shareId=...&recommendCode=...`),用 `find_tab` 传完整 URL 常常匹配不到。传域名即可,如 `{"url":"careers.oppo.com","active":true}`。
- **session 必须一致**:`find_tab` 的请求体里 top-level 必须带和后续 `snapshot`/`evaluate` 相同的 `session` 字段。漏了 session,find_tab 成功但 snapshot 报 `session has no tab`。
- 页面匹配不到时,先 `list_tabs`(只列当前 session 的)或让用户把目标页切到前台再试。

## 4. 快速摸清表单结构

`snapshot` 返回的 a11y tree 对长表单巨大且易截断。优先用 `evaluate` 直接抓结构:

```js
// 1) 列出所有输入框及占位/值(按 el-form-item 聚合,Element UI 通用)
[...document.querySelectorAll('.el-form-item')].map((item, idx) => ({
  label: (item.querySelector('.el-form-item__label')?.textContent || '').trim(),
  required: item.classList.contains('is-required'),
  inputs: [...item.querySelectorAll('input,textarea')].map(el => ({
    tag: el.tagName, type: el.type || '', ph: el.placeholder || '',
    val: (el.value || '').toString().slice(0, 60),
  })),
}));
```

- Element UI / Element Plus(`.el-form-item`, `.el-input__inner`, `.el-select`)在百度、OPPO 等招聘系统里几乎通用;找不到就用 `[class*=form-item]` 或 `[class*=field]` 兜底。
- 拿到结构后**给目标输入框打 `data-*` 标记**(如 `el.dataset.wb = 'proj1-0'`),之后用 `[data-wb="proj1-0"]` 精确操作,避免类名 hash 变化和同结构重复元素(项目-1/项目-2 卡片)错位。
- 注意同值"双份"输入框陷阱:React 表单常渲染一个可见 textarea + 一个隐藏镜像(值相同、`offsetParent===null`)。操作前用 `el.offsetParent!==null` 判断可见性,只改可见的那个。
- **动态表单后要重新打标**：点击“有”、`+添加`、展开编辑态或切换 tab 后，旧的 `data-*` 可能指向已卸载/重复节点。先清掉目标区旧标记，再按当前可见 DOM 重新编号；不要复用上一轮扫描的 ref。
- 只把前端框架状态当作侦查线索。Vue/React 组件里的 `props.data`、`setupState` 可以帮助确认字段名，但不要直接 `Object.assign` / `splice` 内部 model 来“填表”；真实页面可能不刷新、不校验，甚至污染重复卡片。最终写入必须经过可见 input/textarea、下拉或按钮事件。

## 5. React 受控组件赋值

`fill` 工具在百度简历的 textarea 上会报 `fill: Uncaught`。改用原生 setter + 事件派发,一劳永逸:

```js
const setVal = (el, v) => {
  const proto = el.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
  Object.getOwnPropertyDescriptor(proto, 'value').set.call(el, v);
  el.dispatchEvent(new Event('input',  { bubbles: true }));
  el.dispatchEvent(new Event('change', { bubbles: true }));
};
```

- input 用 `fill` 基本没问题(名称/职务等短文本直接 `fill` 即可);textarea 长文本优先 setter 方案。
- 赋值后**必须 evaluate 回读验证**(`.value` 和 `.value.length`),确认 React 状态真正更新,别只看请求成功。
- 如果 setter 改完 DOM 显示值但校验仍报空，说明框架 state 没吃到事件；补发 `blur`、`keydown Enter`，或退回到组件的真实交互路径（下拉选择、日期选择器确认、按钮添加）。不要把“可见值变了”当作已通过校验。

## 6. 下拉选择器（el-select）

这是最大的坑。Element Plus 的 `el-select` 在合成事件下经常打不开:

- 常见 `click`(DOM 合成点击)打不开 → 先用键盘事件:
  ```js
  inp.focus();
  inp.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowDown', code: 'ArrowDown', keyCode: 40, bubbles: true }));
  ```
- 还不行(自定义封装组件如 OPPO 的 `dic-select`、`mul-school`):用 **CDP 真实鼠标**:
  ```json
  {"action":"cdp","args":{"method":"Input.dispatchMouseEvent","params":{"type":"mousePressed","x":507,"y":455,"button":"left","clickCount":1}}}
  {"action":"cdp","args":{"method":"Input.dispatchMouseEvent","params":{"type":"mouseReleased","x":507,"y":455,"button":"left","clickCount":1}}}
  ```
  坐标用 `evaluate` 取 `getBoundingClientRect()` 的中心点,滚动到可视区(`scrollIntoView({block:'center'})`)后再取,否则坐标是旧的。
- **多个下拉面板并存**:页面可能残留多个 `.el-select-dropdown`,只有一个是可见的。选选项前先定位可见面板:
  ```js
  const dd = [...document.querySelectorAll('.el-select-dropdown')]
    .find(p => getComputedStyle(p).display !== 'none' && p.offsetParent !== null);
  ```
  否则会点到别的下拉的选项(真实发生过:点国籍弹出证件类型选项、点到"学校就业网")。
- 选中选项用 `mousedown` + `mouseup` + `click` 三连(仅 click 有时不触发)。
- **远程搜索型下拉**(如 OPPO 学校名称,readonly + `icon-search`):点击后选项为空,需要真实键盘输入触发搜索。合成 setter 输入无效 → CDP 点击聚焦后:
  ```json
  {"action":"cdp","args":{"method":"Input.insertText","params":{"text":"电子科技大学"}}}
  ```
  等 1–2 秒,再从可见面板里选联想项。
- 选完回读 input 的 `.value` 验证。
- 同源接口/前端 bundle 可以用来查字典 code、学校 code、字段顺序，但只能作为定位依据；保存前仍要让目标控件自己产生最终值。对 OPPO 这类表单，直接写显示文本可作为临时可见提示，不能替代下拉/级联的真实选择。

## 7. OPPO / Element Plus 简历页专项

- OPPO 校招简历页常见路径是 `/university/oppo/center/resume`。带内推/岗位的超长 query 可能导致 WebBridge 绑定或刷新不稳定；若页面变成 `chrome-error://chromewebdata/` 且主机可达，优先导航短路径恢复登录态，不要新开无关标签。
- 页面只读态每个模块右上角有 `.module-title__edit` 铅笔。先用最近的 `.van-tab__panel.resume-item` 标题定位模块，再点对应编辑按钮；不要按全页第 N 个铅笔硬点，空模块的父级标题会被大容器文本污染。
- “项目经历”“工作/实习经历”等模块可能先显示“没有 / 有”。要填内容先点“有”，等编辑表单出现后再扫描；不要在未展开时写隐藏/不存在的字段。
- OPPO 项目卡片用 `form.el-form` 重复。每张卡的可见文本输入通常是 `[项目名称, 开始时间, 结束时间, 项目角色]`，textarea 是“项目职责”。新增卡片后重新扫描当前 `form.el-form` 列表，按卡片局部输入填，避免把第 2 个项目写进第 1 张。
- OPPO 学校名称是远程搜索组件。输入学校关键词后从可见候选里选精确学校；“电子科技大学”要避开“杭州电子科技大学”“桂林电子科技大学”等前缀命中。选完回读完整回显和后续学历/地区字段。
- OPPO 教育字段常要求学校、院系、学校所在地、学历、起止时间、受教育类型、是否交流、是否联合办学、专业类别、专业、成绩排名。JSON 没给的院系、籍贯、项目日期等不要编；写完汇报为空的必填项。

## 8. 日期选择器

- 点击后弹出日历面板,但**不需要点日历格子**:直接在输入框 setter 填 `2000-01-01` 或 `2023-09`(按控件格式)再派发 `keydown Enter` / `blur`，Element 通常会接受。
- 优先从用户提供的简历或已有表单中取值。只有在用户已提供身份证号且当前任务需要时，才可推导出生日期；不要在日志或汇报中重述证件号。

## 9. 长文本与多项目拆分

用户常要求"把所有信息都写到 XX 栏了,拆到合适栏目"(例:百度简历把两个项目+自我评价全塞进"项目职责")。

- 先 `evaluate` 读出原文完整内容,按结构切块(项目名/职务/简介/职责明细)。
- 逐项目:名称、职务填 input;简介进"项目描述"(注意字数上限,如 `0 / 2000`);明细进"项目职责"。
- 需要多个项目时,找"+添加项目经验"按钮(`[class*=add-one]` 或文本含"添加项目")先点出第二张卡片,再对新卡片打 `data-*` 标记后填充。
- 没有对应栏目(如"自我评价"在目标系统里不存在)时,明确告诉用户放不下,不要硬塞。

## 10. 必填项与收尾

- 用 `.is-required` class 或 label 前缀 `*` 圈定必填范围,只问用户缺的关键信息(专业、院系、籍贯等),别让用户补 30 个空。
- 修改非空字段前先保留原值摘要，以便发现映射错误时恢复。
- 填完后**不要擅自点保存、下一步、提交或投递**；先汇报并等待用户确认。
- 全程用 `evaluate` 回读验证:字段值、长度、下拉回显、卡片数量。请求返回 `ok:true` 不代表 React 状态已更新。

## 11. 请求体构造

- 含中文/长文本的 evaluate 代码用 Python `json.dump` 写请求文件再 `curl --data-binary @file`,避免 shell 转义和中文损坏(Windows 上更是必须)。
- 长响应(>几千字节)会截断:重定向到文件后 `Read`,或让 evaluate 只返回 `JSON.stringify` 的摘要(长度/前 N 字符),不要回传整页。
