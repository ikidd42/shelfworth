#!/usr/bin/env python3
"""Generate the Athenaeum app icon set and launch motif for Library.

Outputs (into Library/Library/Assets.xcassets):
  AppIcon.appiconset/AppIcon.png         1024x1024 default
  AppIcon.appiconset/AppIcon-dark.png    1024x1024 dark appearance
  AppIcon.appiconset/AppIcon-tinted.png  1024x1024 tinted appearance
  LaunchMotif.imageset/launch-motif.png  360x540 transparent
"""

from PIL import Image, ImageDraw, ImageFilter
import numpy as np
import os

ASSETS = "Library/Library/Assets.xcassets"
ICONSET = os.path.join(ASSETS, "AppIcon.appiconset")
MOTIFSET = os.path.join(ASSETS, "LaunchMotif.imageset")

# Athenaeum palette
GREEN_TOP = (0x35, 0x5A, 0x41)
GREEN_BOTTOM = (0x22, 0x36, 0x28)
ESPRESSO_TOP = (0x24, 0x1D, 0x15)
ESPRESSO_BOTTOM = (0x14, 0x0F, 0x09)
GILT = (0xE8, 0xD5, 0xA3)
GILT_DEEP = (0xC9, 0xAE, 0x74)

# Book cloth colorways (top, bottom)
OXBLOOD = ((0x84, 0x41, 0x33), (0x51, 0x25, 0x1C))
NAVY = ((0x39, 0x4D, 0x66), (0x21, 0x2E, 0x40))
OCHRE = ((0xB2, 0x83, 0x34), (0x74, 0x52, 0x1D))

# Marbled paper palettes (base, mid, vein, gilt) in 0..1 floats
MARBLE_FOREST = {
    "base": (0.91, 0.90, 0.79),
    "mid": (0.47, 0.59, 0.45),
    "vein": (0.11, 0.25, 0.18),
    "gilt": (0.83, 0.72, 0.42),
}
MARBLE_ESPRESSO = {
    "base": (0.42, 0.38, 0.30),
    "mid": (0.24, 0.30, 0.22),
    "vein": (0.08, 0.14, 0.10),
    "gilt": (0.55, 0.46, 0.28),
}


def _noise(res, size, seed):
    """Smooth value noise: random lattice upscaled with bicubic interpolation."""
    rng = np.random.default_rng(seed)
    small = (rng.random((res, res)) * 255).astype(np.uint8)
    img = Image.fromarray(small).resize((size, size), Image.BICUBIC)
    return np.asarray(img, dtype=np.float64) / 255.0


def _fbm(size, seed, octaves=4):
    total, amp, res = np.zeros((size, size)), 0.5, 4
    for i in range(octaves):
        total += amp * _noise(res, size, seed + i * 101)
        amp *= 0.5
        res *= 2
    return total


def marble_field(size, palette, seed):
    """Combed 'nonpareil' marbled paper, mirroring the in-app Swift renderer."""
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float64)
    scale = 6.0 / size
    x, y = xx * scale, yy * scale

    warp1 = _fbm(size, seed)
    warp2 = _fbm(size, seed ^ 0x9E37, octaves=3)
    periods = size / 12.0
    freq = periods * 2 * np.pi / 6.0

    t = 0.5 + 0.5 * np.sin(y * freq + x * 1.4 + warp1 * 6.0 + warp2 * 3.0)
    ridge = np.power(t, 0.65)

    def smoothstep(a, b, v):
        tt = np.clip((v - a) / (b - a), 0, 1)
        return tt * tt * (3 - 2 * tt)

    img = np.zeros((size, size, 3))
    for ch in range(3):
        c = np.full((size, size), palette["base"][ch])
        c = c + (palette["mid"][ch] - c) * smoothstep(0.50, 0.74, ridge)
        c = c + (palette["vein"][ch] - c) * smoothstep(0.76, 0.92, ridge)
        gold = smoothstep(0.955, 0.99, ridge) * 0.85
        c = c + (palette["gilt"][ch] - c) * gold
        # Paper grain
        grain = 0.965 + 0.07 * _noise(64, size, seed + 7)
        img[:, :, ch] = np.clip(c * grain, 0, 1)

    rgba = np.dstack([(img * 255).astype(np.uint8), np.full((size, size), 255, np.uint8)])
    return Image.fromarray(rgba, "RGBA")


def vignette(size, color, strength=0.4):
    """Darken edges radially for depth."""
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float64)
    cx = cy = (size - 1) / 2
    dist = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2) / (size * 0.72)
    alpha = np.clip((dist - 0.45) / 0.55, 0, 1) ** 1.6 * strength
    rgba = np.zeros((size, size, 4), np.uint8)
    rgba[:, :, 0] = color[0]
    rgba[:, :, 1] = color[1]
    rgba[:, :, 2] = color[2]
    rgba[:, :, 3] = (alpha * 255).astype(np.uint8)
    return Image.fromarray(rgba, "RGBA")


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def vertical_gradient(size, top, bottom):
    w, h = size
    img = Image.new("RGB", (w, h))
    px = img.load()
    for y in range(h):
        row = lerp(top, bottom, y / max(h - 1, 1))
        for x in range(w):
            px[x, y] = row
    return img


def cloth_texture(img, alpha=7, step=3):
    """Subtle horizontal weave lines over the cloth."""
    overlay = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(overlay)
    for y in range(0, img.size[1], step):
        d.line([(0, y), (img.size[0], y)], fill=(255, 255, 255, alpha), width=1)
    return Image.alpha_composite(img.convert("RGBA"), overlay)


def rounded_rect(draw, box, radius, fill=None, outline=None, width=1):
    draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)


def gilt_frame(img, inset, gilt=GILT, outer_w=5, inner_w=2, gap=14, alpha_outer=210, alpha_inner=120):
    d = ImageDraw.Draw(img, "RGBA")
    w, h = img.size
    rounded_rect(
        d,
        (inset, inset, w - inset, h - inset),
        radius=18,
        outline=gilt + (alpha_outer,),
        width=outer_w,
    )
    i2 = inset + gap + outer_w
    rounded_rect(
        d,
        (i2, i2, w - i2, h - i2),
        radius=12,
        outline=gilt + (alpha_inner,),
        width=inner_w,
    )


def draw_book(layer, x, y_top, width, height, cloth, gilt=GILT, radius=10):
    """One upright hardcover: cloth gradient, spine shading, gilt bands."""
    y_bottom = y_top + height
    book = vertical_gradient((width, height), cloth[0], cloth[1]).convert("RGBA")
    bd = ImageDraw.Draw(book, "RGBA")

    # Spine shading on the left edge + hairline highlight
    spine_w = max(8, width // 8)
    for i in range(spine_w):
        a = int(90 * (1 - i / spine_w))
        bd.line([(i, 0), (i, height)], fill=(0, 0, 0, a))
    bd.line([(spine_w, 0), (spine_w, height)], fill=(255, 255, 255, 60), width=2)

    # Gilt spine bands
    band = gilt + (230,)
    bd.rectangle((0, int(height * 0.12), width, int(height * 0.12) + 6), fill=band)
    bd.rectangle((0, int(height * 0.17), width, int(height * 0.17) + 3), fill=gilt + (140,))
    bd.rectangle((0, int(height * 0.86), width, int(height * 0.86) + 6), fill=band)
    bd.rectangle((0, int(height * 0.91), width, int(height * 0.91) + 3), fill=gilt + (140,))

    # Rounded corners mask
    mask = Image.new("L", (width, height), 0)
    md = ImageDraw.Draw(mask)
    md.rounded_rectangle((0, 0, width - 1, height - 1), radius=radius, fill=255)
    layer.paste(book, (x, y_top), mask)


def draw_books(size, scale=1.0, silhouettes=None):
    """Compose the three-book motif on a transparent layer."""
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    W, H = size
    books = [
        (int(150 * scale), int(560 * scale), OXBLOOD),
        (int(168 * scale), int(660 * scale), NAVY),
        (int(150 * scale), int(600 * scale), OCHRE),
    ]
    total_w = sum(b[0] for b in books) + int(56 * scale) * (len(books) - 1)
    x = (W - total_w) // 2
    tallest = max(b[1] for b in books)
    anchor_bottom = H // 2 + tallest // 2

    shadow_layer = Image.new("RGBA", size, (0, 0, 0, 0))
    for i, (bw, bh, cloth) in enumerate(books):
        y_top = anchor_bottom - bh
        if silhouettes is not None:
            d = ImageDraw.Draw(layer)
            d.rounded_rectangle((x, y_top, x + bw, y_top + bh), radius=int(10 * scale), fill=silhouettes)
        else:
            # soft drop shadow
            sh = Image.new("RGBA", size, (0, 0, 0, 0))
            ImageDraw.Draw(sh).rounded_rectangle(
                (x, y_top + 10, x + bw, y_top + bh + 10), radius=int(10 * scale), fill=(0, 0, 0, 110)
            )
            shadow_layer = Image.alpha_composite(shadow_layer, sh)
            draw_book(layer, x, y_top, bw, bh, cloth)
        x += bw + int(56 * scale)
    layer = Image.alpha_composite(shadow_layer.filter(ImageFilter.GaussianBlur(9)), layer)
    return layer


def icon_default(path):
    size = (1024, 1024)
    field = marble_field(1024, MARBLE_FOREST, seed=19)
    img = Image.alpha_composite(field, vignette(1024, (0x1B, 0x2C, 0x20), strength=0.45))
    gilt_frame(img, inset=64)
    books = draw_books(size, scale=1.0)
    img = Image.alpha_composite(img, books)
    img.convert("RGB").save(path)


def icon_dark(path):
    size = (1024, 1024)
    field = marble_field(1024, MARBLE_ESPRESSO, seed=42)
    img = Image.alpha_composite(field, vignette(1024, (0x0B, 0x08, 0x05), strength=0.55))
    gilt_frame(img, inset=64, gilt=GILT_DEEP, alpha_outer=230, alpha_inner=140)
    books = draw_books(size, scale=1.0)
    img = Image.alpha_composite(img, books)
    img.convert("RGB").save(path)


def icon_tinted(path):
    size = (1024, 1024)
    img = Image.new("RGBA", size, (0, 0, 0, 0))
    # Flat warm-cream silhouette the system tint can colorize
    d = ImageDraw.Draw(img, "RGBA")
    w, h = size
    inset = 64
    cream = (0xF0, 0xE7, 0xD5, 255)
    rounded_rect(d, (inset, inset, w - inset, h - inset), radius=18, outline=cream, width=5)
    i2 = inset + 14 + 5
    rounded_rect(d, (i2, i2, w - i2, h - i2), radius=12, outline=cream[:3] + (150,), width=2)
    books = draw_books(size, scale=1.0, silhouettes=cream)
    img = Image.alpha_composite(img, books)
    img.save(path)


def launch_motif(path):
    size = (360, 540)
    books = draw_books(size, scale=0.35)
    img = Image.new("RGBA", size, (0, 0, 0, 0))
    img = Image.alpha_composite(img, books)
    # Small gilt diamond below the books
    d = ImageDraw.Draw(img)
    cx, cy = size[0] // 2, size[1] - 60
    r = 7
    d.polygon([(cx, cy - r), (cx + r, cy), (cx, cy + r), (cx - r, cy)], fill=GILT + (230,))
    img.save(path)


if __name__ == "__main__":
    os.makedirs(MOTIFSET, exist_ok=True)
    icon_default(os.path.join(ICONSET, "AppIcon.png"))
    icon_dark(os.path.join(ICONSET, "AppIcon-dark.png"))
    icon_tinted(os.path.join(ICONSET, "AppIcon-tinted.png"))
    launch_motif(os.path.join(MOTIFSET, "launch-motif.png"))
    print("Generated icons + launch motif")
