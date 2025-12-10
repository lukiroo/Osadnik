shader_type canvas_item;

// ile mgły (0–1) i jej kolor
uniform float turbidity : hint_range(0.0, 1.0) = 0.0;
uniform vec4  fog_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

// poziom cieczy: 0 = pusto, 1 = pełno
uniform float level01 : hint_range(0.0, 1.0) = 0.0;
// miękkie przejście przy menisku (w pikselach)
uniform float level_softness_px : hint_range(0.0, 8.0) = 2.0;

// opcjonalne wzmocnienie mętności przy dnie probówki
uniform float bottom_boost : hint_range(0.0, 1.0) = 0.0; // 0 = wyłączone, 0.3–0.5 lekkie wzmocnienie

void fragment() {
    // kształt – alfa tekstury (musi być tak samo przycięta jak liquid body)
    float inside = texture(TEXTURE, UV).a;
    if (inside < 0.001) {
        discard;
    }

    // obliczamy, od jakiej wysokości zaczyna się ciecz
    float lvl  = clamp(level01, 0.0, 1.0);
    float cut  = 1.0 - lvl; // UV.y: 0 = góra, 1 = dno
    float soft = max(0.0001, level_softness_px * TEXTURE_PIXEL_SIZE.y);

    // maska poziomu: 0 nad cieczą, 1 w cieczy, z miękkim przejściem przy menisku
    float level_mask = smoothstep(cut, cut + soft, UV.y);

    // bazowa alfa mętności
    float a = turbidity * inside * level_mask;

    // delikatnie gęściej przy dnie (UV.y → 0 góra, 1 dół)
    if (bottom_boost > 0.0) {
        float depth = smoothstep(cut, 1.0, UV.y); // 0 przy powierzchni, 1 przy dnie
        float depth_factor = mix(1.0, 1.0 + bottom_boost, depth);
        a *= depth_factor;
    }

    if (a < 0.001) {
        discard;
    }

    COLOR = vec4(fog_color.rgb, fog_color.a * clamp(a, 0.0, 1.0));
}
