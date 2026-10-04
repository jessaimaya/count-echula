#!/usr/bin/env python3
"""Make the finale's castle art for the game from svg/castle.png and svg/door.svg.

    python3 scripts/cut_castle.py      # writes game/assets/images/castle/*.png

castle.png: the castle with its gate arch cut out (transparent), so the portcullis
and the lit hall behind it (world.luau, the finale) show through the opening. The
painted portcullis in the source goes with the cut. The arch is traced against the
light purple frame around it: the pointed top row by row, the straight sides below
the springline at a fixed width.
door.png: svg/door.svg (the portcullis) rendered with rsvg-convert.
"""
import subprocess
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'game' / 'assets' / 'images' / 'castle'
CASTLE_H = 1024  # output heights in px (world.luau ATLAS_RECTS)
DOOR_H = 512

CX = 985  # the arch's center line in the source
APEX, SPRING = 990, 1210  # its point and springline (source rows)
SIDES = (750, 1216)  # the straight jambs below the springline


def light(p):
    r, g, b = p[:3]
    return 0x56 <= r <= 0x66 and 0x34 <= g <= 0x42 and 0x7C <= b <= 0x8C


def cut_arch(im):
    px = im.load()
    w, h = im.size
    for y in range(APEX, h):
        if y < SPRING:
            if light(px[CX, y]):
                continue
            l = CX
            while l > SIDES[0] - 10 and not light(px[l - 1, y]):
                l -= 1
            r = CX
            while r < SIDES[1] + 10 and not light(px[r + 1, y]):
                r += 1
        else:
            l, r = SIDES
        for x in range(l, r + 1):
            px[x, y] = (0, 0, 0, 0)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    im = Image.open(ROOT / 'svg' / 'castle.png').convert('RGBA')
    cut_arch(im)
    w = round(im.width * CASTLE_H / im.height)
    im.resize((w, CASTLE_H), Image.LANCZOS).save(OUT / 'castle.png', optimize=True)
    print('castle.png', w, CASTLE_H, 'arch x %.4f-%.4f top %.4f (fractions)' % (
        SIDES[0] / im.width, (SIDES[1] + 1) / im.width, APEX / im.height))

    subprocess.run(['rsvg-convert', '-h', str(DOOR_H), '-o', str(OUT / 'door.png'),
                    str(ROOT / 'svg' / 'door.svg')], check=True)
    door = Image.open(OUT / 'door.png')
    print('door.png', door.width, door.height)


if __name__ == '__main__':
    main()
