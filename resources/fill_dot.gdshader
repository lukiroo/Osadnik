shader_type canvas_item;

uniform float level01 : hint_range(0.0, 1.0) = 0.0;   // 0 = pusto, 1 = pełne
uniform float edge_px : hint_range(0.0, 4.0) = 1.0;   // lekkie wygładzenie krawędzi wypełnienia

void fragment() {
    vec4 tex = texture(TEXTURE, UV);
    // wypełnienie od dołu: zostaw to, co powyżej cut? (UV.y rośnie w dół)
    float cut  = 1.0 - level01;                          // granica w UV
    float soft = edge_px * TEXTURE_PIXEL_SIZE.y + 1e-6;  // miękka krawędź
    float mask = smoothstep(cut - soft, cut + soft, UV.y);

    COLOR = vec4(tex.rgb, tex.a * mask);
}
