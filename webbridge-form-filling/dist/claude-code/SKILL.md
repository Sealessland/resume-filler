---
name: webbridge-form-filling
version: 1.0.0
description: "通过 Kimi WebBridge 控制真实浏览器填写招聘/简历/网申表单（百度人才、OPPO 校招等）的实战经验与踩坑记录。当用户给出招聘系统简历页 URL 或要求『帮我填简历/填一下这个表单/拆分表单内容』时使用。覆盖：WebBridge 连接与升级、复用已打开标签、Element UI/Plus 表单定位、React 受控组件赋值、下拉/级联/日期选择器交互、长文本多栏拆分、填充后验证。基础工具用法见 kimi-webbridge skill，本 skill 只补充表单填写场景的套路。"
---

# WebBridge 填招聘表单实战经验

面向真实场景：用户在浏览器里打开了招聘系统简历页（`talent.baidu.com`、`careers.oppo.com` 等），要求帮填或拆分内容。以下每条均来自真实踩坑。

## 0. 先读 kimi-webbridge

基础操作（工具表、session 规则、截图 path 等）以 `kimi-webbridge` skill 为准。本 skill 只讲"填表单"的额外经验。

## 1. 连接与升级

- daemon 连不上（connection refused）：直接跑 `~/.kimi-webbridge/bin/kimi-webbridge start`，不要问用户。幂等安全。
- `no extension connected`：daemon 起来了但扩展没连上。等 3–8 秒重试几次；再不行请用户刷新页面或点扩展图标。
- 扩展提示版本不匹配 / Please update：跑 `~/.kimi-webbridge/bin/kimi-webbridge upgrade`（自动下载新版并重启 daemon），再等扩展重连。

## 2. 标签页：复用用户已打开的页面

- 用户说"就填我现在打开的这个页面"：用 `find_tab` + `active:true`，**不要** `navigate` 新开标签（用户会反感）。
- **URL 匹配要宽**：完整 URL 常带超长 query（`?shareId=...&recommendCode=...`），传完整 URL 会匹配不到。传域名即可，如 `{"url":"careers.oppo.com","active":true}`。
- **session 必须一致**：`find_tab` 请求体 top-level 必须带与后续 `snapshot`/`evaluate` 相同的 `session`。漏了 session，find_tab 成功但 snapshot 报 `session has no tab`。
- 匹配不到时先 `list_tabs` 看当前 session 有哪些标签，或让用户把目标页切到前台。

## 3. 快速摸清表单结构（不要死磕 snapshot）

`snapshot` 的 a11y tree 对长表单巨大且易截断。优先用 `evaluate` 直接抓结构：

```js
[...document.querySelectorAll('.el-form-item')].map((item, idx) => ({
  label: (item.querySelector('.el-form-item__label')?.textContent || '').trim(),
  required: item.classList.contains('is-required'),
  inputs: [...item.querySelectorAll('input,textarea')].map(el => ({
    tag: el.tagName, type: el.type || '', ph: el.placeholder || '',
    val: (el.value || '').toString().slice(0, 60),
  })),
}));
```

- Element UI / Element Plus（`.el-form-item`、`.el-input__inner`、`.el-select`）在招聘系统里几乎通用；找不到用 `[class*=form-item]` 兜底。
- 拿到结构后**给目标输入框打 `data-*` 标记**（`el.dataset.wb = 'proj1-0'`），之后用 `[data-wb="proj1-0"]` 精确操作，避免类名 hash 变化和同结构卡片（项目-1/项目-2）错位。
- **双份输入框陷阱**：React 表单常渲染可见 textarea + 隐藏镜像（值相同、`offsetParent===null`）。操作前用 `el.offsetParent!==null` 判断可见性，只改可见的那个。

## 4. React 受控组件赋值（fill 会失败的场景）

`fill` 在百度简历的 textarea 上会报 `fill: Uncaught`。改用原生 setter + 事件派发：

```js
const setVal = (el, v) => {
  const proto = el.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
  Object.getOwnPropertyDescriptor(proto, 'value').set.call(el, v);
  el.dispatchEvent(new Event('input',  { bubbles: true }));
  el.dispatchEvent(new Event('change', { bubbles: true }));
};
```

- input 短文本用 `fill` 基本没问题；textarea 长文本优先 setter 方案。
- 赋值后**必须 evaluate 回读验证**（`.value` 和 `.value.length`），确认 React 状态真正更新，别只看请求成功。

## 5. 下拉选择器（el-select）的正确打开方式

最大的坑。Element Plus 的 `el-select` 在合成事件下经常打不开：

- 合成 `click` 打不开 → 先用键盘事件：
  ```js
  inp.focus();
  inp.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowDown', code: 'ArrowDown', keyCode: 40, bubbles: true }));
  ```
- 还不行（自定义封装如 OPPO 的 `dic-select`、`mul-school`）：用 **CDP 真实鼠标**：
  ```json
  {"action":"cdp","args":{"method":"Input.dispatchMouseEvent","params":{"type":"mousePressed","x":507,"y":455,"button":"left","clickCount":1}}}
  {"action":"cdp","args":{"method":"Input.dispatchMouseEvent","params":{"type":"mouseReleased","x":507,"y":455,"button":"left","clickCount":1}}}
  ```
  坐标用 `evaluate` 取 `getBoundingClientRect()` 中心点，先 `scrollIntoView({block:'center'})` 再取，否则坐标过期。
- **多个下拉面板并存**：页面可能残留多个 `.el-select-dropdown`，只有一个可见。选选项前先定位可见面板：
  ```js
  const dd = [...document.querySelectorAll('.el-select-dropdown')]
    .find(p => getComputedStyle(p).display !== 'none' && p.offsetParent !== null);
  ```
  否则会点到别的下拉的选项（真实发生过：点国籍弹出证件类型、点到"学校就业网"）。
- 选中选项用 `mousedown` + `mouseup` + `click` 三连（仅 click 有时不触发）。
- **远程搜索型下拉**（如 OPPO 学校名称，readonly + `icon-search`）：点击后选项为空，需真实键盘输入触发搜索。合成 setter 无效 → CDP 点击聚焦后：
  ```json
  {"action":"cdp","args":{"method":"Input.insertText","params":{"text":"电子科技大学"}}}
  ```
  等 1–2 秒，从可见面板选联想项。
- 选完回读 input 的 `.value` 验证。

## 6. 日期选择器

- 点击后弹日历，但**不需要点日历格子**：直接在输入框 setter 填 `2000-01-01`(示例)再派发 keydown Enter 即可。
- 日期可从身份证号推（第 7–14 位）、从已有简历页抄、或问用户。

## 7. 长文本/多项目拆分

用户常要求"把所有信息都写到 XX 栏了，拆到合适栏目"（例：百度简历把两个项目+自我评价全塞进"项目职责"）。

- 先 `evaluate` 读出原文完整内容，按结构切块（项目名/职务/简介/职责明细）。
- 逐项目：名称、职务填 input；简介进"项目描述"（注意字数上限如 `0 / 2000`）；明细进"项目职责"。
- 多项目时找"+添加项目经验"按钮（`[class*=add-one]` 或文本含"添加项目"）先点出第二张卡片，再对新卡片打 `data-*` 标记后填充。
- 没有对应栏目（如"自我评价"在目标系统里不存在）时明确告诉用户放不下，不要硬塞。

## 8. 必填项与收尾

- 用 `.is-required` class 或 label 前缀 `*` 圈定必填范围，只问用户缺的关键信息（专业、院系、籍贯等）。
- 简历页通常有"保存"按钮；填完**不要擅自点保存/投递**，先汇报由用户确认。
- 全程用 `evaluate` 回读验证：字段值、长度、下拉回显、卡片数量。请求 `ok:true` 不代表 React 状态已更新。

## 9. 请求体构造建议

- 含中文/长文本的 evaluate 代码用 Python `json.dump` 写请求文件再 `curl --data-binary @file`，避免 shell 转义和中文损坏（Windows 必须）。
- 长响应会截断：重定向到文件后 `Read`，或让 evaluate 只返回摘要（长度/前 N 字符），不要回传整页。
