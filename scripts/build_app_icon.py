#!/usr/bin/env python3
"""Build Intelli-Expense's Liquid Glass AppIcon.icon package.

The source SVG keeps the selected option-2 concept as flat, centered artwork:
a receipt sheet, receipt marks, and scan-frame corners. This script exports
those pieces as transparent 1024x1024 layers and writes the Icon Composer
metadata so the system owns the background, lighting, masking, and appearances.

Usage:
    python3 scripts/build_app_icon.py
"""
from __future__ import annotations

import json
import re
from pathlib import Path

import cairosvg
from PIL import Image, ImageDraw

REPO = Path(__file__).resolve().parent.parent
SRC_SVG = REPO / "docs" / "assets" / "app-icon" / "intelli-expense-scan-receipt.svg"
ICON_DIR = REPO / "IntelliExpense" / "Resources" / "AppIcon.icon"
ASSETS_DIR = ICON_DIR / "Assets"
WELCOME_ICON_DIR = REPO / "IntelliExpense" / "Resources" / "Assets.xcassets" / "WelcomeAppIcon.imageset"
PREVIEW_DIR = REPO / "docs" / "assets" / "app-icon"
SIZE = 1024

LAYERS = [
    {
        "id": "receipt-sheet",
        "file": "receipt-sheet.png",
        "name": "Receipt sheet",
        "shadow": 0.18,
        "translucency": 0.08,
    },
    {
        "id": "receipt-details",
        "file": "receipt-details.png",
        "name": "Ledger marks",
        "shadow": 0.06,
        "translucency": 0.04,
    },
    {
        "id": "scan-frame",
        "file": "scan-frame.png",
        "name": "Scan frame",
        "shadow": 0.16,
        "translucency": 0.16,
    },
]

LIGHT_GRADIENT = ("#0D704B", "#063B2B")
DARK_GRADIENT = ("#061E17", "#0E4A35")


def extended_srgb(hex_color: str) -> str:
    raw = hex_color.removeprefix("#")
    if len(raw) != 6:
        raise ValueError(f"expected #RRGGBB color, got {hex_color!r}")
    r, g, b = (int(raw[i : i + 2], 16) / 255 for i in (0, 2, 4))
    return f"extended-srgb:{r:.5f},{g:.5f},{b:.5f},1.00000"


def rgb_tuple(hex_color: str) -> tuple[int, int, int]:
    raw = hex_color.removeprefix("#")
    return tuple(int(raw[i : i + 2], 16) for i in (0, 2, 4))


def extract_groups(svg_text: str) -> tuple[str, dict[str, str]]:
    svg_open_match = re.search(r"<svg\b[^>]*>", svg_text)
    if not svg_open_match:
        raise SystemExit(f"missing opening <svg> tag in {SRC_SVG}")

    groups: dict[str, str] = {}
    for match in re.finditer(r"<g\b(?P<attrs>[^>]*)>(?P<body>.*?)</g>", svg_text, flags=re.DOTALL):
        attrs = match.group("attrs")
        id_match = re.search(r'id="([^"]+)"', attrs)
        if id_match:
            groups[id_match.group(1)] = f"<g{attrs}>{match.group('body')}</g>"

    return svg_open_match.group(0), groups


def render_layer(svg_open: str, group: str, out: Path) -> None:
    doc = f"{svg_open}\n{group}\n</svg>"
    cairosvg.svg2png(
        bytestring=doc.encode("utf-8"),
        write_to=str(out),
        output_width=SIZE,
        output_height=SIZE,
        background_color="rgba(0,0,0,0)",
    )


def build_icon_json() -> dict:
    gradient_orientation = {"start": {"x": 0.12, "y": 0.06}, "stop": {"x": 0.88, "y": 0.96}}
    groups = []
    for layer in LAYERS:
        groups.append(
            {
                "name": layer["name"],
                "layers": [{"image-name": layer["file"], "name": layer["name"]}],
                "lighting": "individual",
                "specular": True,
                "shadow": {"kind": "neutral", "opacity": layer["shadow"]},
                "translucency": {"enabled": True, "value": layer["translucency"]},
            }
        )

    return {
        "fill": {
            "linear-gradient": [extended_srgb(color) for color in LIGHT_GRADIENT],
            "orientation": gradient_orientation,
        },
        "fill-specializations": [
            {
                "appearance": "dark",
                "value": {
                    "linear-gradient": [extended_srgb(color) for color in DARK_GRADIENT],
                    "orientation": gradient_orientation,
                },
            },
            {"appearance": "tinted", "value": "automatic"},
        ],
        "groups": groups,
        "supported-platforms": {"squares": "shared"},
    }


def gradient_background(colors: tuple[str, str]) -> Image.Image:
    top, bottom = (rgb_tuple(colors[0]), rgb_tuple(colors[1]))
    image = Image.new("RGB", (SIZE, SIZE))
    pixels = image.load()
    for y in range(SIZE):
        for x in range(SIZE):
            t = (x + y) / (2 * (SIZE - 1))
            pixels[x, y] = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
    return image.convert("RGBA")


def squircle_preview(layer_pngs: list[Path], out: Path, colors: tuple[str, str]) -> None:
    preview = gradient_background(colors)
    for layer_png in layer_pngs:
        preview.alpha_composite(Image.open(layer_png).convert("RGBA"))

    mask = Image.new("L", (SIZE, SIZE), 0)
    radius = int(SIZE * 0.2237)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, SIZE - 1, SIZE - 1], radius=radius, fill=255)
    preview.putalpha(mask)
    preview.save(out)


def write_welcome_icon_imageset(light_preview: Path, dark_preview: Path) -> None:
    WELCOME_ICON_DIR.mkdir(parents=True, exist_ok=True)
    light_out = WELCOME_ICON_DIR / "welcome-app-icon.png"
    dark_out = WELCOME_ICON_DIR / "welcome-app-icon-dark.png"
    Image.open(light_preview).save(light_out)
    Image.open(dark_preview).save(dark_out)
    contents = {
        "images": [
            {
                "filename": light_out.name,
                "idiom": "universal",
                "scale": "1x",
            },
            {
                "appearances": [
                    {
                        "appearance": "luminosity",
                        "value": "dark",
                    }
                ],
                "filename": dark_out.name,
                "idiom": "universal",
                "scale": "1x",
            },
        ],
        "info": {"author": "xcode", "version": 1},
    }
    (WELCOME_ICON_DIR / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")
    verify_png(light_out)
    verify_png(dark_out)


def verify_png(path: Path) -> None:
    with Image.open(path) as image:
        if image.size != (SIZE, SIZE):
            raise SystemExit(f"{path} is {image.size}, expected {(SIZE, SIZE)}")
        if image.mode != "RGBA":
            raise SystemExit(f"{path} is {image.mode}, expected RGBA")


def main() -> None:
    svg_open, groups = extract_groups(SRC_SVG.read_text())
    ASSETS_DIR.mkdir(parents=True, exist_ok=True)

    rendered: list[Path] = []
    for layer in LAYERS:
        layer_id = layer["id"]
        if layer_id not in groups:
            raise SystemExit(f"missing group id={layer_id!r} in {SRC_SVG}")
        out = ASSETS_DIR / layer["file"]
        render_layer(svg_open, groups[layer_id], out)
        verify_png(out)
        rendered.append(out)

    icon_json = ICON_DIR / "icon.json"
    icon_json.write_text(json.dumps(build_icon_json(), indent=2) + "\n")

    PREVIEW_DIR.mkdir(parents=True, exist_ok=True)
    light_preview = PREVIEW_DIR / "intelli-expense-appicon-preview-default.png"
    dark_preview = PREVIEW_DIR / "intelli-expense-appicon-preview-dark.png"
    squircle_preview(rendered, light_preview, LIGHT_GRADIENT)
    squircle_preview(rendered, dark_preview, DARK_GRADIENT)
    write_welcome_icon_imageset(light_preview, dark_preview)

    print("layers:", *(str(path) for path in rendered))
    print("icon.json:", icon_json)
    print("previews:", light_preview, dark_preview)
    print("welcome imageset:", WELCOME_ICON_DIR)


if __name__ == "__main__":
    main()
