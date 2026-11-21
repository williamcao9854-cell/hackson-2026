import random, sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter
out = sys.argv[1]
N = 1024
PAPER = (0xF4, 0xF0, 0xE8); VERM = (0xC8, 0x44, 0x2F)
img = Image.new("RGB", (N, N), PAPER)
d = ImageDraw.Draw(img)
rng = random.Random(20261121)
# paper fibers
for _ in range(1400):
    x, y = rng.random()*N, rng.random()*N
    l = 6 + rng.random()*22; import math; a = rng.random()*math.pi
    c = tuple(int(v*(0.9+rng.random()*0.06)) for v in (0xC9,0xBE,0xAA))
    d.line([(x,y),(x+math.cos(a)*l, y+math.sin(a)*l)], fill=c+(0,), width=1)
img = Image.blend(Image.new("RGB",(N,N),PAPER), img, 0.16)

# seal
S = 560; x0 = (N-S)//2; y0 = (N-S)//2
seal = Image.new("L", (S, S), 0)
sd = ImageDraw.Draw(seal)
sd.rounded_rectangle([0,0,S-1,S-1], radius=int(S*0.12), fill=255)
# inner border cut out
b = int(S*0.07); w = int(S*0.028)
sd.rounded_rectangle([b,b,S-1-b,S-1-b], radius=int(S*0.08), outline=0, width=w)
font = ImageFont.truetype("/usr/share/fonts/opentype/noto/NotoSerifCJK-Black.ttc", int(S*0.36), index=0) if __import__('os').path.exists("/usr/share/fonts/opentype/noto/NotoSerifCJK-Black.ttc") else ImageFont.truetype("/usr/share/fonts/opentype/noto/NotoSerifCJK-Bold.ttc", int(S*0.36), index=0)
for ch, cy in (("物", 0.31), ("灵", 0.69)):
    bbox = sd.textbbox((0,0), ch, font=font)
    tw, th = bbox[2]-bbox[0], bbox[3]-bbox[1]
    sd.text((S/2 - tw/2 - bbox[0], S*cy - th/2 - bbox[1]), ch, font=font, fill=0)
# grain: erase specks
for _ in range(520):
    r = 1 + rng.random()*4
    px, py = rng.random()*S, rng.random()*S
    sd.ellipse([px, py, px+r, py+r], fill=int(255*(0.35+rng.random()*0.4)) if rng.random()<0.5 else None)
# rough edges
edge = Image.new("L", (S,S), 255); ed = ImageDraw.Draw(edge)
for _ in range(500):
    side = rng.randrange(4); t = rng.random()*S; r = 2+rng.random()*7
    px, py = [(t,0),(t,S),(0,t),(S,t)][side]
    ed.ellipse([px-r,py-r,px+r,py+r], fill=0)
from PIL import ImageChops
seal = ImageChops.multiply(seal, edge).filter(ImageFilter.GaussianBlur(0.8))
P = 80
padded = Image.new("L", (S+2*P, S+2*P), 0); padded.paste(seal, (P, P))
padded = padded.rotate(-4, resample=Image.BICUBIC, expand=False)
color = Image.new("RGB", padded.size, VERM)
img.paste(color, (x0-P, y0-P), padded)
img.save(out)
print("saved", out, img.size)
