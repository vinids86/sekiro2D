shader_type canvas_item;

uniform bool flash = false;
uniform vec4 flash_color : source_color = vec4(1.0, 0.95, 0.6, 1.0);

uniform float sweep_angle = 0.0;       // radianos (0 = horizontal)
uniform float sweep_width = 0.18;      // 0..1
uniform float sweep_feather = 0.20;    // suavização da borda
uniform bool  sweep_animated = true;  // varrer enquanto "flash" ativo
uniform float sweep_speed = 8.0;       // ciclos/s se animado
uniform float screen_strength = 0.85;  // 0..1
uniform vec2  sweep_center = vec2(0.5, 0.5);

void fragment() {
    vec4 tex = texture(TEXTURE, UV);

    if (flash) {
        // --- máscara da faixa (sweep) com rotação ---
        vec2 u = UV - sweep_center;
        float ca = cos(sweep_angle);
        float sa = sin(sweep_angle);
        vec2 uv2 = vec2(
            dot(u, vec2(ca, -sa)),
            dot(u, vec2(sa,  ca))
        ) + sweep_center;

        float phase;
        if (sweep_animated) {
            phase = fract(uv2.x + TIME * sweep_speed);
        } else {
            phase = uv2.x;
        }

        float d = abs(phase - 0.5);
        float half_w = max(sweep_width * 0.5, 1e-4);
        float feather = max(sweep_feather, 1e-5);
        float band = 1.0 - smoothstep(half_w, half_w + feather, d); // 1 dentro da faixa

        // --- mistura tipo SCREEN ---
        vec3 screen_c = 1.0 - (1.0 - tex.rgb) * (1.0 - flash_color.rgb);
        float m = clamp(screen_strength * band, 0.0, 1.0);
        vec3 outc = mix(tex.rgb, screen_c, m);

        COLOR = vec4(outc, tex.a);
    } else {
        COLOR = tex;
    }
}
