// 3D street: instanced billboards + ground, depth tested.
// Alpha channel carries the object class for the sonar post pass:
// 0 = empty, 0.25 = ground, 0.5 = scenery, 0.55 = window, 0.75 = candy, 1.0 = danger.

struct Camera {
    viewProj: mat4x4<f32>,
    params: vec4<f32>, // x = scroll (world units), y = time
};

@group(0) @binding(0) var<uniform> cam: Camera;
// Texture props (world.luau drawAtlas): ATLAS_CELLS square cells side by side,
// 0 = pink candy, 1 = orange candy, 2 = garlic. The instance's color.a picks the cell.
@group(0) @binding(1) var atlasTex: texture_2d<f32>;
@group(0) @binding(2) var atlasSampler: sampler;
const ATLAS_CELLS: f32 = 3.0;

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
};

@vertex
fn vs_main(in: VIn) -> VOut {
    var corners = array<vec2<f32>, 6>(
        vec2<f32>(-0.5, 0.0), vec2<f32>(0.5, 0.0), vec2<f32>(0.5, 1.0),
        vec2<f32>(-0.5, 0.0), vec2<f32>(0.5, 1.0), vec2<f32>(-0.5, 1.0),
    );
    let c = corners[in.vi];
    var world: vec3<f32>;
    if (in.kind > 0.9 && in.kind < 1.1) {
        // ground: flat on XZ, centered on `center`, extends along -Z
        world = in.center + vec3<f32>(c.x * in.size.x, 0.0, -(c.y - 0.5) * in.size.y);
    } else {
        // upright billboard facing +Z (the camera)
        world = in.center + vec3<f32>(c.x * in.size.x, c.y * in.size.y, 0.0);
    }
    var out: VOut;
    out.pos = cam.viewProj * vec4<f32>(world, 1.0);
    out.uv = vec2<f32>(c.x + 0.5, c.y);
    out.color = in.color;
    out.kind = in.kind;
    return out;
}

@fragment
fn fs_main(in: VOut) -> @location(0) vec4<f32> {
    let uv = in.uv;
    var rgb = in.color.rgb;
    var cls = 0.5;
    // sampled up front: textureSample needs uniform control flow
    let art = textureSample(atlasTex, atlasSampler, vec2<f32>((in.color.a + uv.x) / ATLAS_CELLS, 1.0 - uv.y));

    if (in.kind > 0.9 && in.kind < 1.1) {
        // ground: 3 lanes with scrolling dashes, sidewalks at the edges
        cls = 0.25;
        let z = uv.y * 60.0 + cam.params.x;
        let lane = abs(fract(uv.x * 3.0) - 0.0);
        let divider = step(abs(uv.x - 1.0 / 3.0), 0.006) + step(abs(uv.x - 2.0 / 3.0), 0.006);
        let dash = step(0.5, fract(z * 0.5));
        rgb = mix(rgb, vec3<f32>(0.85, 0.8, 1.0), divider * dash * 0.8);
        rgb = rgb * (0.9 + 0.1 * lane);
    } else if (in.kind > 1.9 && in.kind < 2.1) {
        // candy (svg/pink_candy, svg/orange_candy)
        cls = 0.75;
        if (art.a < 0.5) { discard; }
        rgb = art.rgb / art.a;
    } else if (in.kind > 2.9) {
        // danger: garlic (svg/garlic)
        cls = 1.0;
        if (art.a < 0.5) { discard; }
        rgb = art.rgb / art.a;
    } else {
        // house: body + roof triangle + window
        cls = 0.5;
        let body = uv.y < 0.62;
        let roof = uv.y >= 0.62 && abs(uv.x - 0.5) < (1.0 - uv.y) * 1.3;
        if (!(body || roof)) { discard; }
        let win = step(abs(uv.x - 0.5), 0.12) * step(abs(uv.y - 0.35), 0.1);
        rgb = mix(rgb, vec3<f32>(1.0, 0.75, 0.3), win);
        cls = mix(0.5, 0.55, win); // 0.55 = window (glows through the fog)
    }
    return vec4<f32>(rgb, cls);
}
