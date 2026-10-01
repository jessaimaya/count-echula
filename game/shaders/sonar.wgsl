// Sonar post pass. Fullscreen triangle; reads the scene color (alpha = object
// class) and the depth buffer, reconstructs world position, and composes:
//   night sky + moon + stars
//   height fog: thick at street level, thinning upward so rooftops show
//   moonlit rims on whatever rises above the fog, window glow through it
//   sonar pulses that cut the fog and draw soft monochrome outlines
//
// Pulse kinds: 0 = perfect, 1 = good, 2 = miss (glitch).
// Classes (scene alpha): 0 sky, 0.25 ground, 0.5 house, 0.55 window, 0.75 candy, 1.0 danger.

struct Post {
    res: vec4<f32>,    // x = width px, y = height px, z = time s, w = street scroll (world units)
    bat: vec4<f32>,    // x, y = ring origin px, z = near, w = far
    cfg: vec4<f32>,    // x = ring speed px/s, y = fog boost 0..1 (bridge), z = idle reveal, w = class tint 0..1
    look: vec4<f32>,   // x = fog top (world y), y = fog density 0..1, z = chroma 0..1, w = unused
    pulses: array<vec4<f32>, 4>, // x = start time, y = strength (0 = unused), z = kind, w = lifetime s
    invViewProj: mat4x4<f32>,
    fx: vec4<f32>,     // x = seconds since a life was lost, y = seconds since a color burst, z = burst power, w = unused
    fx2: vec4<f32>,    // x = seconds since a streak broke, y = break power 0..1, zw = unused
};

@group(0) @binding(0) var<uniform> u: Post;
@group(0) @binding(1) var sceneTex: texture_2d<f32>;
@group(0) @binding(2) var depthTex: texture_depth_2d;

struct VOut {
    @builtin(position) pos: vec4<f32>,
};

@vertex
fn vs_main(@builtin(vertex_index) vi: u32) -> VOut {
    var p = array<vec2<f32>, 3>(
        vec2<f32>(-1.0, -1.0), vec2<f32>(3.0, -1.0), vec2<f32>(-1.0, 3.0),
    );
    var out: VOut;
    out.pos = vec4<f32>(p[vi], 0.0, 1.0);
    return out;
}

fn clampCoord(p: vec2<i32>) -> vec2<i32> {
    let dim = vec2<i32>(textureDimensions(sceneTex));
    return clamp(p, vec2<i32>(0, 0), dim - vec2<i32>(1, 1));
}

fn rawDepth(p: vec2<i32>) -> f32 {
    return textureLoad(depthTex, clampCoord(p), 0);
}

fn linDepth(p: vec2<i32>) -> f32 {
    let d = rawDepth(p);
    let n = u.bat.z;
    let f = u.bat.w;
    return n * f / (f - d * (f - n));
}

fn cls(p: vec2<i32>) -> f32 {
    return textureLoad(sceneTex, clampCoord(p), 0).a;
}

fn worldPos(px: vec2<f32>, d: f32) -> vec3<f32> {
    let ndc = vec2<f32>(px.x / u.res.x * 2.0 - 1.0, 1.0 - px.y / u.res.y * 2.0);
    let w = u.invViewProj * vec4<f32>(ndc, d, 1.0);
    return w.xyz / w.w;
}

fn hash1(n: f32) -> f32 {
    return fract(sin(n * 12.9898) * 43758.5453);
}

fn hash2(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let s = f * f * (3.0 - 2.0 * f);
    let a = hash2(i);
    let b = hash2(i + vec2<f32>(1.0, 0.0));
    let c = hash2(i + vec2<f32>(0.0, 1.0));
    let d = hash2(i + vec2<f32>(1.0, 1.0));
    return mix(mix(a, b, s.x), mix(c, d, s.x), s.y);
}

fn fbm(p: vec2<f32>) -> f32 {
    var v = 0.0;
    var a = 0.5;
    var q = p;
    for (var i = 0; i < 4; i++) {
        v += a * noise(q);
        q = q * 2.03 + vec2<f32>(17.0, 9.0);
        a *= 0.5;
    }
    return v;
}

fn hsv(h: f32, s: f32, v: f32) -> vec3<f32> {
    let k = vec3<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0);
    let p = abs(fract(vec3<f32>(h) + k) * 6.0 - vec3<f32>(3.0));
    return v * mix(vec3<f32>(1.0), clamp(p - vec3<f32>(1.0), vec3<f32>(0.0), vec3<f32>(1.0)), s);
}

fn luma(c: vec3<f32>) -> f32 {
    return dot(c, vec3<f32>(0.299, 0.587, 0.114));
}

// Monochrome outline color with a faint class hint.
fn outlineColor(c: f32) -> vec3<f32> {
    let white = vec3<f32>(0.92, 0.95, 1.0);
    var hint = white;
    if (c > 0.9) { hint = vec3<f32>(0.62, 1.0, 0.6); }        // danger: faint green
    else if (c > 0.6) { hint = vec3<f32>(1.0, 0.78, 0.5); }   // candy: faint amber
    return mix(white, hint, u.cfg.w);
}

@fragment
fn fs_main(in: VOut) -> @location(0) vec4<f32> {
    let time = u.res.z;
    let uv = in.pos.xy / u.res.xy;
    let toBat = in.pos.xy - u.bat.xy;
    let dist = length(toBat);
    let dir = toBat / max(dist, 1.0);

    // --- sonar pulses
    var reveal = u.cfg.z;
    var band = 0.0;
    var chroma = 0.0;
    var glitch = 0.0;
    for (var i = 0; i < 4; i++) {
        let pl = u.pulses[i];
        let t = time - pl.x;
        if (pl.y <= 0.0 || t < 0.0 || t > pl.w) { continue; }
        let maxR = u.res.y * 1.5 * pl.y;
        let r = min(t * u.cfg.x, maxR);
        let fade = 1.0 - t / pl.w;
        let growing = step(t * u.cfg.x, maxR);
        let b = smoothstep(r - 36.0, r, dist) * (1.0 - smoothstep(r, r + 6.0, dist)) * growing * fade;
        let inside = step(dist, r) * fade * pl.y;
        reveal = max(reveal, inside);
        band = max(band, b);
        if (pl.z < 0.5) { chroma = max(chroma, b); }
        if (pl.z > 1.5) { glitch = max(glitch, inside * fade); }
    }

    // --- life lost: a sharp glitch that fades over ~0.6 s
    var hit = 0.0;
    if (u.fx.x < 1.5) { hit = exp(-u.fx.x * 4.0); }
    glitch = max(glitch, hit * 0.8);

    // --- color burst: a rainbow shockwave from the bat, the street lit in color
    var burst = 0.0;
    var ring = 0.0;
    if (u.fx.y < 5.0) {
        burst = u.fx.z * exp(-u.fx.y * 1.1);
        let rr = u.fx.y * u.res.y * 1.3;
        ring = smoothstep(rr - 70.0, rr, dist) * (1.0 - smoothstep(rr, rr + 10.0, dist)) * u.fx.z * exp(-u.fx.y * 0.8);
    }
    reveal = max(reveal, burst * 0.9);
    let rainbow = hsv(fract(atan2(dir.y, dir.x) / 6.2831 + dist / u.res.y * 0.8 - time * 0.35), 0.75, 1.0);

    // --- streak broken: a fast refracting shockwave + the lights go cold for ~1 s
    var brk = 0.0;
    var brkBand = 0.0;
    if (u.fx2.x >= 0.0 && u.fx2.x < 1.5) {
        brk = u.fx2.y * exp(-u.fx2.x * 3.0);
        let br = u.fx2.x * u.res.y * 1.8;
        brkBand = smoothstep(br - 90.0, br - 20.0, dist) * (1.0 - smoothstep(br - 20.0, br, dist)) * u.fx2.y * exp(-u.fx2.x * 2.0);
    }

    // --- glitch: horizontal block jitter inside a miss reveal or a hit
    let row = floor(in.pos.y / 6.0);
    let jitter = (hash1(row + floor(time * 30.0)) - 0.5) * 18.0 * glitch;
    let pf = in.pos.xy + vec2<f32>(jitter, 0.0) - dir * 22.0 * brkBand;
    let p = vec2<i32>(pf);
    let base = textureLoad(sceneTex, clampCoord(p), 0);
    let c0 = base.a;
    let isSky = c0 < 0.01;

    // --- sky: gradient, moon, stars
    let horizon = 0.13;
    let skyT = clamp(uv.y / horizon, 0.0, 1.0);
    var sky = mix(vec3<f32>(0.03, 0.025, 0.09), vec3<f32>(0.16, 0.14, 0.3), skyT * skyT);
    sky += hsv(fract(uv.x * 0.7 + time * 0.2), 0.7, 1.0) * burst * 0.3 * skyT;
    let moonC = vec2<f32>(0.66 * u.res.x, 0.085 * u.res.y);
    let md = length(in.pos.xy - moonC) / u.res.y;
    sky += vec3<f32>(0.85, 0.87, 0.95) * smoothstep(0.034, 0.03, md);
    sky += vec3<f32>(0.3, 0.3, 0.45) * exp(-md * 18.0) * 0.6;
    let starCell = floor(in.pos.xy / 4.0);
    let star = step(0.9975, hash2(starCell)) * (0.5 + 0.5 * sin(time * 2.0 + hash2(starCell + 3.0) * 6.28));
    sky += vec3<f32>(0.8, 0.8, 0.95) * star * (1.0 - skyT) * 0.8;

    // --- world position and height fog
    let d = rawDepth(p);
    let lin = linDepth(p);
    let world = worldPos(pf, d);
    let fogTop = u.look.x + u.cfg.y * 1.1;
    let above = smoothstep(fogTop - 0.4, fogTop + 0.5, world.y);
    let street = vec2<f32>(world.x * 0.35, (world.z - u.res.w) * 0.22);
    let drift = vec2<f32>(time * 0.04, 0.0);
    let n = fbm(street + drift);
    let distFog = smoothstep(8.0, 34.0, lin);
    var fog = (1.0 - above) * u.look.y * mix(0.85, 1.0, n) + distFog * 0.6;
    fog = clamp(fog + u.cfg.y * 0.15, 0.0, 1.0);

    // --- edges from class id + relative depth discontinuities
    let cx = abs(cls(p + vec2<i32>(1, 0)) - cls(p - vec2<i32>(1, 0)));
    let cy = abs(cls(p + vec2<i32>(0, 1)) - cls(p - vec2<i32>(0, 1)));
    let dx = abs(linDepth(p + vec2<i32>(1, 0)) - linDepth(p - vec2<i32>(1, 0)));
    let dy = abs(linDepth(p + vec2<i32>(0, 1)) - linDepth(p - vec2<i32>(0, 1)));
    let depthEdge = smoothstep(0.02, 0.08, (dx + dy) / max(lin, 0.001));
    let classEdge = step(0.1, cx + cy);
    let edge = max(depthEdge, classEdge);
    let edgeClass = max(c0, cls(p + vec2<i32>(1, 1)));

    // --- ambient: dark silhouettes, moonlit rims above the fog
    var fogLit = mix(vec3<f32>(0.11, 0.1, 0.21), vec3<f32>(0.21, 0.19, 0.34), n * n);
    fogLit = mix(fogLit, rainbow * 0.45, burst * 0.5);
    var obj = vec3<f32>(0.05, 0.045, 0.1) + vec3<f32>(luma(base.rgb)) * 0.08;
    obj += vec3<f32>(0.55, 0.58, 0.72) * edge * above * 0.45;
    var col = mix(obj, fogLit, fog);

    // windows glow warm through the fog
    let isWindow = step(abs(c0 - 0.55), 0.02);
    col += vec3<f32>(1.0, 0.62, 0.25) * isWindow * (0.55 - 0.3 * fog);

    // --- sonar: cut the fog, soft monochrome outlines, faint desaturated fill
    let clear = reveal * (1.0 - distFog * 0.5);
    col = mix(col, obj, clear * 0.85);
    col += vec3<f32>(luma(base.rgb)) * 0.1 * clear * step(0.01, c0);
    let lineColor = mix(outlineColor(edgeClass), rainbow, clamp(burst * 1.4 + ring, 0.0, 1.0));
    col += lineColor * edge * (clear + band * 1.4 + ring);
    col += rainbow * ring * 0.55;
    col += vec3<f32>(0.85, 0.9, 1.0) * band * 0.14;

    // perfect: a light chromatic fringe riding the wavefront only
    let off = vec2<i32>(dir * 3.0 * chroma * u.look.z);
    let fr = textureLoad(sceneTex, clampCoord(p + off), 0).a;
    let fb = textureLoad(sceneTex, clampCoord(p - off), 0).a;
    col += vec3<f32>(abs(fr - c0), 0.0, abs(fb - c0)) * chroma * u.look.z * 0.6;

    // glitch tint
    col += vec3<f32>(0.5, 0.45, 0.6) * glitch * 0.18 * hash1(row * 7.0 + time);

    if (isSky) {
        col = mix(sky, fogLit, smoothstep(0.08, 0.16, uv.y) * 0.8);
        col += vec3<f32>(0.85, 0.9, 1.0) * band * 0.08;
    }

    // vignette
    let vig = smoothstep(0.95, 0.35, length(uv - vec2<f32>(0.5, 0.55)));
    col *= mix(0.5, 1.0, vig);

    // streak broken: drain to a cold blue-grey, dim, squeeze the vignette; a pale ring edge
    if (brk > 0.0) {
        let l = luma(col);
        col = mix(col, vec3<f32>(l * 0.75, l * 0.85, l * 1.15), brk * 0.85);
        col *= 1.0 - 0.35 * brk;
        col *= mix(1.0, vig, brk * 0.7);
    }
    col += vec3<f32>(0.75, 0.85, 1.0) * brkBand * 0.45;

    // life lost: drain the color toward red, pulse a red vignette, one white flash frame
    if (hit > 0.0) {
        let l = luma(col);
        col = mix(col, vec3<f32>(l * 1.3 + 0.2, l * 0.35, l * 0.45 + 0.03), hit * 0.75);
        col += vec3<f32>(0.8, 0.05, 0.12) * (1.0 - vig) * hit * 0.9;
        col += vec3<f32>(1.0, 0.85, 0.9) * smoothstep(0.08, 0.0, u.fx.x) * 0.35;
    }
    return vec4<f32>(col, 1.0);
}
