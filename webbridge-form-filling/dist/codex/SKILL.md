---
name: webbridge-form-filling
description: |
  Fill job-application / resume / online-form pages (Baidu Talent, OPPO campus, etc.) through Kimi WebBridge by driving the user's real browser. Use when the user gives a recruiting-system resume URL or asks to fill a form / split form content. Covers: daemon connect & upgrade, reusing an open tab, Element UI/Plus form field mapping, React controlled-component value setting, select/cascade/date-picker interaction, splitting long text across fields, and post-fill verification. For base WebBridge tool usage read the kimi-webbridge skill; this skill only adds form-filling-specific experience.
---

# WebBridge Form Filling (实战经验)

Real-world scenarios: the user has a recruiting-system resume page open (`talent.baidu.com`, `careers.oppo.com`, …) and wants it filled or restructured. Every item below comes from actual failures.

## 0. Read kimi-webbridge first

Base tool table, session rules, screenshot paths → see `kimi-webbridge`. This skill adds only the form-filling specifics.

## 1. Connect & upgrade

- Daemon unreachable (connection refused): just run `~/.kimi-webbridge/bin/kimi-webbridge start`. Idempotent, safe. Don't ask the user.
- `no extension connected`: daemon is up but the extension isn't. Retry after 3–8 s a few times; then ask the user to refresh the page / click the extension icon.
- Version mismatch / "Please update": run `~/.kimi-webbridge/bin/kimi-webbridge upgrade` (downloads new build, restarts daemon), then wait for re-connect.

## 2. Tabs: reuse the user's open page

- When the user says "fill the page I have open": use `find_tab` with `active:true`. Do NOT `navigate` a new tab — users actively dislike that.
- **Match the URL loosely**: full URLs carry huge query strings (`?shareId=...&recommendCode=...`) and full-URL matching fails. Match the domain, e.g. `{"url":"careers.oppo.com","active":true}`.
- **Keep the session identical**: the `find_tab` request body must carry the same top-level `session` as the later `snapshot`/`evaluate`. Missing session → find_tab succeeds but snapshot errors `session has no tab`.
- If no match, `list_tabs` (session-scoped) or ask the user to bring the tab to the foreground.

## 3. Map the form quickly (don't fight snapshot)

`snapshot` a11y trees are huge for long forms and get truncated. Use `evaluate` to grab structure directly:

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

- Element UI / Element Plus (`.el-form-item`, `.el-input__inner`, `.el-select`) is near-universal in recruiting systems; fall back to `[class*=form-item]`.
- After mapping, **tag target inputs with `data-*`** (`el.dataset.wb = 'proj1-0'`) and operate via `[data-wb="proj1-0"]` to survive hashed classnames and duplicate card structures (项目-1/项目-2).
- **Duplicate-input trap**: React forms render a visible textarea plus a hidden mirror (same value, `offsetParent===null`). Filter by `el.offsetParent!==null` and only touch the visible one.

## 4. React controlled components (when `fill` fails)

`fill` errors with `fill: Uncaught` on Baidu resume textareas. Use the native setter + events:

```js
const setVal = (el, v) => {
  const proto = el.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
  Object.getOwnPropertyDescriptor(proto, 'value').set.call(el, v);
  el.dispatchEvent(new Event('input',  { bubbles: true }));
  el.dispatchEvent(new Event('change', { bubbles: true }));
};
```

- Short text inputs: `fill` usually works. Long textareas: prefer the setter.
- **Always verify by re-reading** via `evaluate` (`.value`, `.value.length`). A `success:true` response does not mean React state updated.

## 5. Opening el-select dropdowns (the biggest pitfall)

Element Plus `el-select` often ignores synthetic events:

- Synthetic `click` won't open it → try keyboard first:
  ```js
  inp.focus();
  inp.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowDown', code: 'ArrowDown', keyCode: 40, bubbles: true }));
  ```
- Still stuck (wrapped components like OPPO's `dic-select`, `mul-school`): use **CDP real mouse**:
  ```json
  {"action":"cdp","args":{"method":"Input.dispatchMouseEvent","params":{"type":"mousePressed","x":507,"y":455,"button":"left","clickCount":1}}}
  {"action":"cdp","args":{"method":"Input.dispatchMouseEvent","params":{"type":"mouseReleased","x":507,"y":455,"button":"left","clickCount":1}}}
  ```
  Get coordinates via `evaluate` from `getBoundingClientRect()` center, after `scrollIntoView({block:'center'})` — stale coords break it.
- **Multiple dropdown panels coexist**: several `.el-select-dropdown` nodes may linger, only one visible. Locate the visible one before picking:
  ```js
  const dd = [...document.querySelectorAll('.el-select-dropdown')]
    .find(p => getComputedStyle(p).display !== 'none' && p.offsetParent !== null);
  ```
  Otherwise you click options of the wrong dropdown (real incidents: clicking nationality showed ID-type options; picked "学校就业网" instead of "校园大使推荐").
- Select an option with `mousedown` + `mouseup` + `click` (click alone sometimes doesn't fire).
- **Remote-search dropdowns** (OPPO school name: readonly + `icon-search`): opens with zero options; needs real keyboard input to trigger suggestions. Synthetic setter is ignored → CDP click to focus, then:
  ```json
  {"action":"cdp","args":{"method":"Input.insertText","params":{"text":"电子科技大学"}}}
  ```
  Wait 1–2 s, pick from the visible panel.
- After picking, re-read the input's `.value`.

## 6. Date pickers

- Clicking opens a calendar, but **you don't need to click the calendar grid**: set `2000-01-01` (example) on the input via setter then dispatch keydown Enter. Element accepts it.
- Derive dates from the ID card (digits 7–14), copy from an existing resume page, or ask.

## 7. Splitting long text / multiple projects

Users often say "everything went into field X, split it into the right fields" (e.g. Baidu: two projects + self-evaluation all crammed into 项目职责).

- `evaluate` the full original text, slice by structure (project name / role / intro / duties).
- Per project: name & role → inputs; intro → "项目描述" (mind the cap, e.g. `0 / 2000`); details → "项目职责".
- For multiple projects, click "+添加项目经验" (`[class*=add-one]` or text containing 添加项目) to spawn card N+1, tag it with `data-*`, then fill.
- If the target system has no matching section (e.g. no 自我评价 section), say so plainly; don't force it in.

## 8. Required fields & wrap-up

- Find required fields via `.is-required` class or `*` label prefix. Only ask the user for genuinely missing key info (major, department, hometown, …), not all 30 blanks.
- Resume pages usually have a 保存 button; **do not click save/submit on your own** — report and let the user confirm.
- Verify throughout with `evaluate`: values, lengths, dropdown echoes, card counts.

## 9. Request body construction

- For Chinese/long evaluate code, write the JSON body with Python `json.dump` and send via `curl --data-binary @file` to dodge shell escaping and CJK corruption (mandatory on Windows).
- Long responses get truncated: redirect to a file then `Read`, or have evaluate return a digest (length / first N chars) instead of the whole page.
