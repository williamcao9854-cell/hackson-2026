#!/usr/bin/env python3
"""
生成比赛要求的项目海报：调用 AMD 图像生成 API 画插画，再排版成竖版海报。

用法（在仓库根目录）：
    python3 -m pip install pillow          # 只需一次
    python3 tools/generate_poster.py       # 调 API 生成插画（默认 1024x1536、high 画质）+ 排版
    python3 tools/generate_poster.py --art posters/poster-art.png   # 已有插画，只重新排版
    python3 tools/generate_poster.py --art posters/poster-art.png --lang en   # 只排英文版

API 配置读取 Wuling/Resources/Secrets.plist（与 App 共用，不会提交到 Git）。
输出：posters/poster-art.png（API 原图）、posters/poster.png（中文海报）、posters/poster-en.png（英文海报）。
"""
import argparse
import base64
import json
import os
import plistlib
import sys
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SECRETS = os.path.join(ROOT, "Wuling", "Resources", "Secrets.plist")
OUT_DIR = os.path.join(ROOT, "posters")

ART_PROMPT = (
    "A poster illustration on warm off-white rice paper (hex #F4F0E8) with subtle paper-fiber texture. "
    "In the lower two thirds, a quiet gathering of gentle object spirits from East Asian folklore, each clearly formed "
    "from a well-loved everyday object: a worn running shoe, a chipped coffee mug, an old acoustic guitar, a faded teddy bear "
    "and a small alarm clock, all with small expressive eyes and tiny limbs, looking warmly at the viewer. "
    "Delicate watercolor washes with fine, confident ink-brush linework, muted earthy palette with one small touch of vermilion red. "
    "Leave the top third completely empty paper for a title. Whimsical yet dignified, like a beautifully printed East Asian picture book. "
    "No text, no letters, no signature, no border, no frame."
)

# (字体文件, 字体集里的第几个)：Noto CJK 的第 2 个是简体中文（第 0 个是日文字形）
FONT_CANDIDATES = [
    ("/System/Library/Fonts/Supplemental/Songti.ttc", 0),           # macOS 宋体
    ("/System/Library/Fonts/STHeiti Medium.ttc", 0),
    ("/System/Library/Fonts/PingFang.ttc", 0),
    ("/usr/share/fonts/opentype/noto/NotoSerifCJK-Bold.ttc", 2),    # Linux
    ("/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc", 2),
]

# 英文海报用的衬线字体
LATIN_CANDIDATES = [
    "/System/Library/Fonts/Supplemental/Baskerville.ttc",          # macOS
    "/System/Library/Fonts/Supplemental/Georgia.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationSerif-Regular.ttf",   # Linux
    "/usr/share/fonts/truetype/dejavu/DejaVuSerif.ttf",
]

PAPER = (0xF4, 0xF0, 0xE8)
INK = (0x1C, 0x1A, 0x17)
INK2 = (0x7A, 0x74, 0x6B)
VERMILION = (0xC8, 0x44, 0x2F)


def load_config():
    if not os.path.exists(SECRETS):
        sys.exit(f"找不到 {SECRETS}\n请先复制 Secrets.example.plist 为 Secrets.plist 并填入 AMD API 信息。")
    with open(SECRETS, "rb") as f:
        cfg = plistlib.load(f)
    for key in ("IMAGE_API_BASE_URL", "IMAGE_API_KEY", "IMAGE_API_MODEL"):
        if not cfg.get(key) or str(cfg[key]).startswith("YOUR_"):
            sys.exit(f"Secrets.plist 里的 {key} 还没有填写。")
    return cfg


def generate_art(cfg, size, quality):
    url = cfg["IMAGE_API_BASE_URL"].rstrip("/") + "/" + cfg.get("IMAGE_API_PATH", "/v1/images/generations").lstrip("/")
    body = {"model": cfg["IMAGE_API_MODEL"], "prompt": ART_PROMPT, "n": 1, "size": size}
    # gpt-image 系列：画质、输出格式；老的 dall-e 类接口才需要 response_format
    if quality:
        body["quality"] = quality
    if cfg.get("IMAGE_API_OUTPUT_FORMAT"):
        body["output_format"] = cfg["IMAGE_API_OUTPUT_FORMAT"]
    if cfg.get("IMAGE_API_RESPONSE_FORMAT"):
        body["response_format"] = cfg["IMAGE_API_RESPONSE_FORMAT"]
    req = urllib.request.Request(url, data=json.dumps(body).encode(), method="POST", headers={
        "Content-Type": "application/json",
        "Authorization": f"Bearer {cfg['IMAGE_API_KEY']}",
    })
    print(f"→ 调用图像 API：{url}（模型 {body['model']}，尺寸 {body['size']}，画质 {quality or '默认'}），可能要一两分钟…")
    try:
        with urllib.request.urlopen(req, timeout=600) as resp:
            data = json.load(resp)
    except urllib.error.HTTPError as e:
        sys.exit(f"API 返回错误 {e.code}：{e.read().decode(errors='replace')[:500]}")
    item = (data.get("data") or [{}])[0]
    if item.get("b64_json"):
        return base64.b64decode(item["b64_json"])
    if item.get("url"):
        with urllib.request.urlopen(item["url"], timeout=180) as resp:
            return resp.read()
    sys.exit(f"API 没有返回图片：{json.dumps(data)[:500]}")


def find_font():
    for path, index in FONT_CANDIDATES:
        if os.path.exists(path):
            return path, index
    return None


def compose(art_path, out_path):
    try:
        from PIL import Image, ImageDraw, ImageFont
    except ImportError:
        print("未安装 Pillow，跳过排版。插画已保存，可以自己在 Keynote / Figma 里加标题。")
        return
    found = find_font()
    if not found:
        print("找不到中文字体，跳过排版。")
        return

    W, H = 1800, 2700  # 2:3 竖版
    poster = Image.new("RGB", (W, H), PAPER)
    art = Image.open(art_path).convert("RGB")
    art_w = W
    art_h = int(art.height * art_w / art.width)
    art = art.resize((art_w, art_h), Image.LANCZOS)
    poster.paste(art, (0, H - art_h))

    d = ImageDraw.Draw(poster)
    font_path, font_index = found
    def font(size):
        return ImageFont.truetype(font_path, size, index=font_index)

    # 竖排标题「物灵」，右上
    title = font(300)
    x = W - 360
    for i, ch in enumerate("物灵"):
        d.text((x, 150 + i * 320), ch, font=title, fill=INK)

    # 左上：标语 + 说明
    left = 140
    d.text((left, 200), "拍下一件旧物，", font=font(72), fill=INK)
    d.text((left, 300), "唤醒它的物灵。", font=font(72), fill=INK)
    d.text((left, 430), "道一声谢，然后放手；", font=font(52), fill=INK2)
    d.text((left, 505), "或者，把它和它的故事", font=font(52), fill=INK2)
    d.text((left, 580), "一起传给下一个人。", font=font(52), fill=INK2)

    # 朱印
    seal = 170
    sx, sy = left, 720
    d.rounded_rectangle([sx, sy, sx + seal, sy + seal], radius=22, fill=VERMILION)
    d.rounded_rectangle([sx + 12, sy + 12, sx + seal - 12, sy + seal - 12], radius=14, outline=PAPER, width=5)
    sf = font(56)
    d.text((sx + seal / 2, sy + seal * 0.32), "传", font=sf, fill=PAPER, anchor="mm")
    d.text((sx + seal / 2, sy + seal * 0.68), "灵", font=sf, fill=PAPER, anchor="mm")

    # 底部信息条
    bar = 150
    d.rectangle([0, H - bar, W, H], fill=PAPER)
    d.text((left, H - bar + 40), "Track 1 · Apple Human-Centered Care", font=font(40), fill=INK)
    d.text((left, H - bar + 95), "Swift · SwiftUI · Core ML · Vision · AMD 图像生成 API", font=font(30), fill=INK2)
    d.text((W - left, H - bar + 75), "hackson-2026", font=font(36), fill=VERMILION, anchor="rm")

    poster.save(out_path)
    print(f"✓ 海报已保存：{out_path}")


def find_latin_font(preferred=None):
    if preferred and os.path.exists(preferred):
        return preferred
    for path in LATIN_CANDIDATES:
        if os.path.exists(path):
            return path
    return None


def wrap(draw, text, font, width):
    """按单词换行，每行不超过 width 像素"""
    lines, line = [], ""
    for word in text.split():
        trial = f"{line} {word}".strip()
        if draw.textlength(trial, font=font) <= width or not line:
            line = trial
        else:
            lines.append(line)
            line = word
    if line:
        lines.append(line)
    return lines


def compose_en(art_path, out_path, latin_font=None):
    """英文海报：版式和中文版同一套（竖排「物灵」在右上，文字在左），文字换成英文"""
    try:
        from PIL import Image, ImageDraw, ImageFont
    except ImportError:
        print("未安装 Pillow，跳过英文排版。")
        return
    found, latin = find_font(), find_latin_font(latin_font)
    if not found or not latin:
        print("找不到中文或英文字体，跳过英文排版。")
        return
    cjk_path, cjk_index = found

    W, H = 1800, 2700
    poster = Image.new("RGB", (W, H), PAPER)
    art = Image.open(art_path).convert("RGB")
    art_h = int(art.height * W / art.width)
    poster.paste(art.resize((W, art_h), Image.LANCZOS), (0, H - art_h))
    d = ImageDraw.Draw(poster)

    def cjk(size):
        return ImageFont.truetype(cjk_path, size, index=cjk_index)

    def serif(size, weight="Regular"):
        font = ImageFont.truetype(latin, size)
        try:   # 可变字体（比如 EB Garamond）按名字取字重
            font.set_variation_by_name(weight)
        except Exception:
            pass
        return font

    # 右上：竖排「物灵」，和中文版一样是这张海报的记号
    x = W - 330
    for i, ch in enumerate("物灵"):
        d.text((x, 150 + i * 270), ch, font=cjk(250), fill=INK)

    left, text_width = 140, W - 140 - 420
    # 名字
    spaced = " ".join("WULING")
    d.text((left, 168), spaced, font=serif(44, "Medium"), fill=VERMILION)
    # 标语：把记忆留下，把东西放下
    y = 250
    for line in ("Keep the memory.", "Let the thing go."):
        d.text((left, y), line, font=serif(108), fill=INK)
        y += 128
    # 说明
    y += 40
    body = serif(48)
    copy = ("Snap an old object you can’t bear to throw away and awaken its spirit. "
            "Say thank you and let it go, or pass it on, story and all, to someone new.")
    for line in wrap(d, copy, body, text_width):
        d.text((left, y), line, font=body, fill=INK2)
        y += 66
    # 三种仪式：同住 · 送别 · 传灵
    y += 34
    rituals = [("同住", "Live with it"), ("送别", "Let it go"), ("传灵", "Pass it on")]
    seal = 76
    cx = left
    for chinese, english in rituals:
        d.rounded_rectangle([cx, y, cx + seal, y + seal], radius=10, fill=VERMILION)
        d.rounded_rectangle([cx + 6, y + 6, cx + seal - 6, y + seal - 6], radius=7, outline=PAPER, width=3)
        sf = cjk(26)
        d.text((cx + seal / 2, y + seal * 0.32), chinese[0], font=sf, fill=PAPER, anchor="mm")
        d.text((cx + seal / 2, y + seal * 0.68), chinese[1], font=sf, fill=PAPER, anchor="mm")
        f = serif(40)
        d.text((cx + seal + 18, y + seal / 2), english, font=f, fill=INK, anchor="lm")
        cx += seal + 18 + d.textlength(english, font=f) + 44

    # 底部信息条
    bar = 150
    d.rectangle([0, H - bar, W, H], fill=PAPER)
    d.text((left, H - bar + 36), "Track 1 · Apple Human-Centered Care", font=serif(42), fill=INK)
    d.text((left, H - bar + 92), "Swift · SwiftUI · Metal · Core ML · Vision · AMD Image Generation API", font=serif(30), fill=INK2)
    d.text((W - left, H - bar + 75), "hackson-2026", font=serif(38), fill=VERMILION, anchor="rm")

    poster.save(out_path)
    print(f"✓ 英文海报已保存：{out_path}")


def main():
    parser = argparse.ArgumentParser(description="生成物灵项目海报")
    parser.add_argument("--art", help="已有插画路径，跳过 API 调用")
    parser.add_argument("--size", default="1024x1536", help="图像尺寸（默认 1024x1536，竖版）")
    parser.add_argument("--quality", default="high", help="画质 low / medium / high（默认 high，海报只生成一次）")
    parser.add_argument("--lang", default="both", choices=["zh", "en", "both"], help="排哪个语言的海报（默认中英文都排）")
    parser.add_argument("--latin-font", help="英文海报用的字体文件（默认 macOS 的 Baskerville，找不到再用其他衬线体）")
    args = parser.parse_args()

    os.makedirs(OUT_DIR, exist_ok=True)
    art_path = args.art
    if not art_path:
        cfg = load_config()
        art_path = os.path.join(OUT_DIR, "poster-art.png")
        with open(art_path, "wb") as f:
            f.write(generate_art(cfg, args.size, args.quality))
        print(f"✓ 插画已保存：{art_path}")
    if args.lang in ("zh", "both"):
        compose(art_path, os.path.join(OUT_DIR, "poster.png"))
    if args.lang in ("en", "both"):
        compose_en(art_path, os.path.join(OUT_DIR, "poster-en.png"), args.latin_font)


if __name__ == "__main__":
    main()
