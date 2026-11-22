#!/usr/bin/env python3
"""
生成比赛要求的项目海报：调用 AMD 图像生成 API 画插画，再排版成竖版海报。

用法（在仓库根目录）：
    python3 -m pip install pillow          # 只需一次
    python3 tools/generate_poster.py       # 调 API 生成插画（默认 1024x1536、high 画质）+ 排版
    python3 tools/generate_poster.py --art posters/poster-art.png   # 已有插画，只重新排版

API 配置读取 Wuling/Resources/Secrets.plist（与 App 共用，不会提交到 Git）。
输出：posters/poster-art.png（API 原图）、posters/poster.png（排版后的海报）。
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


def main():
    parser = argparse.ArgumentParser(description="生成物灵项目海报")
    parser.add_argument("--art", help="已有插画路径，跳过 API 调用")
    parser.add_argument("--size", default="1024x1536", help="图像尺寸（默认 1024x1536，竖版）")
    parser.add_argument("--quality", default="high", help="画质 low / medium / high（默认 high，海报只生成一次）")
    args = parser.parse_args()

    os.makedirs(OUT_DIR, exist_ok=True)
    art_path = args.art
    if not art_path:
        cfg = load_config()
        art_path = os.path.join(OUT_DIR, "poster-art.png")
        with open(art_path, "wb") as f:
            f.write(generate_art(cfg, args.size, args.quality))
        print(f"✓ 插画已保存：{art_path}")
    compose(art_path, os.path.join(OUT_DIR, "poster.png"))


if __name__ == "__main__":
    main()
