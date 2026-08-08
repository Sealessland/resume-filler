---
name: webbridge-form-filling
description: |
  通过 Kimi WebBridge 控制真实浏览器填写招聘/简历/网申表单(百度人才、OPPO 校招、各厂招聘系统等)的实战经验与踩坑记录。当用户给出招聘系统简历页 URL 或要求"帮我填简历/填一下这个表单"时使用。覆盖:WebBridge 连接与升级、复用已打开标签、Element UI/Plus 表单字段定位、React 受控组件赋值、下拉/级联/日期选择器的交互、长文本拆分到多栏、填充后的验证。与 kimi-webbridge skill 配合使用——本 skill 只补充表单填写场景特有的套路,基础工具用法见 kimi-webbridge。
metadata:
  version: "1.0.0"
---

# WebBridge 填招聘表单实战经验

面向真实场景:用户在浏览器里打开了招聘系统简历页(如 `talent.baidu.com`、`careers.oppo.com`),要求帮填或拆分内容。以下每一条都来自真实踩坑。

## 0. 先读 kimi-webbridge

基础操作(工具表、session 规则、截图、screenshot path 等)全部以 `kimi-webbridge` skill 为准。本 skill 只讲"填表单"这一件事上的额外经验,不重复基础内容。

## 1. 连接与升级

- daemon 连不上(exit code 7 / connection refused):直接跑 `~/.kimi-webbridge/bin/kimi-webbridge start`,不要问用户。安全,幂等。
- `no extension connected`:daemon 起来了但浏览器扩展没连上。等 3–8 秒重试几次;再不行请用户刷新页面或点扩展图标。不要反复空转。
- 扩展提示 **Please update Kimi WebBridge** 或版本不匹配:跑 `~/.kimi-webbridge/bin/kimi-webbridge upgrade`(会下载新版并自动重启 daemon),然后等扩展重连。不要自己手动对版本。

## 2. 标签页:复用用户已打开的页面

- 用户说"就填我现在打开的这个页面"时,用 `find_tab` + `active:true`,不要 `navigate` 新开标签(用户会明确反感新开)。
- **URL 匹配要宽**:完整 URL 可能带超长 query 参数(`?shareId=...&recommendCode=...`),用 `find_tab` 传完整 URL 常常匹配不到。传域名即可,如 `{"url":"careers.oppo.com","active":true}`。
- **session 必须一致**:`find_tab` 的请求体里 top-level 必须带和后续 `snapshot`/`evaluate` 相同的 `session` 字段。漏了 session,find_tab 成功但 snapshot 报 `session has no tab`。
- 页面匹配不到时,先 `list_tabs`(只列当前 session 的)或让用户把目标页切到前台再试。

## 3. 快速摸清表单结构(不要死磕 snapshot)

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

## 4. React 受控组件赋值(fill 会失败的场景)

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

## 5. 下拉选择器(el-select)的正确打开方式

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

## 6. 日期选择器

- 点击后弹出日历面板,但**不需要点日历格子**:直接在输入框 setter 填 `2000-01-01`(示例)再派发 keydown Enter 即可,Element 会接受。
- 日期可以从身份证号推(第 7–14 位),从已有简历页抄,或问用户。

## 7. 长文本/多项目拆分

用户常要求"把所有信息都写到 XX 栏了,拆到合适栏目"(例:百度简历把两个项目+自我评价全塞进"项目职责")。

- 先 `evaluate` 读出原文完整内容,按结构切块(项目名/职务/简介/职责明细)。
- 逐项目:名称、职务填 input;简介进"项目描述"(注意字数上限,如 `0 / 2000`);明细进"项目职责"。
- 需要多个项目时,找"+添加项目经验"按钮(`[class*=add-one]` 或文本含"添加项目")先点出第二张卡片,再对新卡片打 `data-*` 标记后填充。
- 没有对应栏目(如"自我评价"在目标系统里不存在)时,明确告诉用户放不下,不要硬塞。

## 8. 必填项与收尾

- 用 `.is-required` class 或 label 前缀 `*` 圈定必填范围,只问用户缺的关键信息(专业、院系、籍贯等),别让用户补 30 个空。
- 简历页通常有"保存"按钮;填完**不要擅自点保存/投递**——先汇报,由用户确认。
- 全程用 `evaluate` 回读验证:字段值、长度、下拉回显、卡片数量。请求返回 `ok:true` 不代表 React 状态已更新。

## 9. 请求体构造建议

- 含中文/长文本的 evaluate 代码用 Python `json.dump` 写请求文件再 `curl --data-binary @file`,避免 shell 转义和中文损坏(Windows 上更是必须)。
- 长响应(>几千字节)会截断:重定向到文件后 `Read`,或让 evaluate 只返回 `JSON.stringify` 的摘要(长度/前 N 字符),不要回传整页。
