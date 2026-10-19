# Generates assets/icon.png and assets/icon_fg.png for the app launcher icon.
import math, os
from PIL import Image, ImageDraw

S = 2048  # supersample, downscaled to 1024 at the end

def glyph(size):
    """White notebook page + pencil + sparkle on a transparent layer (unit coords)."""
    im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    u = lambda v: v * size
    # page shadow + page
    d.rounded_rectangle([u(0.25), u(0.22), u(0.72), u(0.82)], radius=u(0.05), fill=(0, 0, 0, 45))
    d.rounded_rectangle([u(0.25), u(0.20), u(0.72), u(0.80)], radius=u(0.05), fill=(255, 255, 255, 255))
    for y, x2 in [(0.34, 0.64), (0.44, 0.64), (0.54, 0.64), (0.64, 0.50)]:
        d.rounded_rectangle([u(0.33), u(y) - u(0.012), u(x2), u(y) + u(0.012)], radius=u(0.012), fill=(199, 210, 254, 255))
    # pencil
    tip = (0.58, 0.80); end = (0.86, 0.38)
    dx, dy = end[0] - tip[0], end[1] - tip[1]
    L = math.hypot(dx, dy); dx, dy = dx / L, dy / L
    nx, ny = -dy, dx
    hw = 0.04
    def P(t, w):
        return (u(tip[0] + dx * t + nx * w), u(tip[1] + dy * t + ny * w))
    d.polygon([P(0, 0), P(0.12, hw), P(0.12, -hw)], fill=(253, 224, 171, 255))
    d.polygon([P(0, 0), P(0.045, hw * 0.35), P(0.045, -hw * 0.35)], fill=(30, 41, 59, 255))
    d.polygon([P(0.12, hw), P(0.44, hw), P(0.44, -hw), P(0.12, -hw)], fill=(251, 191, 36, 255))
    d.polygon([P(0.44, hw), P(0.50, hw), P(0.50, -hw), P(0.44, -hw)], fill=(244, 114, 182, 255))
    # sparkle
    cx, cy, R, r = u(0.79), u(0.24), u(0.095), u(0.026)
    pts = []
    for i in range(8):
        ang = math.pi / 4 * i - math.pi / 2
        rad = R if i % 2 == 0 else r
        pts.append((cx + rad * math.cos(ang), cy + rad * math.sin(ang)))
    d.polygon(pts, fill=(255, 255, 255, 255))
    return im

def gradient(size):
    im = Image.new("RGBA", (size, size))
    px = im.load()
    c1, c2 = (79, 70, 229), (147, 51, 234)
    for y in range(size):
        for x in range(size):
            t = (x + y) / (2 * size - 2)
            px[x, y] = tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3)) + (255,)
    return im

os.makedirs("assets", exist_ok=True)
g = glyph(S)
bg = gradient(512).resize((S, S), Image.BILINEAR)
icon = Image.alpha_composite(bg, g).resize((1024, 1024), Image.LANCZOS)
icon.save("assets/icon.png")

# adaptive foreground: glyph scaled into the safe zone on a transparent canvas
fg = Image.new("RGBA", (S, S), (0, 0, 0, 0))
small = g.resize((int(S * 0.62), int(S * 0.62)), Image.LANCZOS)
fg.paste(small, ((S - small.width) // 2, (S - small.height) // 2), small)
fg.resize((1024, 1024), Image.LANCZOS).save("assets/icon_fg.png")
print("icons written")
