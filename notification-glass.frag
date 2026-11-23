#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 resolution;
    vec4 bodyRect;
    vec2 inward;
    vec4 shape;
    vec4 finish;
    vec4 accentColor;
    vec4 sceneUv;
    vec4 joinedPuck;
};
layout(binding = 1) uniform sampler2D scene;

float distanceToGlass(vec2 p) {
    vec2 halfSize = max(bodyRect.zw * 0.5, vec2(0.5));
    vec2 local = p - bodyRect.xy - halfSize;
    vec2 across = vec2(inward.y, -inward.x);
    float axisSize = dot(halfSize, abs(inward));
    float travel = clamp(0.5 + dot(local, inward) / (2.0 * axisSize), 0.0, 1.0);
    float taper = mix(1.0, mix(0.28, 1.0, smoothstep(0.0, 0.7, travel)), shape.y);
    local += across * dot(local, across) * (1.0 / taper - 1.0);
    vec2 q = abs(local) - halfSize + shape.x;
    float body = (length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - shape.x) * taper;
    if (joinedPuck.z > 0.001) {
        vec2 halfPuck = joinedPuck.zw * 0.5;
        float radius = min(halfPuck.x, halfPuck.y);
        vec2 edge = abs(p - joinedPuck.xy - halfPuck) - halfPuck + radius;
        float puck = length(max(edge, 0.0)) + min(max(edge.x, edge.y), 0.0) - radius;
        float join = max(18.0 - abs(body - puck), 0.0) / 18.0;
        body = min(body, puck) - 4.5 * join * join;
    }
    return body;
}

void main() {
    vec2 p = qt_TexCoord0 * resolution;
    float d = distanceToGlass(p);
    float aa = max(fwidth(d), 0.65);
    float coverage = 1.0 - smoothstep(-aa, aa, d);
    float bevel = exp(-max(0.0, -d) / 8.5);
    vec2 normal = normalize(vec2(distanceToGlass(p + vec2(1.0, 0.0)) - distanceToGlass(p - vec2(1.0, 0.0)),
        distanceToGlass(p + vec2(0.0, 1.0)) - distanceToGlass(p - vec2(0.0, 1.0))) + vec2(0.0001));
    vec2 lens = clamp((p - bodyRect.xy) * 2.0 / max(bodyRect.zw, vec2(1.0)) - 1.0, -1.0, 1.0);
    float shoulder = smoothstep(0.2, 1.0, max(abs(lens.x), abs(lens.y)));
    vec2 bend = mix(normal * bevel * 10.0, lens * (3.0 + 9.0 * shoulder), 0.75);
    vec2 uv = sceneUv.xy + (p - bend * shape.z) / resolution * sceneUv.zw;
    vec2 blur = shape.w * 0.6 / resolution * sceneUv.zw;
    vec4 background = vec4(0.0);
    if (finish.w > 0.5) {
        background = texture(scene, uv) * 0.44 + 0.14 * (
            texture(scene, uv + vec2(blur.x, 0.0)) + texture(scene, uv - vec2(blur.x, 0.0))
            + texture(scene, uv + vec2(0.0, blur.y)) + texture(scene, uv - vec2(0.0, blur.y)));
    }

    float dark = clamp(0.48 + 0.29 * finish.x + 0.20 * finish.y, 0.0, 0.96);
    float alpha = dark + background.a * (1.0 - dark);
    vec3 base = mix(vec3(0.056, 0.090, 0.081), accentColor.rgb, 0.11);
    vec3 color = base * dark + background.rgb * (1.0 - dark);
    float specular = pow(max(0.0, dot(normal, normalize(vec2(-0.50, -1.0)))), 3.0);
    float rim = exp(-abs(d + 0.9) / 1.1) * (0.095 + 0.34 * specular);
    float inner = exp(-abs(d + 4.2) / 2.1) * 0.052;
    vec3 pearl = mix(vec3(1.0), accentColor.rgb, 0.34);
    color += pearl * (rim + inner) * clamp(finish.z, 0.0, 2.0);
    color += pearl * 0.035 * finish.z * bevel * specular;
    fragColor = vec4(min(color, vec3(alpha)), alpha) * coverage * qt_Opacity;
}
