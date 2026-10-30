"""
逐光 / LightBearing 应用图标生成

按设计稿（lightbearing_ui.html brandIcon sun 形状）重新绘制，输出：
- docs/icon/lightbearing_icon.svg      矢量源（单一主体 + 两级渐变）
- docs/icon/lightbearing_icon_1024.png 1024×1024 预览图
- AppScope / entry 资源：layered icon 的 background.png + foreground.png
- entry startIcon.png

形状来源（64 单位坐标系，与设计稿一致）：
  地平线 M10 51 h44
  半圆   M14 44 a18 18 0 0 1 36 0
  三道光 M32 9 v13 / M13 24 l9 7 / M51 24 l-9 7
  太阳盘 circle(32,44,r=7)

运行：python tools/icon-gen/make_icon.py
"""

import math
import os
from PIL import Image, ImageDraw

PRIMARY = (255, 188, 107)
ACCENT = (115, 217, 213)
INK = (39, 50, 65)
SS = 4  # 超采样倍数，用于抗锯齿

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))


def gradient_square(size: int) -> Image.Image:
    """130° 线性渐变：#FFBC6B → #73D9D5（与设计稿 130deg 一致）"""
    img = Image.new("RGB", (size, size))
    px = img.load()
    angle = math.radians(130)
    dx, dy = math.cos(angle), math.sin(angle)
    # 归一化投影范围
    corners = [(0, 0), (size, 0), (0, size), (size, size)]
    proj = [x * dx + y * dy for x, y in corners]
    lo, hi = min(proj), max(proj)
    for y in range(size):
        for x in range(size):
            t = ((x * dx + y * dy) - lo) / (hi - lo)
            t = max(0.0, min(1.0, t))
            px[x, y] = (
                round(PRIMARY[0] + (ACCENT[0] - PRIMARY[0]) * t),
                round(PRIMARY[1] + (ACCENT[1] - PRIMARY[1]) * t),
                round(PRIMARY[2] + (ACCENT[2] - PRIMARY[2]) * t),
            )
    return img


def draw_sun(canvas_size: int, glyph_ratio: float) -> Image.Image:
    """在透明画布上绘制 sun 图形；glyph_ratio 为图形占画布的比例"""
    big = canvas_size * SS
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    scale = glyph_ratio * big / 64.0
    offset = (big - 64 * scale) / 2.0

    def p(x: float, y: float):
        return (offset + x * scale, offset + y * scale)

    width = max(2, int(round(5 * scale)))

    # 地平线
    d.line([p(10, 51), p(54, 51)], fill=INK + (255,), width=width)
    # 半圆（半径 18，圆心 32,44）
    bbox = [p(14, 26)[0], p(14, 26)[1], p(50, 62)[0], p(50, 62)[1]]
    d.arc(bbox, start=180, end=360, fill=INK + (255,), width=width)
    # 三道光线
    d.line([p(32, 9), p(32, 22)], fill=INK + (255,), width=width)
    d.line([p(13, 24), p(22, 31)], fill=INK + (255,), width=width)
    d.line([p(51, 24), p(42, 31)], fill=INK + (255,), width=width)
    # 太阳盘
    cx, cy = p(32, 44)
    r = 7 * scale
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=INK + (255,))

    return img.resize((canvas_size, canvas_size), Image.LANCZOS)


def write_png(img: Image.Image, rel_path: str) -> None:
    path = os.path.join(ROOT, rel_path)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path, "PNG")
    print(f"written {rel_path} {img.size}")


def main() -> None:
    size = 1024

    # 1. 完整图标（预览/交付）
    base = gradient_square(size).convert("RGBA")
    base.alpha_composite(draw_sun(size, 0.62))
    write_png(base, "docs/icon/lightbearing_icon_1024.png")

    # 2. layered icon：background 全幅渐变，foreground 透明底图形
    background = gradient_square(size).convert("RGBA")
    foreground = draw_sun(size, 0.56)
    write_png(background, "AppScope/resources/base/media/background.png")
    write_png(foreground, "AppScope/resources/base/media/foreground.png")
    write_png(background, "entry/src/main/resources/base/media/background.png")
    write_png(foreground, "entry/src/main/resources/base/media/foreground.png")

    # 3. 启动图标（带圆角，避免系统未遮罩时露出直角）
    start = base.copy()
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size - 1, size - 1], radius=int(size * 0.22), fill=255)
    start.putalpha(mask)
    write_png(start, "entry/src/main/resources/base/media/startIcon.png")

    # 3.5 多尺寸位图（交付给旧平台/商店素材用；HarmonyOS 分层图标仍用 1024 前景+背景）
    for size_px in (48, 72, 96, 144, 192, 288, 512):
        scaled = base.resize((size_px, size_px), Image.LANCZOS)
        write_png(scaled, f"docs/icon/sizes/lightbearing_icon_{size_px}.png")

    # 4. 矢量源
    svg = f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" width="1024" height="1024" role="img" aria-label="逐光 LightBearing 应用图标">
  <defs>
    <linearGradient id="lbGrad" x1="0" y1="0" x2="1" y2="1" gradientTransform="rotate(40 0.5 0.5)">
      <stop offset="0" stop-color="#FFBC6B"/>
      <stop offset="1" stop-color="#73D9D5"/>
    </linearGradient>
  </defs>
  <rect width="64" height="64" rx="14" fill="url(#lbGrad)"/>
  <g fill="none" stroke="#273241" stroke-width="3.1" stroke-linecap="round">
    <path d="M10 51h44"/>
    <path d="M14 44a18 18 0 0 1 36 0"/>
    <path d="M32 9v13"/>
    <path d="M13 24l9 7"/>
    <path d="M51 24l-9 7"/>
  </g>
  <circle cx="32" cy="44" r="7" fill="#273241"/>
</svg>
"""
    svg_path = os.path.join(ROOT, "docs", "icon", "lightbearing_icon.svg")
    os.makedirs(os.path.dirname(svg_path), exist_ok=True)
    with open(svg_path, "w", encoding="utf-8") as f:
        f.write(svg)
    print("written docs/icon/lightbearing_icon.svg")


if __name__ == "__main__":
    main()
