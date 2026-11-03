# UI-0 · 设计系统基线（Token 与组件规则）

> 依据：`common/Theme.ets`（现状实际值）、`lightbearing_ui.html`（原稿 token 面板）、
> `lightbearing_dev_prd.md` §3（视觉系统）、真机截图 `docs/screenshots/qa2c_01_home.jpeg`。
> 本轮只定义系统，不重绘页面；实现落在 UI-1。

## 1. 现状 Token（VERIFIED，取自 Theme.ets）

| 组 | 值 |
|---|---|
| 间距 | XS 4 / S 8 / M 12 / L 16 / XL 20 / XXL 24 / XXXL 32 |
| 圆角 | CARD 19 / HERO 24 / BUTTON 12 / CHIP 40 / STAT 15 / ICONBOX 12 / APPLOGO 17 |
| 字级 | CAPTION 11 / SMALL 12 / EYEBROW 12 / BODY 14 / BODY_L 15 / TITLE 20 / HERO_H2 22 / H1 30 |
| 触控 | `MIN_TOUCH`（全页统一引用；值需一次核对，原稿要求 ≥44vp） |
| 颜色 | 通过 `$r('app.color.lb_*')` 引用（bg/panel/panel2/ink/muted/line/primary/accent） |

## 2. 原稿 token（VERIFIED，取自 lightbearing_ui.html）

```text
--bg #0D1A29   --panel #182C3D   --panel2 #213B4E
--primary #FFBC6B   --accent #73D9D5
--ink #F9FAF3   --muted #A2B9C5   --line rgba(226,246,255,.12)
间距 4/8/12/16/24/32vp   卡片 16vp   按钮 12vp   hero 24vp
字级：正文 14–16vp / 标题 20–36vp    动效 160–240ms（可关闭）
```

## 3. 差异与裁决

| 项 | 原稿 | 现状 | 裁决 |
|---|---|---|---|
| 主题基线 | 深色 | 浅色（截图） | **双主题并存**：浅色为默认，深色为一等公民；两套都必须通过对比度 ≥4.5:1 |
| 卡片圆角 | 16 | 19 | 统一为 **18vp**（取中间，减少既有页面跳变） |
| 字级上限 | 36 | 30 | 新增 `DISPLAY 36`，仅 hero/页面主标题使用 |
| 间距档位 | 无 20 | 有 XL 20 | 保留 20（已有页面大量使用），文档标注为「仅用于卡片内间距」 |
| 图标尺寸 | 20–24 | 线性图标组件 | 固定 20（行内）/ 24（导航） |

## 4. 语义化 Token（UI-1 落地目标）

```text
color.surface.base / raised / sunken      卡片与浮层三级
color.text.primary / secondary / disabled
color.accent.primary / onPrimary
color.status.ok / warn / danger / info
radius.card 18 / control 12 / chip 999 / sheet 24
space.1..7 = 4/8/12/16/20/24/32
type.display 36 / h1 30 / h2 22 / title 20 / body 15 / bodyS 14 / caption 12 / micro 11
touch.min 48（≥原稿 44，含 4vp 视觉边距）
```

## 5. 组件规则（最小集）

| 组件 | 规则 |
|---|---|
| 卡片 Card | 圆角 18、内边距 16、底色 surface.raised、1px line、无阴影（浅色）|
| 主按钮 | 高 48、圆角 12、accent 底 + onPrimary 文字；禁用态 opacity .42 |
| 次按钮 | panel2 底 + primary 文字；不得用于「危险」 |
| 危险按钮 | danger 底或 danger 边框 + 二次确认（沿用现有 Dialog）|
| 状态徽标 | 文字 + 颜色双通道（不能只用颜色） |
| 空态 | 标题 + 一句说明 + 一个动作（禁止只放插图） |
| 错误条 | 行内警示条（不遮挡表单），带「重试」动作 |
| 进度浮层 | 必须可取消；取消按钮始终可点（不被进度内容遮挡） |
| 输入框 | 标签在上、单位在右、错误在下的三段式；数值框允许空串但不允许静默回退 |

## 6. 可访问性基线

- 触控 ≥48vp，相邻可点元素间距 ≥8vp；
- 正文对比度 ≥4.5:1，大字 ≥3:1；不得仅靠颜色传达状态（已有「昼/夜/无/缺」双通道可作范式）；
- 支持系统字体缩放（正文允许换行，不设固定行高裁切）；
- 动效遵循 `prefers-reduced-motion`（见 `UI0_MOTION_SPEC.md`）；
- 所有图标按钮需 `accessibilityText`（正式设计，不是测试用 ID）。

## 7. 状态

本文档为**规范基线**：Token 现状为 VERIFIED（源码），原稿值为 VERIFIED（原稿），
「裁决」与「语义化 Token」为待 UI-1 实施的设计决定；深色主题的实机表现 NOT_RUN。
