shader_type canvas_item;

// Określa poziom wypełnienia od dołu (0 = pusto, 1 = pełne)
uniform float level01 : hint_range(0.0, 1.0) = 0.0;

// Określa miękkość krawędzi wypełnienia w pikselach
uniform float edge_px : hint_range(0.0, 4.0) = 1.0;

void fragment() {
    // Pobiera kolor z tekstury
    vec4 tex = texture(TEXTURE, UV);

    // Wyznacza granicę wypełnienia w UV (0 = góra, 1 = dół)
    float cut = 1.0 - level01;

    // Przelicza miękką krawędź z pikseli na przestrzeń UV
    float soft = edge_px * TEXTURE_PIXEL_SIZE.y;

    // Tworzy maskę wypełnienia: 0 powyżej poziomu, 1 poniżej, z miękkim przejściem
    float fill_mask = smoothstep(cut - soft, cut + soft, UV.y);

    // Skaluje alfę tekstury maską wypełnienia
    tex.a *= fill_mask;

    // Zapisuje wynikowy kolor piksela
    COLOR = tex;
}
