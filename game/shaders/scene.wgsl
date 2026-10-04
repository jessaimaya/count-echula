// 3D street: instanced billboards + ground, depth tested.
// Alpha channel carries the object class for the sonar post pass:
// 0 = empty, 0.25 = ground, 0.5 = scenery, 0.55 = window, 0.75 = candy, 1.0 = danger.
// Kinds: 0 house, 1 ground, 2 candy, 3 garlic, 4 lamp, 5 fence (upright along the
// street, so the projection gives it its perspective), 6 sidewalk top (flat, raised),
// 7 curb face (upright along the street). The sidewalk is geometry, not art, so it
// converges correctly; its joints are drawn here in svg/left_sidewalk's palette.
// 8 the castle's lit hall seen through its gate, 9 the portcullis (world.luau CASTLE).

struct Camera {
    viewProj: mat4x4<f32>,
    params: vec4<f32>, // x = scroll (world units), y = time, z = lane spacing (world units)
    atlas: array<vec4<f32>, 16>, // per atlas cell: u0, v0, u1, v1 (world.luau ATLAS_RECTS)
};

@group(0) @binding(0) var<uniform> cam: Camera;
// Texture props (world.luau drawAtlas): one rect per prop in cam.atlas; the
// instance's color.a picks the cell.
@group(0) @binding(1) var atlasTex: texture_2d<f32>;
@group(0) @binding(2) var atlasSampler: sampler;

// Paving: a joint across the sidewalk every SLAB world units of street.
const SLAB: f32 = 1.0;
const SEAM: f32 = 0.035; // joint width, world units
const SEAM_RGB: vec3<f32> = vec3<f32>(0.243, 0.157, 0.31); // #3e284f
const SEAM_NEAR: f32 = -12.0; // world z beyond which joints stop drawing sonar outlines

// Fence gaps below this height (fraction of the section) are filled; the shortest
// picket's shoulders sit just above it in svg/fence.
const FENCE_BACKING: f32 = 0.84;

fn near(v: f32, k: f32) -> bool {
    return abs(v - k) < 0.1;
}

struct VIn {
    @builtin(vertex_index) vi: u32,
    @location(0) center: vec3<f32>,
    @location(1) size: vec2<f32>,
    @location(2) color: vec4<f32>,
    @location(3) kind: f32,
};

struct VOut {
    @builtin(position) pos: vec4<f32>,
    @location(0) uv: vec2<f32>,
    @location(1) color: vec4<f32>,
    @location(2) kind: f32,
    @location(3) wpos: vec3<f32>,
};

@vertex
fn vs_main(in: VIn) -> VOut {
    var corners = array<vec2<f32>, 6>(
        vec2<f32>(-0.5, 0.0), vec2<f32>(0.5, 0.0), vec2<f32>(0.5, 1.0),
        vec2<f32>(-0.5, 0.0), vec2<f32>(0.5, 1.0), vec2<f32>(-0.5, 1.0),
    );
    let c = corners[in.vi];
    var world: vec3<f32>;
    if (near(in.kind, 1.0) || near(in.kind, 6.0)) {
        // ground and sidewalk top: flat on XZ, centered on `center`, extends along -Z
        world = in.center + vec3<f32>(c.x * in.size.x, 0.0, -(c.y - 0.5) * in.size.y);
    } else if (near(in.kind, 7.0)) {
        // curb face: upright along the street, `size` = (length, height)
        world = in.center + vec3<f32>(0.0, c.y * in.size.y, -(c.x) * in.size.x);
    } else if (near(in.kind, 5.0)) {
        // fence: a section standing along the street (u runs away from the camera)
        world = in.center + vec3<f32>(0.0, c.y * in.size.y, -c.x * in.size.x);
    } else {
        // upright billboard facing +Z (the camera)
        world = in.center + vec3<f32>(c.x * in.size.x, c.y * in.size.y, 0.0);
    }
    var out: VOut;
    out.pos = cam.viewProj * vec4<f32>(world, 1.0);
    out.uv = vec2<f32>(c.x + 0.5, c.y);
    out.color = in.color;
    out.kind = in.kind;
    out.wpos = world;
    return out;
}

@fragment
fn fs_main(in: VOut) -> @location(0) vec4<f32> {
    let uv = in.uv;
    var rgb = in.color.rgb;
    var cls = 0.5;
    // sampled up front: textureSample needs uniform control flow
    // round: the interpolated cell index can arrive as 2.9999
    let rect = cam.atlas[u32(clamp(round(in.color.a), 0.0, 15.0))];
    let art = textureSample(atlasTex, atlasSampler, mix(rect.xy, rect.zw, vec2<f32>(uv.x, 1.0 - uv.y)));

    if (near(in.kind, 1.0)) {
        // ground: 3 lanes with scrolling dashes between them, at the lanes' real edges
        // (half a lane spacing either side of the center line)
        cls = 0.25;
        let z = uv.y * 60.0 + cam.params.x;
        let half = cam.params.z * 0.5;
        let lane = step(half, abs(in.wpos.x)); // the outer lanes a shade brighter
        let divider = step(abs(abs(in.wpos.x) - half), 0.036);
        let dash = step(0.5, fract(z * 0.5));
        rgb = mix(rgb, vec3<f32>(0.85, 0.8, 1.0), divider * dash * 0.8);
        rgb = rgb * (0.9 + 0.1 * lane);
    } else if (near(in.kind, 6.0) || near(in.kind, 7.0)) {
        // sidewalk: raised paving with joints that scroll with the street. Near the
        // camera a joint is its own class, so the sonar outlines the slabs; further
        // away it is color only (dense outlines there would just be noise)
        cls = 0.38;
        let s = cam.params.x - in.wpos.z;
        let j = abs(fract(s / SLAB + 0.5) - 0.5) * SLAB;
        if (j < SEAM * 0.5) {
            rgb = SEAM_RGB;
            if (in.wpos.z > SEAM_NEAR) { cls = 0.25; }
        }
    } else if (near(in.kind, 2.0)) {
        // candy (svg/pink_candy, svg/orange_candy)
        cls = 0.75;
        if (art.a < 0.5) { discard; }
        rgb = art.rgb / art.a;
    } else if (near(in.kind, 3.0)) {
        // danger: garlic (svg/garlic)
        cls = 1.0;
        if (art.a < 0.5) { discard; }
        rgb = art.rgb / art.a;
    } else if (near(in.kind, 4.0)) {
        // lamp (svg/lamp): scenery; its warm glass glows through the fog like a window
        if (art.a < 0.5) { discard; }
        rgb = art.rgb / art.a;
        let glass = rgb.r > 0.85 && rgb.g > 0.7 && rgb.b < 0.7;
        cls = select(0.5, 0.55, glass);
    } else if (near(in.kind, 5.0)) {
        // fence (svg/fence): seen this edge-on, real pickets hide the gaps between them
        // (they have thickness, ours don't), so the gaps below the picket tops get a dark
        // backing. Otherwise every gap draws its own sonar outline; only the tops stay cut out.
        cls = 0.5;
        if (art.a < 0.5) {
            if (uv.y > FENCE_BACKING) { discard; }
            rgb = vec3<f32>(0.1, 0.06, 0.1);
        } else {
            rgb = art.rgb / art.a;
        }
    } else if (near(in.kind, 8.0)) {
        // the castle's hall through the gate: warm light spilling from the floor, dark
        // under the vault; the light glows through the fog like a window
        let warm = smoothstep(0.9, 0.15, uv.y);
        rgb = mix(vec3<f32>(0.16, 0.07, 0.18), vec3<f32>(1.0, 0.72, 0.28), warm);
        cls = select(0.5, 0.55, warm > 0.2);
    } else if (near(in.kind, 9.0)) {
        // portcullis (svg/door): it hangs behind the wall; above the arch's top
        // (color.r, world height) the castle's towers don't cover it, so it is cut there
        if (art.a < 0.5 || in.wpos.y > in.color.r) { discard; }
        rgb = art.rgb / art.a;
    } else {
        // house (assets/images/houses): scenery; its lit windows glow through the
        // fog (0.55 = window)
        if (art.a < 0.5) { discard; }
        rgb = art.rgb / art.a;
        let lit = rgb.r > 0.85 && rgb.g > 0.6 && rgb.b < 0.55;
        cls = select(0.5, 0.55, lit);
    }
    return vec4<f32>(rgb, cls);
}
