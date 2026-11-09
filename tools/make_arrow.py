# Usage: python3 tools/make_arrow.py GoblinCompass/arrow.tga [preview.png]
# Draws GoblinCompass/arrow.tga: a white/grey chevron pointing up with a dark outline.
# White areas take the profession tint in-game (SetVertexColor); the outline stays dark.
import numpy as np, struct, sys
N, SS = 128, 4
poly = np.array([(64, 10), (114, 112), (64, 84), (14, 112)], float)  # tip, right wing, notch, left wing
OUT = 5.0  # outline width in px
g = (np.arange(N * SS) + 0.5) / SS
X, Y = np.meshgrid(g, g)
inside = np.zeros_like(X, bool)
d = np.full_like(X, 1e9)
for i in range(len(poly)):
    (x1, y1), (x2, y2) = poly[i], poly[(i + 1) % len(poly)]
    inside ^= ((y1 > Y) != (y2 > Y)) & (X < (x2 - x1) * (Y - y1) / (y2 - y1 + 1e-12) + x1)
    dx, dy = x2 - x1, y2 - y1
    t = np.clip(((X - x1) * dx + (Y - y1) * dy) / (dx * dx + dy * dy), 0, 1)
    d = np.minimum(d, np.hypot(X - (x1 + t * dx), Y - (y1 + t * dy)))
# shading: left half bright, right half darker (fake bevel), a little darker towards the tail
shade = np.where(X < 64, 1.0, 0.72) * (1.0 - 0.15 * (Y - 10) / 102)
val = np.where(d < OUT, 0.08, shade)
alpha = inside.astype(float)
def down(a): return a.reshape(N, SS, N, SS).mean(axis=(1, 3))
A = down(alpha)
V = down(val * alpha) / np.maximum(A, 1e-6)
rgb = (np.clip(V, 0, 1) * 255).astype(np.uint8)
a8 = (A * 255).astype(np.uint8)
out = sys.argv[1]
with open(out, "wb") as f:
    f.write(struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, N, N, 32, 0x28))  # top-left origin, 8-bit alpha
    px = np.dstack([rgb, rgb, rgb, a8])  # BGRA (grey so order doesn't matter)
    f.write(px.tobytes())
if len(sys.argv) > 2:  # preview sheet with the in-game tints on a sandy background
    from PIL import Image
    tints = [(0.95, 0.55, 0.2), (0.35, 0.9, 0.3), (0.3, 0.6, 1.0), (1.0, 0.82, 0.15)]
    sheet = Image.new("RGBA", (N * 4 + 50, N + 20), (196, 120, 60, 255))
    base = np.dstack([rgb, rgb, rgb]).astype(float) / 255
    for i, t in enumerate(tints):
        im = (base * np.array(t) * 255).astype(np.uint8)
        tile = Image.fromarray(np.dstack([im, a8]), "RGBA")
        sheet.alpha_composite(tile, (10 + i * (N + 10), 10))
    sheet.save(sys.argv[2])
