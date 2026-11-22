#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// 物灵的水墨着色器：
// 1. 送别时的墨点粒子（MTKView 里的一条完整渲染管线：顶点 + 片元）
// 2. 水面（SwiftUI 的 layerEffect）：物理波纹的折射、墨色涟漪，和水线以上一切东西的倒影

// MARK: - 墨点粒子

// 和 Swift 里的 InkParticle 一一对应：两个 float4，32 字节
struct InkParticle {
    float4 origin;  // xy = 起点（pt），z = 随机数 0…1，w = 出发的延迟（秒）
    float4 color;   // 原图这个像素的颜色（未预乘），a = 不透明度
};

// 和 Swift 里的 InkUniforms 一一对应：四个 float4，64 字节
struct InkUniforms {
    float4 view;    // xy = 画布大小（pt），z = 已过去的时间（秒），w = 每 pt 多少像素
    float4 target;  // xy = 河灯落点（pt），z = 水线 y（pt），w = 开始汇聚的时刻（秒）
    float4 ink;     // rgb = 墨色，a = 汇聚用多久（秒）
    float4 glow;    // rgb = 河灯的暖光，a = 采样间距（pt），也就是一开始每个点的大小
};

struct InkVertexOut {
    float4 position [[position]];
    float pointSize [[point_size]];
    float4 color;      // 预乘过的颜色
    float softness;    // 0 = 方形像素（拼成原图），1 = 边缘洇开的圆墨点
};

// 由一个种子派生出彼此独立的随机数（0…1）
static float inkHash(float seed, float salt) {
    return fract(sin(seed * salt) * 43758.5453);
}

vertex InkVertexOut inkParticleVertex(uint vid [[vertex_id]],
                                      const device InkParticle *particles [[buffer(0)]],
                                      constant InkUniforms &u [[buffer(1)]]) {
    InkParticle p = particles[vid];
    float now = u.view.z;
    float seed = p.origin.z;
    float t = max(now - p.origin.w, 0.0);   // 这个墨点出发后过了多久
    float2 pos = p.origin.xy;

    // 1. 随风飘散：先被风托起一点，再往右下方飘落，路上打着小旋
    float2 wind = float2(38.0 + 44.0 * fract(seed * 7.13), -34.0 + 22.0 * fract(seed * 3.71));
    pos += wind * t + float2(0.0, 68.0 * t * t);
    float swirl = seed * 6.2831853 + t * (2.0 + 2.5 * fract(seed * 5.31));
    pos += float2(cos(swirl), sin(swirl)) * (14.0 * min(t, 1.2));

    // 落到水面的墨点不再下沉，浮在水面上（远近略有不同，随水轻轻起伏）
    float waterY = u.target.z;
    float rest = waterY - 1.0 + 12.0 * inkHash(seed, 91.7) + 1.5 * sin(seed * 40.0 + now * 2.0);
    pos.y = min(pos.y, rest);

    // 2. 汇聚：每个墨点沿一道向上的弧线飞进河灯，像萤火归巢
    //    （时机、弧高、偏向各取一个独立的随机数，免得几千个点排成一道道线）
    float gather = clamp((now - u.target.w - inkHash(seed, 19.1) * 0.3) / max(u.ink.a, 0.01), 0.0, 1.0);
    float eased = gather * gather * (3.0 - 2.0 * gather);
    float arc = sin(eased * 3.14159265);
    pos = mix(pos, u.target.xy, eased);
    pos += float2(cos(inkHash(seed, 63.9) * 6.2831853) * 16.0, -(14.0 + 30.0 * inkHash(seed, 47.3))) * arc;

    // 颜色：原色 → 墨色 → 汇聚时被河灯照暖
    float inked = smoothstep(0.0, 0.7, t);
    float3 rgb = mix(p.color.rgb, u.ink.rgb, inked * 0.85);
    rgb = mix(rgb, u.glow.rgb, eased);
    float alpha = p.color.a * (1.0 - 0.3 * inked) * (1.0 - smoothstep(0.7, 1.0, gather));

    // 大小：一开始和采样间距一样大（拼成完整的原图），出发后变成大小不一的墨点，汇聚时收成光点
    float cell = u.glow.a;
    float inkSize = mix(1.4, 4.4, fract(seed * 11.7));
    float size = mix(cell * 1.45, inkSize, smoothstep(0.0, 0.5, t));
    size = mix(size, 1.8, eased);

    InkVertexOut out;
    float2 ndc = float2(pos.x / u.view.x * 2.0 - 1.0, 1.0 - pos.y / u.view.y * 2.0);
    out.position = float4(ndc, 0.0, 1.0);
    out.pointSize = max(size * u.view.w, 1.0);
    out.color = float4(rgb * alpha, alpha);
    out.softness = smoothstep(0.0, 0.35, t);
    return out;
}

fragment float4 inkParticleFragment(InkVertexOut in [[stage_in]],
                                    float2 pointCoord [[point_coord]]) {
    float d = length(pointCoord - float2(0.5)) * 2.0;   // 中心 0，边缘 1
    float disc = 1.0 - smoothstep(0.45, 1.0, d);
    float coverage = mix(1.0, disc, in.softness);
    if (coverage <= 0.002) {
        discard_fragment();
    }
    return in.color * coverage;
}

// MARK: - 水面

// 从波纹网格里取高度（双线性插值）。g 是网格坐标。
static float rippleHeight(device const float *heights, int count, int columns, float2 g) {
    int rows = count / max(columns, 1);
    if (columns < 2 || rows < 2) {
        return 0.0;
    }
    float2 maxIndex = float2(float(columns - 1), float(rows - 1));
    g = clamp(g, float2(0.0), maxIndex);
    int x0 = int(floor(g.x));
    int y0 = int(floor(g.y));
    int x1 = min(x0 + 1, columns - 1);
    int y1 = min(y0 + 1, rows - 1);
    float2 f = g - float2(float(x0), float(y0));
    float a = heights[y0 * columns + x0];
    float b = heights[y0 * columns + x1];
    float c = heights[y1 * columns + x0];
    float d = heights[y1 * columns + x1];
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// 水线以上原样显示；水线以下是一池淡墨：
// - 波纹网格（RippleField 解出的波动方程）决定折射偏移和墨色涟漪
// - 以水线为镜，倒映上面的一切（物件、物灵插画、河灯），离水线越远越淡
// - 再叠一层缓缓流动的横向淡墨水纹
[[ stitchable ]] half4 inkWater(float2 position, SwiftUI::Layer layer,
                                float2 size, float waterY, float time,
                                device const float *heights, int count, float columns,
                                half4 ink) {
    half4 original = layer.sample(position);
    if (position.y < waterY) {
        return original;
    }

    float depthRange = max(size.y - waterY, 1.0);
    float depth = clamp((position.y - waterY) / depthRange, 0.0, 1.0);
    int gridColumns = int(columns);
    int gridRows = count / max(gridColumns, 1);

    // 物理波纹：取高度场的梯度
    float2 g = float2(position.x / max(size.x, 1.0) * float(gridColumns - 1),
                      depth * float(gridRows - 1));
    float hc = rippleHeight(heights, count, gridColumns, g);
    float hx = rippleHeight(heights, count, gridColumns, g + float2(1.0, 0.0))
             - rippleHeight(heights, count, gridColumns, g - float2(1.0, 0.0));
    float hy = rippleHeight(heights, count, gridColumns, g + float2(0.0, 1.0))
             - rippleHeight(heights, count, gridColumns, g - float2(0.0, 1.0));

    // 平时也有一点微波：远处（靠近水线）细密，近处舒展
    float persp = mix(0.35, 1.0, depth);
    float wave = sin(position.x * 0.045 / persp + time * 1.3) * 0.6
               + sin(position.x * 0.11 / persp - time * 2.1 + position.y * 0.35) * 0.4;

    float2 offset = float2(wave * 1.8 * persp + hx * 9.0, wave * 0.6 * persp + hy * 6.0);

    // 倒影：以水线为镜
    float2 mirrored = float2(position.x + offset.x, 2.0 * waterY - position.y + offset.y);
    half4 reflection = half4(0.0h);
    if (mirrored.y >= 0.0) {
        reflection = layer.sample(mirrored);
    }
    float reflectStrength = 0.45 * (1.0 - depth * 0.8);
    reflection *= half(reflectStrength);
    // 倒影偏墨色一些，像隔着一层水
    reflection.rgb = mix(reflection.rgb, ink.rgb * reflection.a, 0.3h);

    // 水本身：越近越深的淡墨，加流动的横向水纹，再加波纹的墨圈
    float streak = smoothstep(0.86, 1.0, sin(position.y * 0.9 + sin(position.x * 0.018 + time * 0.5) * 2.5 + hc * 3.0));
    float ring = clamp(abs(hy) * 0.9 + abs(hx) * 0.5, 0.0, 1.0);
    float waterAlpha = 0.05 + 0.09 * depth + streak * 0.06 * (1.0 - depth * 0.5) + ring * 0.28;
    // 水线处一道细细的亮边
    waterAlpha += (1.0 - smoothstep(0.0, 2.5, position.y - waterY)) * 0.10;

    // 左右两端淡入纸色
    float edge = smoothstep(0.0, 40.0, position.x) * smoothstep(0.0, 40.0, size.x - position.x);
    // 底部也慢慢淡掉
    edge *= 1.0 - smoothstep(0.75, 1.0, depth);

    half4 water = half4(ink.rgb, 1.0h) * half(clamp(waterAlpha, 0.0, 1.0) * edge);
    half4 surface = reflection * half(edge) + water * (1.0h - reflection.a * half(edge));
    // 水面以下本来就画着的东西（比如河灯的底）盖在最上面
    return original + surface * (1.0h - original.a);
}
