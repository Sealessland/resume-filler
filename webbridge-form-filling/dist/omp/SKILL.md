---
name: webbridge-form-filling
description: |
  Fill job-application / resume / online-form pages (Baidu Talent, OPPO campus, etc.) through Kimi WebBridge driving the user's real browser. Use when the user gives a recruiting-system resume URL or asks to fill / restructure a form. Covers daemon connect & upgrade, reusing an open tab, Element UI/Plus field mapping, React controlled-component value setting, select/cascade/date-picker interaction, splitting long text into fields, and post-fill verification. Base tool usage lives in the kimi-webbridge skill; this one adds only form-filling specifics.
---

# WebBridge Form Filling

Real-world experience filling recruiting-system resume pages (`talent.baidu.com`, `careers.oppo.com`, …) via Kimi WebBridge. Every item below comes from actual failures.

## 0. Read kimi-webbridge first

Base tool table, session rules, screenshot paths → `kimi-webbridge`. This skill only adds form-filling specifics.

## 1. Connect & upgrade

- Daemon unreachable (connection refused): run `~/.kimi-webbridge/bin/kimi-webbridge start`. Idempotent and safe; don't ask the user.
- `no extension connected`: daemon up, extension not. Retry after 3–8 s a few times, then ask the user to refresh / click the extension icon.
- Version mismatch / "Please update": run `~/.kimi-webbridge/bin/kimi-webbridge upgrade`, then wait for re-connect.

## 2. Tabs: reuse the user's open page

- "Fill the page I have open" → `find_tab` with `active:true`. Do NOT `navigate` a new tab; users dislike it.
- **Match the URL loosely**: full URLs carry huge query strings and full-URL matching fails. Match the domain: `{"url":"careers.oppo.com","active":true}`.
- **Keep the session identical**: `find_tab` must carry the same top-level `session` as later `snapshot`/`evaluate`. Missing session → find_tab succeeds but snapshot errors `session has no tab`.
- No match → `list_tabs` or ask the user to foreground the tab.

## 3. Map the form quickly (don't fight snapshot)

`snapshot` a11y trees are huge and truncated for long forms. Use `evaluate`:

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

- Element UI / Plus (`.el-form-item`, `.el-input__inner`, `.el-select`) is near-universal in recruiting systems; fall back to `[class*=form-item]`.
- **Tag target inputs with `data-*`** (`el.dataset.wb = 'proj1-0'`) and operate via `[data-wb="proj1-0"]` to survive hashed classnames and duplicate cards.
- **Duplicate-input trap**: React forms render a visible textarea plus a hidden mirror (same value, `offsetParent===null`). Filter by `el.offsetParent!==null`; touch only the visible one.

## 4. React controlled components (when `fill` fails)

`fill` errors `fill: Uncaught` on Baidu resume textareas. Use the native setter + events:

```js
const setVal = (el, v) => {
  const proto = el.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
  Object.getOwnPropertyDescriptor(proto, 'value').set.call(el, v);
  el.dispatchEvent(new Event('input',  { bubbles: true }));
  el.dispatchEvent(new Event('change', { bubbles: true }));
};
```

- Short text inputs: `fill` usually works. Long textareas: prefer the setter.
- **Always verify by re-reading** via `evaluate` (`.value`, `.value.length`). `success:true` does not mean React state updated.

## 5. Opening el-select dropdowns (biggest pitfall)

Element Plus `el-select` often ignores synthetic events:

- Synthetic `click` won't open → keyboard first:
  ```js
  inp.focus();
  inp.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowDown', code: 'ArrowDown', keyCode: 40, bubbles: true }));
  ```
- Still stuck (wrapped components like OPPO `dic-select`, `mul-school`): **CDP real mouse**:
  ```json
  {"action":"cdp","args":{"method":"Input.dispatchMouseEvent","params":{"type":"mousePressed","x":507,"y":455,"button":"left","clickCount":1}}}
  {"action":"cdp","args":{"method":"Input.dispatchMouseEvent","params":{"type":"mouseReleased","x":507,"y":455,"button":"left","clickCount":1}}}
  ```
  Coordinates from `getBoundingClientRect()` center after `scrollIntoView({block:'center'})` — stale coords break it.
- **Multiple dropdown panels coexist**: several `.el-select-dropdown` linger, only one visible. Find the visible one before picking:
  ```js
  const dd = [...document.querySelectorAll('.el-select-dropdown')]
    .find(p => getComputedStyle(p).display !== 'none' && p.offsetParent !== null);
  ```
  Otherwise you click options of the wrong dropdown (real incidents: clicking nationality showed ID-type options; picked "学校就业网" instead of "校园大使推荐").
- Select with `mousedown` + `mouseup` + `click` (click alone sometimes doesn't fire).
- **Remote-search dropdowns** (OPPO school name: readonly + `icon-search`): opens with zero options; needs real keyboard input. Synthetic setter is ignored → CDP click to focus, then:
  ```json
  {"action":"cdp","args":{"method":"Input.insertText","params":{"text":"电子科技大学"}}}
  ```
  Wait 1–2 s, pick from the visible panel.
- Re-read the input's `.value` after picking.

## 6. Date pickers

- Clicking opens a calendar, but **you don't need the calendar grid**: set `2000-01-01` (example) on the input via setter then dispatch keydown Enter. Element accepts it.
- Derive dates from the ID card (digits 7–14), copy from an existing resume page, or ask.

## 7. Splitting long text / multiple projects

Users often say "everything went into field X, split it into the right fields" (e.g. Baidu: two projects + self-evaluation crammed into 项目职责).

- `evaluate` the full original text, slice by structure (project name / role / intro / duties).
- Per project: name & role → inputs; intro → "项目描述" (mind the cap, e.g. `0 / 2000`); details → "项目职责".
- Multiple projects: click "+添加项目经验" (`[class*=add-one]` or text containing 添加项目) to spawn card N+1, tag with `data-*`, then fill.
- No matching section in the target system (e.g. no 自我评价 section) → say so plainly; don't force it.

## 8. Required fields & wrap-up

- Find required fields via `.is-required` class or `*` label prefix. Only ask for genuinely missing key info (major, department, hometown, …).
- Resume pages usually have a 保存 button; **do not click save/submit on your own** — report and let the user confirm.
- Verify throughout with `evaluate`: values, lengths, dropdown echoes, card counts.

## 9. Request body construction

- For Chinese/long evaluate code, write the JSON body with Python `json.dump` and send via `curl --data-binary @file` to dodge shell escaping and CJK corruption.
- Long responses truncate: redirect to a file then `Read`, or have evaluate return a digest (length / first N chars).
