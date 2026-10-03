#!/usr/bin/env python3
"""Cut the six houses out of svg/houses.jpg into transparent PNGs for the game.

    python3 scripts/cut_houses.py      # writes game/assets/images/houses/*.png

Background: a flood fill from each panel's border through pixels close to that
row's sky colour (the sky is a vertical gradient), so a slate roof as dark as the
sky survives when the house's outline encloses it. Base plate, fences, leaves and
stray props (candy, pumpkins, the lamp): a hand-traced keep-polygon per house that
follows the foundation's V and the outer walls. Re-trace KEEP if the sheet changes.
"""
import os
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as ndi

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / 'svg' / 'houses.jpg'
OUT = str(ROOT / 'game' / 'assets' / 'images' / 'houses') + '/'
HEIGHT = 480  # output height in px

# panel boxes in the sheet: x0, y0, x1, y1 (inside the divider lines)
PANELS = {  # x0, y0, x1, y1 in the sheet
    'house_a': (4, 120, 762, 964),
    'cottage_c': (774, 120, 1532, 964),
    'house_b': (4, 979, 875, 1837),
    'narrow_d': (889, 979, 1532, 1837),
    'church': (4, 1852, 875, 2724),
    'cottage_e': (889, 1852, 1532, 2724),
}


IM = np.asarray(Image.open(SRC).convert('RGB')).astype(np.float32)

# keep-polygons in panel-crop pixels, traced on the grid renders
KEEP = {
    'house_a': [(100, 0), (680, 0), (680, 370), (630, 370), (630, 510), (602, 522), (602, 612),
                (420, 708), (198, 652), (196, 545), (140, 515), (135, 370), (100, 370)],
    'cottage_c': [(175, 0), (680, 0), (680, 430), (637, 430), (637, 628), (452, 728), (305, 703),
                  (218, 662), (213, 430), (175, 430)],
    'house_b': [(170, 30), (700, 30), (700, 470), (680, 470), (678, 600), (650, 642), (566, 658),
                (470, 692), (362, 657), (240, 614), (184, 584), (182, 290), (170, 290)],
    'narrow_d': [(246, 186), (330, 186), (330, 40), (445, 40), (445, 140), (545, 455), (520, 462),
                 (518, 722), (398, 750), (260, 730), (182, 696), (178, 470), (140, 462)],
    'church': [(140, 0), (662, 0), (662, 645), (602, 690), (602, 734), (512, 734), (396, 770),
               (150, 662), (146, 340), (140, 340)],
    'cottage_e': [(60, 0), (545, 0), (545, 468), (505, 468), (503, 640), (462, 662), (462, 702),
                  (390, 702), (305, 740), (110, 657), (107, 470), (60, 470)],
}


def background(p, tol=30):
    edge = np.concatenate([p[:, :14], p[:, -14:]], axis=1)
    bg = ndi.median_filter(np.median(edge, axis=1), size=(15, 1))
    near = np.linalg.norm(p - bg[:, None, :], axis=2) < tol
    near = ndi.binary_opening(near, iterations=1)
    lab, _ = ndi.label(near)
    border = np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))
    return np.isin(lab, border[border > 0])


def cut(name):
    x0, y0, x1, y1 = PANELS[name]
    p = IM[y0:y1, x0:x1]
    h, w, _ = p.shape
    poly = Image.new('L', (w, h), 0)
    ImageDraw.Draw(poly).polygon(KEEP[name], fill=255)
    keep = (np.asarray(poly) > 0) & ~background(p)
    # the house is the biggest piece; drop stars and crumbs, fill pinholes
    lab, n = ndi.label(keep)
    sizes = ndi.sum(keep, lab, range(1, n + 1))
    keep = ndi.binary_fill_holes(lab == (np.argmax(sizes) + 1))
    # a soft ~1.5 px edge so the cut does not alias when scaled down
    alpha = ndi.gaussian_filter(keep.astype(np.float32), 0.8)
    alpha = np.clip((alpha - 0.15) / 0.7, 0, 1)
    ys, xs = np.nonzero(alpha > 0.02)
    bx0, bx1, by0, by1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
    rgba = np.dstack([p, alpha * 255]).astype(np.uint8)[by0:by1, bx0:bx1]
    img = Image.fromarray(rgba, 'RGBA')
    # the game draws each into a ~480 px tall atlas cell; no need to ship more
    scale = HEIGHT / img.height
    img = img.resize((round(img.width * scale), HEIGHT), Image.LANCZOS)
    img.save(OUT + name + '.png', optimize=True)
    return img



if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    for name in KEEP:
        img = cut(name)
        print('%-10s %dx%d' % (name, img.width, img.height))
