"""
逐光 / LightBearing 线性图标生成

图标路径直接取自设计稿 lightbearing_ui.html 的 PATHS 字典（同一套 24×24、stroke 1.8、
linecap/linejoin round 的线性图标语言），另补少量设计稿未给出但页面需要的图标。

输出：
  entry/src/main/resources/base/media/ic_<name>_<variant>.svg   浅色主题
  entry/src/main/resources/dark/media/ic_<name>_<variant>.svg   深色主题

不用 Image.fillColor 着色，因为它对 fill="none" 的描边图标不生效；
改为把颜色烘进 SVG，并通过 dark 资源限定目录切换深浅色。

运行：python tools/icon-gen/make_icons.py
"""

import os

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
BASE = os.path.join(ROOT, "entry", "src", "main", "resources", "base", "media")
DARK = os.path.join(ROOT, "entry", "src", "main", "resources", "dark", "media")

# 与设计稿 PATHS 一致（24×24 线性图标）
PATHS = {
    "home": "M3 11 12 3l9 8v10H3z M9 21v-8h6v8",
    "sunpath": "M3 19h18 M4 16a8 8 0 0 1 16 0 M12 3v4",
    "reverse": "M7 3h10v4 M7 21h10v-4 M12 7v10 M9 14l3 3 3-3",
    "locations": "M12 22s7-8 7-13a7 7 0 0 0-14 0c0 5 7 13 7 13z M12 12a3 3 0 1 0 0-6 3 3 0 0 0 0 6",
    "compass": "M12 2l8 19-8-5-8 5z",
    "map": "M3 5l6-2 6 2 6-2v16l-6 2-6-2-6 2z M9 3v16 M15 5v16",
    "planner": "M4 4h16v17H4z M8 2v5 M16 2v5 M4 10h16",
    "calendar": "M4 5h16v16H4z M4 10h16 M8 2v6 M16 2v6",
    "compare": "M3 18h18 M4 12l5-5 4 4 6-6",
    "settings": "M12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8 M12 2v3 M12 19v3 M2 12h3 M19 12h3 M4.9 4.9l2.2 2.2 M16.9 16.9l2.2 2.2 M19.1 4.9l-2.2 2.2 M7.1 16.9l-2.2 2.2",
    "more": "M6 12h.01 M12 12h.01 M18 12h.01",
    "sun": "M4 19h16 M5.5 16a6.5 6.5 0 0 1 13 0 M12 3v4.5 M4.6 8.6l3 2.4 M19.4 8.6l-3 2.4 M12 16a3.2 3.2 0 1 0 0-6.4 3.2 3.2 0 0 0 0 6.4",
    "export": "M12 3v12 m-5-5 5 5 5-5 M4 17v4h16v-4",
    "history": "M4 12a8 8 0 1 0 4-7 M4 4v5h5 M12 7v5l3 2",
    "preview": "M4 4h16v16H4z M10 8l7 4-7 4z",
    "activity": "M3 12h5l3-8 3 16 3-8h4",
    "diagnostics": "M4 18l4-4 4 3 4-8 4 2 M4 4h16v16H4z",
    "macros": "M4 4h6v6H4z M14 14h6v6h-6z M10 7h7v7",
    "library": "M3 5h7l2 2h9v13H3z",
    "timeline": "M3 4h18v16H3z M9 4v16 M15 4v16 M3 10h18",
    "frame": "M4 4h16v16H4z M4 16l5-5 3 3 3-5 5 7",
    "warning": "M12 3 2 21h20z M12 9v6 M12 18h.01",
    "search": "M11 4a7 7 0 1 0 0 14 7 7 0 0 0 0-14 M16.5 16.5 21 21",
    "plus": "M12 5v14 M5 12h14",
    "check": "M4 12l6 6 10-12",
    "close": "M5 5l14 14 M19 5L5 19",
    "trash": "M4 7h16 M9 4h6 M6 7l1 14h10l1-14 M10 11v6 M14 11v6",
    "edit": "M4 20h4L20 8l-4-4L4 16z",
    "chevron": "M9 5l7 7-7 7",
    "location_current": "M12 2v3 M12 19v3 M2 12h3 M19 12h3 M12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8",
    "target": "M12 2v4 M12 18v4 M2 12h4 M18 12h4 M12 6a6 6 0 1 0 0 12 6 6 0 0 0 0-12 M12 10a2 2 0 1 0 0 4 2 2 0 0 0 0-4",
    "clock": "M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18 M12 7v5l4 2",
    "note": "M4 3h12l4 4v14H4z M12 11v7 m-4-4 4-4 4 4",
    "checklist": "M4 6h3l2 2 M4 14h3l2 2 M13 7h7 M13 16h7",
}

# 深色/浅色两套调色板（浅色为深色设计的浅底等价物，保证 AA 对比度）
PALETTES = {
    "dark": {
        "ink": "#F9FAF3",
        "muted": "#A2B9C5",
        "primary": "#FFBC6B",
        "accent": "#73D9D5",
        "bg": "#0D1A29",
    },
    "light": {
        "ink": "#0D1A29",
        "muted": "#516A7B",
        "primary": "#9C5A08",
        "accent": "#146E6B",
        "bg": "#F2F6F9",
    },
}

# 每个图标需要哪些颜色变体（尽量减少资源数量）
MANIFEST = {
    # 导航：未选中 muted / 选中 ink（与设计稿 .navbtn 一致）
    "home": ["muted", "ink", "primary"],
    "sunpath": ["muted", "ink", "primary"],
    "reverse": ["muted", "ink", "primary"],
    "locations": ["muted", "ink", "primary"],
    "compass": ["muted", "ink", "primary"],
    "map": ["muted", "ink", "primary"],
    "planner": ["muted", "ink", "primary"],
    "calendar": ["muted", "ink", "primary"],
    "compare": ["muted", "ink", "primary"],
    "settings": ["muted", "ink", "primary"],
    "more": ["muted", "ink", "primary"],
    # 品牌与状态
    "sun": ["primary", "bg"],
    "warning": ["primary"],
    "search": ["muted", "ink"],
    "plus": ["bg", "primary"],
    "check": ["primary", "muted"],
    "close": ["muted"],
    "trash": ["primary"],
    "edit": ["muted"],
    "chevron": ["muted"],
    "location_current": ["primary", "muted"],
    "target": ["primary"],
    "export": ["primary", "ink"],
    "history": ["muted"],
    "clock": ["muted"],
    "note": ["primary", "muted"],
    "checklist": ["primary", "muted"],
    "preview": ["muted"],
    "activity": ["primary"],
    "diagnostics": ["muted"],
}

SVG_TEMPLATE = (
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" '
    'stroke="{color}" stroke-width="{width}" stroke-linecap="round" stroke-linejoin="round">'
    '<path d="{path}"/></svg>\n'
)

# 少数图标需要更粗的笔画（三点省略号在 20vp 下会显得过细）
WIDTH_OVERRIDES = {
    "more": "3.4",
}


def write_set(theme: str, out_dir: str) -> int:
    palette = PALETTES[theme]
    os.makedirs(out_dir, exist_ok=True)
    count = 0
    for name, variants in MANIFEST.items():
        path = PATHS[name]
        width = WIDTH_OVERRIDES.get(name, "1.8")
        for variant in variants:
            color = palette[variant]
            filename = f"ic_{name}_{variant}.svg"
            with open(os.path.join(out_dir, filename), "w", encoding="utf-8") as f:
                f.write(SVG_TEMPLATE.format(color=color, path=path, width=width))
            count += 1
    return count


def main() -> None:
    light_count = write_set("light", BASE)
    dark_count = write_set("dark", DARK)
    print(f"light icons: {light_count} -> {BASE}")
    print(f"dark  icons: {dark_count} -> {DARK}")
    total = light_count + dark_count
    print(f"total {total} svg files")


if __name__ == "__main__":
    main()
