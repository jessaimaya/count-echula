#!/usr/bin/env python3
"""Convert the Inkscape SVGs in svg/ into Rive artboards (game/art.rml).

Every path and ellipse becomes a Shape with a PointsPath of real vertices in
artboard space, so the art stays vector and editable in the Rive Editor.
SVG groups listed in an asset's `nodes` become Nodes pivoted where the config
says, so they can be animated (Echula's wings, ears and headphone cups).

    python3 scripts/svg2rml.py      # rewrites game/art.rml

Re-run after editing an SVG. Element ids in the SVGs are the hooks: keep them.
"""

import math
import re
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
# Artboards other artboards nest (Echula sits in "Echula Intro", game/intro.rml).
COMPONENTS = {'Echula'}
COMPONENT = ' isComponent="true"'
SVG = '{http://www.w3.org/2000/svg}'

# --------------------------------------------------------------- matrices

def mul(m, n):
    a, b, c, d, e, f = m
    A, B, C, D, E, F = n
    return (a * A + c * B, b * A + d * B, a * C + c * D, b * C + d * D, a * E + c * F + e, b * E + d * F + f)


def apply(m, p):
    a, b, c, d, e, f = m
    return (a * p[0] + c * p[1] + e, b * p[0] + d * p[1] + f)


IDENT = (1, 0, 0, 1, 0, 0)


def parse_transform(s):
    m = IDENT
    for name, args in re.findall(r'(\w+)\s*\(([^)]*)\)', s or ''):
        v = [float(x) for x in re.split(r'[\s,]+', args.strip()) if x]
        if name == 'translate':
            t = (1, 0, 0, 1, v[0], v[1] if len(v) > 1 else 0)
        elif name == 'scale':
            t = (v[0], 0, 0, v[1] if len(v) > 1 else v[0], 0, 0)
        elif name == 'rotate':
            r = math.radians(v[0])
            t = (math.cos(r), math.sin(r), -math.sin(r), math.cos(r), 0, 0)
            if len(v) == 3:
                t = mul(mul((1, 0, 0, 1, v[1], v[2]), t), (1, 0, 0, 1, -v[1], -v[2]))
        elif name == 'matrix':
            t = tuple(v)
        else:
            raise ValueError('transform ' + name)
        m = mul(m, t)
    return m

# ------------------------------------------------------------------ paths
# A subpath is (start, [segments], closed); a segment is ('L', p) or ('C', c1, c2, p).

def arc_to_cubics(p0, rx, ry, phi, large, sweep, p1):
    if rx == 0 or ry == 0:
        return [('L', p1)]
    rx, ry = abs(rx), abs(ry)
    cp, sp = math.cos(phi), math.sin(phi)
    dx, dy = (p0[0] - p1[0]) / 2, (p0[1] - p1[1]) / 2
    x1 = cp * dx + sp * dy
    y1 = -sp * dx + cp * dy
    lam = x1 * x1 / (rx * rx) + y1 * y1 / (ry * ry)
    if lam > 1:
        rx *= math.sqrt(lam)
        ry *= math.sqrt(lam)
    num = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
    den = rx * rx * y1 * y1 + ry * ry * x1 * x1
    k = math.sqrt(max(0, num / den)) * (-1 if large == sweep else 1)
    cxp, cyp = k * rx * y1 / ry, -k * ry * x1 / rx
    cx = cp * cxp - sp * cyp + (p0[0] + p1[0]) / 2
    cy = sp * cxp + cp * cyp + (p0[1] + p1[1]) / 2

    def ang(ux, uy, vx, vy):
        a = math.atan2(ux * vy - uy * vx, ux * vx + uy * vy)
        return a

    t1 = ang(1, 0, (x1 - cxp) / rx, (y1 - cyp) / ry)
    dt = ang((x1 - cxp) / rx, (y1 - cyp) / ry, (-x1 - cxp) / rx, (-y1 - cyp) / ry)
    if not sweep and dt > 0:
        dt -= 2 * math.pi
    elif sweep and dt < 0:
        dt += 2 * math.pi
    n = max(1, math.ceil(abs(dt) / (math.pi / 2) - 1e-9))
    d = dt / n
    kk = 4 / 3 * math.tan(d / 4)

    def pt(t):
        x, y = rx * math.cos(t), ry * math.sin(t)
        return (cp * x - sp * y + cx, sp * x + cp * y + cy)

    def dv(t):
        x, y = -rx * math.sin(t), ry * math.cos(t)
        return (cp * x - sp * y, sp * x + cp * y)

    segs = []
    for i in range(n):
        a, b = t1 + i * d, t1 + (i + 1) * d
        pa, pb, da, db = pt(a), pt(b), dv(a), dv(b)
        segs.append(('C', (pa[0] + kk * da[0], pa[1] + kk * da[1]), (pb[0] - kk * db[0], pb[1] - kk * db[1]), pb))
    segs[-1] = ('C', segs[-1][1], segs[-1][2], p1)
    return segs


def parse_d(d):
    toks = re.findall(r'[MmLlHhVvCcSsAaZz]|[-+]?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?', d)
    i = 0
    subs = []
    cur = (0.0, 0.0)
    start = cur
    segs = None
    cmd = None
    last_c2 = None

    def num():
        nonlocal i
        v = float(toks[i])
        i += 1
        return v

    def flag():
        # arc flags may be packed ("01") in some writers; Inkscape spaces them
        return num() != 0

    while i < len(toks):
        if re.match(r'[A-Za-z]', toks[i]):
            cmd = toks[i]
            i += 1
        rel = cmd.islower()
        C = cmd.upper()
        ox, oy = cur if rel else (0.0, 0.0)
        if C == 'M':
            p = (num() + ox, num() + oy)
            if segs is not None:
                subs.append((start, segs, False))
            segs = []
            start = cur = p
            cmd = 'l' if rel else 'L'
            last_c2 = None
        elif C == 'L':
            p = (num() + ox, num() + oy)
            segs.append(('L', p))
            cur = p
            last_c2 = None
        elif C == 'H':
            p = (num() + ox, cur[1])
            segs.append(('L', p))
            cur = p
            last_c2 = None
        elif C == 'V':
            p = (cur[0], num() + (cur[1] if rel else 0.0))
            segs.append(('L', p))
            cur = p
            last_c2 = None
        elif C == 'C':
            c1 = (num() + ox, num() + oy)
            c2 = (num() + ox, num() + oy)
            p = (num() + ox, num() + oy)
            segs.append(('C', c1, c2, p))
            cur = p
            last_c2 = c2
        elif C == 'S':
            c1 = (2 * cur[0] - last_c2[0], 2 * cur[1] - last_c2[1]) if last_c2 else cur
            c2 = (num() + ox, num() + oy)
            p = (num() + ox, num() + oy)
            segs.append(('C', c1, c2, p))
            cur = p
            last_c2 = c2
        elif C == 'A':
            rx, ry, rot = num(), num(), num()
            large, sweep = flag(), flag()
            p = (num() + ox, num() + oy)
            segs.extend(arc_to_cubics(cur, rx, ry, math.radians(rot), large, sweep, p))
            cur = p
            last_c2 = None
        elif C == 'Z':
            subs.append((start, segs, True))
            segs = None
            cur = start
            last_c2 = None
        else:
            raise ValueError('path command ' + cmd)
    if segs:
        subs.append((start, segs, False))
    return subs


def ellipse_path(cx, cy, rx, ry):
    k = 0.5522847498
    p = [(cx + rx, cy), (cx, cy + ry), (cx - rx, cy), (cx, cy - ry)]
    segs = [
        ('C', (cx + rx, cy + k * ry), (cx + k * rx, cy + ry), p[1]),
        ('C', (cx - k * rx, cy + ry), (cx - rx, cy + k * ry), p[2]),
        ('C', (cx - rx, cy - k * ry), (cx - k * rx, cy - ry), p[3]),
        ('C', (cx + k * rx, cy - ry), (cx + rx, cy - k * ry), p[0]),
    ]
    return [(p[0], segs, True)]


def transform_subs(subs, m):
    out = []
    for start, segs, closed in subs:
        ns = []
        for s in segs:
            ns.append((s[0],) + tuple(apply(m, q) for q in s[1:]))
        out.append((apply(m, start), ns, closed))
    return out


def sub_points(subs):
    for start, segs, _ in subs:
        yield start
        for s in segs:
            yield from s[1:]

# ------------------------------------------------------------------ style

def style_of(el):
    st = {}
    for part in (el.get('style') or '').split(';'):
        if ':' in part:
            k, v = part.split(':', 1)
            st[k.strip()] = v.strip()
    for k in ('fill', 'stroke', 'stroke-width', 'fill-opacity', 'stroke-opacity'):
        if el.get(k) is not None:
            st[k] = el.get(k)
    return st


def inherit(parent, el):
    st = dict(parent)
    st.update(style_of(el))
    return st


def argb(hexcol, opacity):
    a = max(0, min(255, round(float(opacity) * 255)))
    return '%02X%s' % (a, hexcol.lstrip('#').upper())

# ----------------------------------------------------------- collect tree
# Item = ('shape', name, subs(svg space), style, matrix) | ('node', name, [items])

def collect(el, m, st, nodes):
    tag = el.tag.replace(SVG, '')
    m = mul(m, parse_transform(el.get('transform')))
    st = inherit(st, el)
    eid = el.get('id', '')
    items = []
    if tag in ('g', 'svg'):
        for ch in el:
            items.extend(collect(ch, m, st, nodes))
    elif tag == 'path':
        items.append(('shape', eid, transform_subs(parse_d(el.get('d')), m), st, m))
    elif tag in ('ellipse', 'circle'):
        rx = float(el.get('rx') or el.get('r'))
        ry = float(el.get('ry') or el.get('r'))
        subs = ellipse_path(float(el.get('cx', 0)), float(el.get('cy', 0)), rx, ry)
        items.append(('shape', eid, transform_subs(subs, m), st, m))
    elif tag == 'rect':
        x, y = float(el.get('x', 0)), float(el.get('y', 0))
        w, h = float(el.get('width')), float(el.get('height'))
        # rounded corners (rx/ry) are not used by the art yet; drawn square
        subs = [((x, y), [('L', (x + w, y)), ('L', (x + w, y + h)), ('L', (x, y + h)), ('L', (x, y))], True)]
        items.append(('shape', eid, transform_subs(subs, m), st, m))
    if eid in nodes:
        return [('node', nodes[eid], items)]
    return items


def anchor_points(items):
    for it in items:
        if it[0] == 'shape':
            for start, segs, _ in it[2]:
                yield start
                for sg in segs:
                    yield sg[-1]
        else:
            yield from anchor_points(it[2])


def all_points(items):
    for it in items:
        if it[0] == 'shape':
            yield from sub_points(it[2])
        else:
            yield from all_points(it[2])


def bbox(pts):
    pts = list(pts)
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    return min(xs), min(ys), max(xs), max(ys)

# -------------------------------------------------------------------- emit

def f(v):
    s = '%.3f' % v
    s = s.rstrip('0').rstrip('.')
    return '0' if s in ('-0', '') else s


def vertices(start, segs, closed, ox, oy):
    eps = 1e-4
    anchors = [start] + [s[-1] for s in segs]
    ins = [None] + [s[2] if s[0] == 'C' else None for s in segs]
    outs = [s[1] if s[0] == 'C' else None for s in segs] + [None]
    if closed and len(anchors) > 1 and math.dist(anchors[0], anchors[-1]) < eps:
        ins[0] = ins[-1]
        anchors, ins, outs = anchors[:-1], ins[:-1], outs[:-1]
    lines = []
    for p, ci, co in zip(anchors, ins, outs):
        x, y = p[0] - ox, p[1] - oy
        di = math.dist(p, ci) if ci else 0
        do = math.dist(p, co) if co else 0
        if di < eps and do < eps:
            lines.append('<StraightVertex x="%s" y="%s"/>' % (f(x), f(y)))
            continue
        ri = math.atan2(ci[1] - p[1], ci[0] - p[0]) if di >= eps else 0
        ro = math.atan2(co[1] - p[1], co[0] - p[0]) if do >= eps else 0
        lines.append('<CubicDetachedVertex x="%s" y="%s" inRotation="%s" inDistance="%s" outRotation="%s" outDistance="%s"/>'
                     % (f(x), f(y), f(ri), f(di), f(ro), f(do)))
    return lines


class Emitter:
    def __init__(self, g, scale, ids, tips):
        self.g = g          # svg space -> artboard space
        self.scale = scale  # artboard units per svg unit
        self.ids = ids
        self.tips = tips    # node name -> (marker name, 'min' or 'max' x)
        self.node_ids = {}
        self.out = []

    def emit(self, items, ox, oy, pivots, depth):
        pad = '    ' * depth
        # RML draws earlier siblings on top; SVG draws later ones on top
        for it in reversed(items):
            if it[0] == 'node':
                name, kids = it[1], it[2]
                px, py = pivots[name](bbox(apply(self.g, p) for p in all_points(kids)))
                nid = self.ids.next()
                self.node_ids[name] = nid
                self.out.append('%s<Node x="%s" y="%s" name="%s" id="%s">' % (pad, f(px - ox), f(py - oy), name, nid))
                if name in self.tips:
                    # an empty marker at the node's outermost vertex, moving with it
                    marker, side = self.tips[name]
                    pts = [apply(self.g, q) for q in anchor_points(kids)]
                    tip = min(pts, key=lambda q: q[0]) if side == 'min' else max(pts, key=lambda q: q[0])
                    self.out.append('%s    <Node x="%s" y="%s" name="%s" id="%s"/>'
                                    % (pad, f(tip[0] - px), f(tip[1] - py), marker, self.ids.next()))
                self.emit(kids, px, py, pivots, depth + 1)
                self.out.append('%s</Node>' % pad)
            else:
                self.shape(it, ox, oy, pad)

    def shape(self, it, ox, oy, pad):
        _, name, subs, st, m = it
        subs = transform_subs(subs, self.g)
        self.out.append('%s<Shape name="%s">' % (pad, name or 'Shape'))
        for start, segs, closed in subs:
            self.out.append('%s    <PointsPath isClosed="%s" name="Path">' % (pad, 'true' if closed else 'false'))
            for v in vertices(start, segs, closed, ox, oy):
                self.out.append('%s        %s' % (pad, v))
            self.out.append('%s    </PointsPath>' % pad)
        fill = st.get('fill', '#000000')
        if fill != 'none':
            self.out.append('%s    <Fill name="Fill"><SolidColor colorValue="%s" name="C"/></Fill>'
                            % (pad, argb(fill, st.get('fill-opacity', 1))))
        stroke = st.get('stroke', 'none')
        if stroke != 'none':
            w = float(st.get('stroke-width', 1)) * math.sqrt(abs(m[0] * m[3] - m[1] * m[2])) * self.scale
            self.out.append('%s    <Stroke thickness="%s" cap="round" join="round" name="Stroke"><SolidColor colorValue="%s" name="C"/></Stroke>'
                            % (pad, f(w), argb(stroke, st.get('stroke-opacity', 1))))
        self.out.append('%s</Shape>' % pad)


class Ids:
    def __init__(self, start):
        self.n = start

    def next(self):
        self.n += 1
        return '0:%d' % self.n

# ------------------------------------------------------------------ assets

def frac(fx, fy):
    return lambda b: (b[0] + (b[2] - b[0]) * fx, b[1] + (b[3] - b[1]) * fy)


# Each asset owns a block of 100 ids starting at `id` (the artboard's), so the
# ids scene.rml points at stay put when an SVG changes.
# Echula's left wing is the mirrored group g45, the right wing g41. Pivots are
# fractions of each group's bounding box in artboard space: the wing's shoulder
# sits at its inner top edge, the ears at their base.
ASSETS = [
    dict(svg='echula.svg', name='Echula', id=5000, size=(260, 220), box=(12, 50, 248, 190), align='center',
         root='Body', root_pivot=frac(0.5, 0.55),
         nodes={'g45': 'WingL', 'g41': 'WingR', 'path34': 'EarL', 'path42': 'EarR',
                'g42': 'Head', 'path39': 'Tuft', 'path38': 'Band', 'g38': 'CupL', 'g47': 'CupR'},
         # wingtip markers (streak trails start there) ride the flapping wings
         tips={'WingL': ('WingTipL', 'min'), 'WingR': ('WingTipR', 'max')},
         pivots={'WingL': frac(0.97, 0.25), 'WingR': frac(0.03, 0.25),
                 'EarL': frac(0.5, 0.95), 'EarR': frac(0.5, 0.95),
                 'Head': frac(0.5, 0.5), 'Tuft': frac(0.5, 0.5), 'Band': frac(0.5, 0.5),
                 'CupL': frac(0.5, 0.5), 'CupR': frac(0.5, 0.5)}),
    # 3D props: transparent, feet on the bottom edge (ASSETS.md §2)
    dict(svg='garlic.svg', name='Garlic', id=5100, size=(256, 288), box=(6, 6, 250, 286), align='bottom'),
    dict(svg='wooden_stake.svg', name='Stake', id=5800, size=(232, 292), box=(4, 4, 228, 290), align='bottom'),
    dict(svg='pink_candy.svg', name='CandyPink', id=5200, size=(128, 128), box=(4, 4, 124, 124), align='center'),
    dict(svg='orange_candy.svg', name='CandyOrange', id=5300, size=(128, 128), box=(4, 4, 124, 124), align='center'),
    # street dressing (texture props): the lamp faces the camera, the fence runs along the street
    dict(svg='lamp.svg', name='Lamp', id=5600, size=(104, 512), box=(2, 2, 102, 510), align='bottom'),
    # a front view that tiles: no margin, so the rails meet the next section's
    dict(svg='fence.svg', name='Fence', id=5700, size=(442, 256), box=(0, 0, 442, 256), align='bottom'),
    # sky, drawn as vectors over the sonar sky
    dict(svg='moon.svg', name='Moon', id=5400, size=(160, 160), box=(0, 0, 160, 160), align='center'),
    dict(svg='cloud.svg', name='Cloud', id=5500, size=(260, 90), box=(0, 0, 260, 90), align='bottom'),
]


def build_asset(a, stage_x):
    ids = Ids(a['id'])
    tree = ET.parse(ROOT / 'svg' / a['svg']).getroot()
    nodes = a.get('nodes', {})
    items = collect(tree, IDENT, {}, nodes)
    x0, y0, x1, y1 = bbox(all_points(items))
    bx0, by0, bx1, by1 = a['box']
    s = min((bx1 - bx0) / (x1 - x0), (by1 - by0) / (y1 - y0))
    w, h = (x1 - x0) * s, (y1 - y0) * s
    tx = bx0 + ((bx1 - bx0) - w) / 2
    ty = by1 - h if a['align'] == 'bottom' else by0 + ((by1 - by0) - h) / 2
    g = (s, 0, 0, s, tx - x0 * s, ty - y0 * s)

    em = Emitter(g, s, ids, a.get('tips', {}))
    W, H = a['size']
    aid = '0:%d' % a['id']
    pivots = dict(a.get('pivots', {}))
    if a.get('root'):
        pivots[a['root']] = a['root_pivot']
        items = [('node', a['root'], items)]
    em.emit(items, 0, 0, pivots, 2)
    head = ['    <!-- %s: generated from svg/%s by scripts/svg2rml.py -->' % (a['name'], a['svg']),
            '    <Artboard x="%d" y="-400" width="%d" height="%d" clip="false"%s name="%s" id="%s">'
            % (stage_x, W, H, COMPONENT if a['name'] in COMPONENTS else '', a['name'], aid)]
    return aid, em, head, W, ids


def echula_extras(em, ids):
    """The beat-synced flap: down on the beat (frame 0)."""
    out = []
    n = em.node_ids

    ease_out = '<CubicEaseInterpolator x1="0.2" y1="0" x2="0.3" y2="1"/>'
    ease_io = '<CubicEaseInterpolator x1="0.45" y1="0" x2="0.55" y2="1"/>'

    def keys(prop, frames):
        lines = ['                <KeyedProperty propertyKey="%d">' % prop]
        for fr, v, ease in frames:
            interp = ease_out if ease == 'out' else ease_io
            lines.append('                    <KeyFrameDouble value="%s" frame="%d" interpolationType="cubic">%s</KeyFrameDouble>'
                         % (f(v), fr, interp))
        lines.append('                </KeyedProperty>')
        return lines

    def keyed(name, props):
        lines = ['            <KeyedObject objectId="%s">' % n[name]]
        for p in props:
            lines += p
        lines.append('            </KeyedObject>')
        return lines

    ROT, SY, Y = 15, 17, 14
    body_y = em.body_y
    # One flap per beat (30 frames at 60 fps = 120 BPM). Snappy downstroke on
    # the beat, slower recovery; the body rises on the push, ears lag 3 frames.
    down, up = 0.22, -0.5
    anim = ['        <LinearAnimation fps="60" duration="30" loopValue="loop" name="idle_flap" id="%s">' % ids.next()]
    anim += keyed('WingL', [keys(ROT, [(0, -down, 'io'), (13, -up, 'io'), (24, -down * 1.1, 'out'), (30, -down, 'io')]),
                            keys(SY, [(0, 1, 'io'), (13, 0.8, 'io'), (24, 1.05, 'out'), (30, 1, 'io')])])
    anim += keyed('WingR', [keys(ROT, [(0, down, 'io'), (13, up, 'io'), (24, down * 1.1, 'out'), (30, down, 'io')]),
                            keys(SY, [(0, 1, 'io'), (13, 0.8, 'io'), (24, 1.05, 'out'), (30, 1, 'io')])])
    anim += keyed('Body', [keys(Y, [(0, body_y - 4, 'io'), (15, body_y + 3, 'io'), (30, body_y - 4, 'io')])])
    anim += keyed('EarL', [keys(ROT, [(0, -0.05, 'io'), (3, -0.1, 'io'), (18, 0.08, 'io'), (30, -0.05, 'io')])])
    anim += keyed('EarR', [keys(ROT, [(0, 0.05, 'io'), (3, 0.1, 'io'), (18, -0.08, 'io'), (30, 0.05, 'io')])])
    anim += keyed('Head', [keys(Y, [(0, em.head_y, 'io'), (18, em.head_y + 1.5, 'io'), (30, em.head_y, 'io')])])
    anim.append('        </LinearAnimation>')
    return out + anim


def main():
    lines = ['<Rive version="1" kind="fragment">',
             '    <!-- GENERATED by scripts/svg2rml.py from svg/*.svg. Do not edit by hand: change the',
             '         SVG (keep its element ids) or the script, then re-run it. -->']
    stage_x = 700
    for a in ASSETS:
        aid, em, head, W, ids = build_asset(a, stage_x)
        stage_x += W + 80
        lines += head
        body = list(em.out)
        if a['name'] == 'Echula':
            m = re.search(r'<Node x="([-\d.]+)" y="([-\d.]+)" name="Body"', '\n'.join(body))
            em.body_y = float(m.group(2))
            m = re.search(r'<Node x="([-\d.]+)" y="([-\d.]+)" name="Head"', '\n'.join(body))
            em.head_y = float(m.group(2))
            lines += echula_extras(em, ids)
        lines += body
        lines.append('    </Artboard>')
        if a['name'] in COMPONENTS:
            lines.append('    <ComponentAsset artboardId="%s" name="%s"/>' % (aid, a['name']))
        print('%-12s %s  nodes: %s' % (a['name'], aid, ', '.join('%s=%s' % kv for kv in em.node_ids.items())))
    lines.append('</Rive>')
    (ROOT / 'game' / 'art.rml').write_text('\n'.join(lines) + '\n')


if __name__ == '__main__':
    main()
