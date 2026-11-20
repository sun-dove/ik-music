"""生成「漾音」各平台图标。用法: python build_icons.py
依赖: Pillow；渲染 SVG 用本机 Edge 无头模式。"""
import json
import math
import os
import shutil
import subprocess

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.abspath(__file__))
TMP = os.path.join(ROOT, "_tmp")
EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
NAME = "yangyin"
C1, C2 = "#16C2B0", "#0B2A6B"  # 渐变：左上 -> 右下

# 图形在自身坐标系里的包围盒中心和最大边长
BX, BY, BSIZE = 553.25, 509.9, 680.0


def n(v):
    return f"{v:.3f}".rstrip("0").rstrip(".")


def glyph(canvas, frac, small=False):
    """返回图形的若干 path d 字符串。frac = 图形最大边占画布的比例。
    small=True 是给 32px 以下用的版本：符干更粗、两条波浪间距更大。"""
    s = canvas * frac / BSIZE
    tx, ty = canvas / 2 - BX * s, canvas / 2 - BY * s

    def P(x, y):
        return f"{n(x * s + tx)},{n(y * s + ty)}"

    # 符头：旋转 -22° 的椭圆，用两段圆弧表示
    cx, cy, rx, ry, deg = 350, 742, 138, 102, -22
    ex, ey = rx * math.cos(math.radians(deg)), rx * math.sin(math.radians(deg))
    p1, p2 = P(cx - ex, cy - ey), P(cx + ex, cy + ey)
    arc = f"A{n(rx * s)},{n(ry * s)} {deg} 1,0"
    head = f"M{p1} {arc} {p2} {arc} {p1} Z"

    x0 = 418 if small else 432  # 符干左边缘
    stem = f"M{P(x0, 170)} L{P(484, 170)} L{P(484, 720)} L{P(x0, 720)} Z"

    def ribbon(pts, dy=0):
        q = [P(x, y + dy) for x, y in pts]
        return (f"M{q[0]} L{q[1]} C{q[2]} {q[3]} {q[4]} C{q[5]} {q[6]} {q[7]} "
                f"C{q[8]} {q[9]} {q[10]} C{q[11]} {q[12]} {q[13]} L{q[14]} Z")

    xi = x0 + 8  # 波浪起点压进符干里，避免接缝
    top = [(xi, 170), (484, 170), (575, 170), (625, 285), (725, 285), (795, 285), (845, 245),
           (890, 195), (862, 300), (795, 372), (705, 372), (610, 372), (565, 292), (484, 292),
           (xi, 292)]
    low = [(xi, 345), (484, 345), (570, 345), (615, 450), (705, 450), (770, 450), (815, 415),
           (855, 372), (830, 468), (770, 532), (690, 532), (600, 532), (560, 460), (484, 460),
           (xi, 460)]
    return [head, stem, ribbon(top), ribbon(low, 26 if small else 0)]


def svg(canvas, body, defs=""):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {canvas} {canvas}" '
            f'width="{canvas}" height="{canvas}">{defs}{body}</svg>\n')


def paths(ds, fill):
    return "".join(f'<path fill="{fill}" d="{d}"/>' for d in ds)


def grad(x1, y1, x2, y2):
    return (f'<defs><linearGradient id="bg" gradientUnits="userSpaceOnUse" x1="{x1}" y1="{y1}" '
            f'x2="{x2}" y2="{y2}"><stop offset="0" stop-color="{C1}"/>'
            f'<stop offset="1" stop-color="{C2}"/></linearGradient></defs>')


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


def render(svg_text, name, w=1024, h=1024):
    src = os.path.join(TMP, name + (".html" if svg_text.lstrip().startswith("<!doctype") else ".svg"))
    out = os.path.join(TMP, name + ".png")
    write(src, svg_text)
    subprocess.run([EDGE, "--headless", "--disable-gpu", "--hide-scrollbars",
                    "--default-background-color=00000000", f"--window-size={w},{h}",
                    f"--screenshot={out}", "file:///" + src.replace("\\", "/")],
                   capture_output=True, timeout=120, check=True)
    return Image.open(out).convert("RGBA")


def masked(img, radius_frac):
    """radius_frac=0.5 即圆形。4 倍超采样保证边缘平滑。"""
    S, k = img.size[0], 4
    m = Image.new("L", (S * k, S * k), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, S * k - 1, S * k - 1], radius=int(S * k * radius_frac), fill=255)
    out = img.copy()
    out.putalpha(m.resize((S, S), Image.LANCZOS))
    return out


def padded(img, frac):
    S = img.size[0]
    inner = img.resize((round(S * frac),) * 2, Image.LANCZOS)
    out = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    off = (S - inner.size[0]) // 2
    out.paste(inner, (off, off), inner)
    return out


def save(img, path, size, rgb=False):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    im = img.resize((size, size), Image.LANCZOS)
    (im.convert("RGB") if rgb else im).save(path)


def android_vector(ds, fill):
    body = "".join(f'\n    <path android:fillColor="{fill}" android:pathData="{d}"/>' for d in ds)
    return ('<?xml version="1.0" encoding="utf-8"?>\n'
            '<vector xmlns:android="http://schemas.android.com/apk/res/android"\n'
            '    android:width="108dp" android:height="108dp"\n'
            '    android:viewportWidth="108" android:viewportHeight="108">' + body + '\n</vector>\n')


def main():
    shutil.rmtree(TMP, ignore_errors=True)
    os.makedirs(TMP)
    bg = '<rect width="1024" height="1024" fill="url(#bg)"/>'
    g1024 = grad(0, 0, 1024, 1024)

    # ---------- 源文件 ----------
    full_svg = svg(1024, bg + paths(glyph(1024, 0.56), "#fff"), g1024)
    small_svg = svg(1024, bg + paths(glyph(1024, 0.70, small=True), "#fff"), g1024)
    tile_svg = svg(1024, '<rect width="1024" height="1024" rx="230" fill="url(#bg)"/>'
                   + paths(glyph(1024, 0.56), "#fff"), g1024)
    glyph_svg = svg(1024, paths(glyph(1024, 0.66), "#000"))
    write(os.path.join(ROOT, "src", "icon-fullbleed.svg"), full_svg)
    write(os.path.join(ROOT, "src", "icon-rounded.svg"), tile_svg)
    write(os.path.join(ROOT, "src", "icon-small.svg"), small_svg)
    write(os.path.join(ROOT, "src", "glyph.svg"), glyph_svg)

    full = render(full_svg, "full")
    small = render(small_svg, "small")
    glyph_png = render(glyph_svg, "glyph")
    tile, tile_s = masked(full, 0.225), masked(small, 0.21)
    save(glyph_png, os.path.join(ROOT, "src", "glyph-black-1024.png"), 1024)

    # ---------- Windows ----------
    win = os.path.join(ROOT, "windows")
    os.makedirs(win, exist_ok=True)
    sizes = [16, 20, 24, 32, 40, 48, 64, 128, 256]
    frames = {s: (tile_s if s <= 32 else tile).resize((s, s), Image.LANCZOS) for s in sizes}
    frames[256].save(os.path.join(win, NAME + ".ico"), format="ICO", sizes=[(s, s) for s in sizes],
                     append_images=[frames[s] for s in sizes if s != 256])
    save(tile, os.path.join(win, NAME + "-256.png"), 256)

    # ---------- Linux (hicolor 图标主题) ----------
    lin = os.path.join(ROOT, "linux")
    for s in [16, 22, 24, 32, 48, 64, 128, 256, 512]:
        save(tile_s if s <= 32 else tile,
             os.path.join(lin, "hicolor", f"{s}x{s}", "apps", NAME + ".png"), s)
    write(os.path.join(lin, "hicolor", "scalable", "apps", NAME + ".svg"), tile_svg)
    write(os.path.join(lin, NAME + ".desktop"),
          "[Desktop Entry]\nType=Application\nName=漾音\nName[en]=Yangyin\nComment=音乐播放器\n"
          f"Exec={NAME} %U\nIcon={NAME}\nCategories=AudioVideo;Audio;Music;Player;\nTerminal=false\n")

    # ---------- Android ----------
    res = os.path.join(ROOT, "android", "res")
    fg = glyph(108, 0.41)  # 最远点半径约 30dp，落在 66dp 安全区内
    write(os.path.join(res, "drawable", "ic_launcher_foreground.xml"), android_vector(fg, "#FFFFFFFF"))
    write(os.path.join(res, "drawable", "ic_launcher_background.xml"),
          '<?xml version="1.0" encoding="utf-8"?>\n'
          '<vector xmlns:android="http://schemas.android.com/apk/res/android"\n'
          '    xmlns:aapt="http://schemas.android.com/aapt"\n'
          '    android:width="108dp" android:height="108dp"\n'
          '    android:viewportWidth="108" android:viewportHeight="108">\n'
          '    <path android:pathData="M0,0h108v108h-108z">\n'
          '        <aapt:attr name="android:fillColor">\n'
          '            <gradient android:type="linear"\n'
          '                android:startX="18" android:startY="18" android:endX="90" android:endY="90"\n'
          f'                android:startColor="#FF{C1[1:]}" android:endColor="#FF{C2[1:]}"/>\n'
          '        </aapt:attr>\n    </path>\n</vector>\n')
    adaptive = ('<?xml version="1.0" encoding="utf-8"?>\n'
                '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
                '    <background android:drawable="@drawable/ic_launcher_background"/>\n'
                '    <foreground android:drawable="@drawable/ic_launcher_foreground"/>\n'
                '    <monochrome android:drawable="@drawable/ic_launcher_foreground"/>\n'
                '</adaptive-icon>\n')
    write(os.path.join(res, "mipmap-anydpi-v26", "ic_launcher.xml"), adaptive)
    write(os.path.join(res, "mipmap-anydpi-v26", "ic_launcher_round.xml"), adaptive)
    legacy_sq, legacy_round = padded(masked(full, 0.2), 0.875), padded(masked(full, 0.5), 0.94)
    for d, s in [("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)]:
        save(legacy_sq, os.path.join(res, f"mipmap-{d}", "ic_launcher.png"), s)
        save(legacy_round, os.path.join(res, f"mipmap-{d}", "ic_launcher_round.png"), s)
    save(full, os.path.join(ROOT, "android", "play-store-512.png"), 512, rgb=True)
    # 用和 XML 完全相同的路径数据画一张 SVG，用来在预览里核对自适应图标
    adaptive_svg = svg(108, '<rect width="108" height="108" fill="url(#bg)"/>' + paths(fg, "#fff"),
                       grad(18, 18, 90, 90))
    mono_svg = svg(108, '<rect width="108" height="108" fill="#D7E3F8"/>' + paths(fg, "#1B3A5F"))
    write(os.path.join(TMP, "adaptive.svg"), adaptive_svg)
    write(os.path.join(TMP, "mono.svg"), mono_svg)

    # ---------- iOS ----------
    ios = os.path.join(ROOT, "ios", "AppIcon.appiconset")
    save(full, os.path.join(ios, "icon-1024.png"), 1024, rgb=True)  # iOS 不允许透明通道
    write(os.path.join(ios, "Contents.json"), json.dumps({
        "images": [{"filename": "icon-1024.png", "idiom": "universal", "platform": "ios",
                    "size": "1024x1024"}],
        "info": {"author": "xcode", "version": 1}}, indent=2) + "\n")

    # ---------- 预览 ----------
    ico = Image.open(os.path.join(win, NAME + ".ico"))
    got = sorted(s[0] for s in ico.ico.sizes())
    assert got == sizes, got
    for s in sizes:
        ico.ico.getimage((s, s)).save(os.path.join(TMP, f"ico{s}.png"))

    def imgs(tpl, ss):
        return "".join(tpl.format(s=s) for s in ss)

    win_row = imgs('<img src="_tmp/ico{s}.png" width="{s}">', [16, 24, 32, 48, 64, 128])
    zoom = "".join(f'<img class="px" src="_tmp/ico{s}.png" width="{s * 6}">' for s in [16, 20, 24, 32])
    lin_row = imgs(f'<img src="linux/hicolor/{{s}}x{{s}}/apps/{NAME}.png" width="{{s}}">', [16, 22, 32, 48, 64, 128])

    def adaptive_mask(src, radius):
        return (f'<div class="ad" style="border-radius:{radius}"><img src="_tmp/{src}"></div>')

    html = f"""<!doctype html><meta charset="utf-8"><style>
body{{margin:0;width:1400px;height:1010px;font:13px "Microsoft YaHei",sans-serif;display:grid;
 grid-template-columns:1fr 1fr;grid-template-rows:auto auto auto}}
section{{padding:22px 30px}} h3{{margin:0 0 14px;font-size:14px;font-weight:600}}
.l{{background:#f3f3f3;color:#222}} .d{{background:#1f2023;color:#ddd}}
.row{{display:flex;align-items:flex-end;gap:22px;margin-bottom:14px}} .px{{image-rendering:pixelated}}
.ad{{width:96px;height:96px;overflow:hidden;position:relative}}
.ad img{{position:absolute;width:144px;height:144px;left:-24px;top:-24px}}
.ios{{border-radius:22.37%}}
</style>
<section class="l"><h3>Windows · yangyin.ico（实际尺寸 16/24/32/48/64/128）</h3><div class="row">{win_row}</div></section>
<section class="d"><h3>Windows · 深色任务栏</h3><div class="row">{win_row}</div></section>
<section class="l"><h3>Windows 小尺寸放大 6 倍（16/20/24/32）</h3><div class="row">{zoom}</div></section>
<section class="d"><h3>Linux · hicolor（16/22/32/48/64/128）</h3><div class="row">{lin_row}</div></section>
<section class="l"><h3>Android 自适应图标（圆 / 圆角方 / 方圆）+ Android 13 主题图标</h3><div class="row">
{adaptive_mask("adaptive.svg", "50%")}{adaptive_mask("adaptive.svg", "22%")}{adaptive_mask("adaptive.svg", "38%")}
{adaptive_mask("mono.svg", "50%")}</div>
<div class="row"><img src="android/res/mipmap-xxhdpi/ic_launcher.png" width="72">
<img src="android/res/mipmap-xxhdpi/ic_launcher_round.png" width="72">
<img src="android/res/mipmap-mdpi/ic_launcher.png" width="48"><span>旧版 PNG</span></div></section>
<section class="d"><h3>iOS · 1024 满版（系统裁圆角后的样子）</h3><div class="row">
<img class="ios" src="ios/AppIcon.appiconset/icon-1024.png" width="180">
<img class="ios" src="ios/AppIcon.appiconset/icon-1024.png" width="120">
<img class="ios" src="ios/AppIcon.appiconset/icon-1024.png" width="60">
<img class="ios" src="ios/AppIcon.appiconset/icon-1024.png" width="29"></div></section>
"""
    page = os.path.join(ROOT, "_preview.html")
    write(page, html)
    out = os.path.join(ROOT, "preview.png")
    subprocess.run([EDGE, "--headless", "--disable-gpu", "--hide-scrollbars", "--window-size=1400,1010",
                    f"--screenshot={out}", "file:///" + page.replace("\\", "/")],
                   capture_output=True, timeout=120, check=True)
    os.remove(page)
    shutil.rmtree(TMP, ignore_errors=True)
    print("ico sizes:", got)
    print("ok")


if __name__ == "__main__":
    main()
