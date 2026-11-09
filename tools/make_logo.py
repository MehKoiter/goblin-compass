# Usage: python3 tools/make_logo.py media/logo.png
# Draws the CurseForge project logo: a brass compass on goblin green, with the
# addon's own chevron arrow (same shape as GoblinCompass/arrow.tga) as the needle.
import math, sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter

OUT, SS = 512, 4
N = OUT * SS
C = N / 2

def lerp(a, b, t): return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))

img = Image.new("RGBA", (N, N), (0, 0, 0, 0))

# rounded-square background with a radial goblin-green glow
bg = Image.new("RGBA", (N, N))
px = bg.load()
inner, outer = (58, 112, 52), (14, 34, 18)
for y in range(0, N, 4):
    for x in range(0, N, 4):
        t = min(1, math.hypot(x - C, y - C * 0.9) / (N * 0.68))
        c = lerp(inner, outer, t) + (255,)
        for dy in range(4):
            for dx in range(4):
                px[x + dx, y + dy] = c
mask = Image.new("L", (N, N), 0)
ImageDraw.Draw(mask).rounded_rectangle((0, 0, N - 1, N - 1), radius=N * 0.18, fill=255)
img.paste(bg, (0, 0), mask)

d = ImageDraw.Draw(img)
R = N * 0.40

# drop shadow under the compass
sh = Image.new("RGBA", (N, N), (0, 0, 0, 0))
ImageDraw.Draw(sh).ellipse((C - R, C - R + N * 0.02, C + R, C + R + N * 0.03), fill=(0, 0, 0, 150))
img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(N * 0.02)))
d = ImageDraw.Draw(img)

# brass ring: concentric bands from dark to light to dark
bands = [(1.00, (92, 58, 18)), (0.985, (196, 140, 48)), (0.955, (246, 206, 110)),
         (0.925, (214, 160, 60)), (0.885, (120, 76, 22)), (0.865, (40, 30, 22))]
for f, col in bands:
    r = R * f
    d.ellipse((C - r, C - r, C + r, C + r), fill=col)
# compass face: dark parchment-brown
face = R * 0.85
for i in range(40):
    t = i / 39
    r = face * (1 - t * 0.999)
    d.ellipse((C - r, C - r, C + r, C + r), fill=lerp((34, 30, 26), (70, 58, 42), t))

# tick marks
for k in range(72):
    a = math.radians(k * 5)
    long = k % 18 == 0
    mid = k % 9 == 0
    r1 = face * (0.80 if long else 0.86 if mid else 0.91)
    r2 = face * 0.97
    w = int(N * (0.010 if long else 0.006 if mid else 0.004))
    col = (240, 200, 110) if (long or mid) else (170, 140, 90)
    d.line((C + math.sin(a) * r1, C - math.cos(a) * r1, C + math.sin(a) * r2, C - math.cos(a) * r2), fill=col, width=w)

# small profession-colored chevrons at E/S/W, "N" at the top
COLORS = {"Mining": (255, 128, 26), "Herbalism": (90, 230, 76), "Fishing": (76, 153, 255), "Treasure": (255, 210, 38)}

OUTER = [(0, -1.0), (0.98, 1.0), (0, 0.46), (-0.98, 1.0)]   # tip, right wing, notch, left wing
INNER = [(0, -0.78), (0.79, 0.86), (0, 0.40), (-0.79, 0.86)]  # same, inset to leave a dark outline

def poly_at(cx, cy, size, angle, pts):
    ca, sa = math.cos(angle), math.sin(angle)
    return [(cx + p[0] * size * 0.5 * ca - p[1] * size * 0.5 * sa, cy + p[0] * size * 0.5 * sa + p[1] * size * 0.5 * ca) for p in pts]

def chevron(draw, cx, cy, size, angle, color):
    draw.polygon(poly_at(cx, cy, size, angle, OUTER), fill=(14, 10, 8))
    tip, rw, notch, lw = poly_at(cx, cy, size, angle, INNER)
    draw.polygon([tip, notch, lw], fill=color)                                   # left half bright
    draw.polygon([tip, rw, notch], fill=tuple(int(c * 0.68) for c in color))   # right half shaded

for ang, prof in ((90, "Herbalism"), (180, "Fishing"), (270, "Treasure")):
    a = math.radians(ang)
    r = face * 0.70
    chevron(d, C + math.sin(a) * r, C - math.cos(a) * r, N * 0.085, a, COLORS[prof])

font = ImageFont.truetype("/usr/share/fonts/truetype/crosextra/Caladea-Bold.ttf", int(N * 0.11))
tw = d.textlength("N", font=font)
d.text((C - tw / 2 + N * 0.004, C - face * 0.58 - N * 0.062 + N * 0.006), "N", font=font, fill=(0, 0, 0, 160))
d.text((C - tw / 2, C - face * 0.58 - N * 0.062), "N", font=font, fill=(250, 214, 120))

# the needle: big Mining-orange chevron pointing north-east, pivoting on the centre
ang = math.radians(45)
size = N * 0.30
# shift so the pivot sits between tip and notch rather than at the shape's box centre
cx, cy = C - math.sin(ang) * size * 0.5 * -0.05, C + math.cos(ang) * size * 0.5 * -0.05
sh2 = Image.new("RGBA", (N, N), (0, 0, 0, 0))
ImageDraw.Draw(sh2).polygon(poly_at(cx + N * 0.012, cy + N * 0.02, size, ang, OUTER), fill=(0, 0, 0, 170))
img.alpha_composite(sh2.filter(ImageFilter.GaussianBlur(N * 0.012)))
d = ImageDraw.Draw(img)
chevron(d, cx, cy, size, ang, COLORS["Mining"])
# brass pivot cap
for f, col in ((0.030, (92, 58, 18)), (0.025, (230, 184, 90)), (0.013, (255, 236, 170))):
    r = N * f
    d.ellipse((C - r, C - r, C + r, C + r), fill=col)

img = img.resize((OUT, OUT), Image.LANCZOS)
img.save(sys.argv[1])
