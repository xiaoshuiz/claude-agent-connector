#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
ASSET_ROOT = ROOT / "Resources" / "Assets.xcassets"
ICONSET = ASSET_ROOT / "AppIcon.appiconset"


def lerp_color(c1: tuple[int, int, int], c2: tuple[int, int, int], t: float) -> tuple[int, int, int]:
    return (
        int(c1[0] + (c2[0] - c1[0]) * t),
        int(c1[1] + (c2[1] - c1[1]) * t),
        int(c1[2] + (c2[2] - c1[2]) * t),
    )


def draw_background(size: int) -> Image.Image:
    image = Image.new("RGBA", (size, size))
    px = image.load()

    top = (29, 56, 140)
    bottom = (89, 44, 180)
    glow = (24, 178, 255)

    for y in range(size):
        v = y / (size - 1)
        base = lerp_color(top, bottom, v)
        for x in range(size):
            u = x / (size - 1)
            dx = u - 0.28
            dy = v - 0.26
            glow_mix = max(0.0, 1.0 - (dx * dx + dy * dy) * 3.2)
            r = min(255, int(base[0] * (1 - glow_mix * 0.35) + glow[0] * glow_mix * 0.35))
            g = min(255, int(base[1] * (1 - glow_mix * 0.35) + glow[1] * glow_mix * 0.35))
            b = min(255, int(base[2] * (1 - glow_mix * 0.35) + glow[2] * glow_mix * 0.35))
            px[x, y] = (r, g, b, 255)

    # rounded clipping mask
    mask = Image.new("L", (size, size), 0)
    mask_draw = ImageDraw.Draw(mask)
    radius = int(size * 0.23)
    mask_draw.rounded_rectangle((0, 0, size - 1, size - 1), radius=radius, fill=255)
    image.putalpha(mask)
    return image


def draw_bubbles(canvas: Image.Image) -> None:
    size = canvas.size[0]
    overlay = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(overlay)

    left = (int(size * 0.14), int(size * 0.22), int(size * 0.62), int(size * 0.66))
    right = (int(size * 0.38), int(size * 0.34), int(size * 0.86), int(size * 0.78))
    left_r = int(size * 0.11)
    right_r = int(size * 0.11)

    d.rounded_rectangle(left, radius=left_r, fill=(22, 212, 255, 214))
    d.rounded_rectangle(right, radius=right_r, fill=(88, 240, 168, 220))

    # tails
    d.polygon(
        [
            (int(size * 0.25), int(size * 0.66)),
            (int(size * 0.23), int(size * 0.82)),
            (int(size * 0.39), int(size * 0.66)),
        ],
        fill=(22, 212, 255, 214),
    )
    d.polygon(
        [
            (int(size * 0.73), int(size * 0.78)),
            (int(size * 0.81), int(size * 0.88)),
            (int(size * 0.8), int(size * 0.73)),
        ],
        fill=(88, 240, 168, 220),
    )

    # connector chain in center
    chain_w = max(16, int(size * 0.04))
    d.arc(
        (
            int(size * 0.41),
            int(size * 0.44),
            int(size * 0.57),
            int(size * 0.60),
        ),
        start=15,
        end=330,
        fill=(255, 255, 255, 245),
        width=chain_w,
    )
    d.arc(
        (
            int(size * 0.50),
            int(size * 0.40),
            int(size * 0.66),
            int(size * 0.56),
        ),
        start=200,
        end=160,
        fill=(255, 255, 255, 245),
        width=chain_w,
    )

    # subtle spark lines
    center = (int(size * 0.52), int(size * 0.24))
    for offset in (-70, -30, 0, 30, 70):
        d.line(
            [
                (center[0] + offset, center[1]),
                (center[0] + int(offset * 0.7), center[1] + int(size * 0.07)),
            ],
            fill=(255, 255, 255, 110),
            width=max(2, int(size * 0.006)),
        )

    # border stroke
    inset = int(size * 0.01)
    d.rounded_rectangle(
        (inset, inset, size - inset - 1, size - inset - 1),
        radius=int(size * 0.22),
        outline=(255, 255, 255, 90),
        width=max(2, int(size * 0.008)),
    )

    shadow = overlay.filter(ImageFilter.GaussianBlur(radius=size * 0.01))
    canvas.alpha_composite(shadow)
    canvas.alpha_composite(overlay)


def save_icon_set(master: Image.Image) -> None:
    ASSET_ROOT.mkdir(parents=True, exist_ok=True)
    ICONSET.mkdir(parents=True, exist_ok=True)

    (ASSET_ROOT / "Contents.json").write_text(
        '{\n  "info": {\n    "author": "xcode",\n    "version": 1\n  }\n}\n',
        encoding="utf-8",
    )

    definitions = [
        ("icon_16x16.png", 16, "16x16", "1x"),
        ("icon_16x16@2x.png", 32, "16x16", "2x"),
        ("icon_32x32.png", 32, "32x32", "1x"),
        ("icon_32x32@2x.png", 64, "32x32", "2x"),
        ("icon_128x128.png", 128, "128x128", "1x"),
        ("icon_128x128@2x.png", 256, "128x128", "2x"),
        ("icon_256x256.png", 256, "256x256", "1x"),
        ("icon_256x256@2x.png", 512, "256x256", "2x"),
        ("icon_512x512.png", 512, "512x512", "1x"),
        ("icon_512x512@2x.png", 1024, "512x512", "2x"),
    ]

    image_entries: list[str] = []
    for filename, pixels, size, scale in definitions:
        resized = master.resize((pixels, pixels), Image.Resampling.LANCZOS)
        resized.save(ICONSET / filename, "PNG")
        image_entries.append(
            f'    {{"filename":"{filename}","idiom":"mac","scale":"{scale}","size":"{size}"}}'
        )

    contents = (
        "{\n"
        '  "images": [\n'
        + ",\n".join(image_entries)
        + '\n  ],\n  "info": {"author": "xcode", "version": 1}\n}\n'
    )
    (ICONSET / "Contents.json").write_text(contents, encoding="utf-8")


def main() -> None:
    master = draw_background(1024)
    draw_bubbles(master)
    save_icon_set(master)
    print(f"Generated icon assets at: {ICONSET}")


if __name__ == "__main__":
    main()
