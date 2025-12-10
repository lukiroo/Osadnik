shader_type canvas_item;

// Poziom wypełnienia od dołu (0 = pusto, 1 = pełno)
uniform float level01 : hint_range(0.0, 1.0) = 0.0;

// Miękkość krawędzi menisku w pikselach tekstury
uniform float edge_softness_px : hint_range(0.0, 8.0) = 0.0;

// Gdy true, przesuwa UV tak, żeby wierzch płynu był zawsze w tym samym miejscu
uniform bool scroll_uv = true;

// Maska kształtu szkła (np. LiquidBody)
uniform bool use_mask = false;
uniform sampler2D mask_tex;
// 1.0/width, 1.0/height maski – służy do przesunięć w pikselach
uniform vec2 mask_texel = vec2(0.0);
// Jak mocno „nadgryza” brzegi (0 = brak efektu)
uniform float wall_softness_px : hint_range(0.0, 8.0) = 0.0;

// Wzmacnia menisk w wąskim pasku nad poziomem cieczy
uniform float meniscus_boost : hint_range(0.0, 2.0) = 0.0;
uniform float meniscus_band_px : hint_range(0.5, 4.0) = 1.0;

void fragment() {
    // Kopiuje UV do lokalnej zmiennej
    vec2 uv = UV;

    // Oblicza położenie menisku (0 = góra, 1 = dół)
    float cut = 1.0 - level01;

    // Przelicza miękkość przejścia z pikseli na UV
    float soft_uv = edge_softness_px * TEXTURE_PIXEL_SIZE.y;
    if (soft_uv <= 0.0) {
        // Zostawia minimalne wygładzenie na 1 piksel
        soft_uv = TEXTURE_PIXEL_SIZE.y;
    }

    // Maska poziomu: powyżej menisku ~0, poniżej ~1
    float level_mask = smoothstep(cut - soft_uv, cut + soft_uv, uv.y);

    // Jeśli ma przewijać UV, przesuwa teksturę tak, żeby wierzch cieczy wypadł przy y = 0
    if (scroll_uv) {
        uv.y = clamp(uv.y - cut, 0.0, 1.0);
    }

    // Czyta kolor płynu z tekstury
    vec4 col = texture(TEXTURE, uv);

    // Bazowa alfa wynikająca z kształtu szkła / płynu
    float clip_a;

    if (use_mask) {
        // Używa osobnej maski kształtu (np. LiquidBody)
        float a0 = texture(mask_tex, UV).a;

        if (wall_softness_px > 0.0) {
            // Delikatnie „ścina” krawędzie, patrzy na sąsiednie piksele maski
            vec2 wpx = mask_texel * wall_softness_px;
            float aN = texture(mask_tex, UV + vec2( 0.0, -wpx.y)).a;
            float aS = texture(mask_tex, UV + vec2( 0.0,  wpx.y)).a;
            float aE = texture(mask_tex, UV + vec2(  wpx.x, 0.0)).a;
            float aW = texture(mask_tex, UV + vec2( -wpx.x, 0.0)).a;
            float min_wall = min(min(aN, aS), min(aE, aW));
            clip_a = a0 * min_wall;
        } else {
            clip_a = a0;
        }
    } else {
        // Bez maski – bierze kształt z alfy samej tekstury płynu
        float a0 = texture(TEXTURE, UV).a;

        if (wall_softness_px > 0.0) {
            // Ten sam efekt „erozji”, tylko oparty na TEXTURE
            vec2 wpx = TEXTURE_PIXEL_SIZE * wall_softness_px;
            float aN = texture(TEXTURE, UV + vec2( 0.0, -wpx.y)).a;
            float aS = texture(TEXTURE, UV + vec2( 0.0,  wpx.y)).a;
            float aE = texture(TEXTURE, UV + vec2(  wpx.x, 0.0)).a;
            float aW = texture(TEXTURE, UV + vec2( -wpx.x, 0.0)).a;
            float min_wall = min(min(aN, aS), min(aE, aW));
            clip_a = a0 * min_wall;
        } else {
            clip_a = a0;
        }
    }

    // Domyślne wzmocnienie menisku (1.0 = brak zmian)
    float boost = 1.0;

    // Jeżeli ma podbijać menisk, rysuje wąski, mocniejszy pasek tuż nad poziomem
    if (meniscus_boost > 0.0) {
        float band_uv = meniscus_band_px * TEXTURE_PIXEL_SIZE.y;
        if (band_uv <= 0.0) {
            band_uv = TEXTURE_PIXEL_SIZE.y;
        }
        // Używa uv.y po przewinięciu – menisk siedzi wtedy blisko y ≈ 0
        float line_factor = 1.0 - smoothstep(0.0, band_uv, uv.y);
        boost = 1.0 + meniscus_boost * line_factor;
    }

    // Łączy alfę tekstury z maską kształtu, poziomem cieczy i ewentualnym boostem menisku
    float out_a = col.a * clip_a * level_mask * boost;
    out_a = clamp(out_a, 0.0, 1.0);

    // Zapisuje wynikowy kolor (RGB z tekstury, A po modyfikacjach)
    COLOR = vec4(col.rgb, out_a);
}
