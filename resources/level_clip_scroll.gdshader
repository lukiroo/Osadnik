shader_type canvas_item;

/// 0 = pusto, 1 = pełno (od dna do wylotu)
uniform float level01 : hint_range(0.0, 1.0) = 0.0;

/// miękka krawędź menisku (px w TEKSTURZE; 0 = binaryjna)
uniform float edge_softness_px : hint_range(0.0, 8.0) = 0.0;

/// przewijanie UV, by top tekstury „jechał” z poziomem
uniform bool scroll_uv = true;

/// [opcjonalnie] maska kształtu (np. LiquidBody), żeby nic nie wychodziło poza szkło
uniform bool use_mask = false;
uniform sampler2D mask_tex;
uniform vec2 mask_texel = vec2(0.0); // ustaw z GDScript: (1.0/width, 1.0/height)
uniform float wall_softness_px : hint_range(0.0, 8.0) = 0.0; // 0 = brak „erozji” krawędzi

/// [opcjonalnie] wzmocnij widoczność menisku (alfa) w wąskim pasie
uniform float meniscus_boost : hint_range(0.0, 2.0) = 0.0; // 0 = wyłączone
uniform float meniscus_band_px : hint_range(0.5, 4.0) = 1.0; // grubość pasa (px w TEKSTURZE)

void fragment() {
    // 1) wyznacz poziom i szerokość przejścia
    float cut = 1.0 - level01;

    // Jeśli edge_softness_px == 0 → użyj szerokości zależnej od ekranu (fwidth) dla ostrego „stepa”.
    // W przeciwnym razie zrób miękką strefę o zadanej liczbie pikseli tekstury.
    float soft_uv;
    if (edge_softness_px <= 0.0) {
        // fwidth(UV.y) to różnica UV między sąsiednimi pikselami – bardzo wąska, ale stabilna.
        soft_uv = fwidth(UV.y);
    } else {
        soft_uv = edge_softness_px * TEXTURE_PIXEL_SIZE.y;
    }

    // Maska poziomu (0 powyżej, 1 poniżej) z wąskim przejściem
    float level_mask = smoothstep(cut - soft_uv, cut + soft_uv, UV.y);

    // 2) przewiń UV tak, by górna krawędź tekstury (y==0) była zawsze na aktualnym poziomie
    vec2 uv = UV;
    if (scroll_uv) {
        uv.y = clamp(UV.y - cut, 0.0, 1.0);
    }

    vec4 col = texture(TEXTURE, uv);

    // 3) clip kształtem probówki
    float clip_a;
    if (use_mask) {
        float a0 = texture(mask_tex, UV).a;
        if (wall_softness_px > 0.0) {
            vec2 wpx = mask_texel * wall_softness_px;
            float aN = texture(mask_tex, UV + vec2( 0.0, -wpx.y)).a;
            float aS = texture(mask_tex, UV + vec2( 0.0,  wpx.y)).a;
            float aE = texture(mask_tex, UV + vec2(  wpx.x, 0.0)).a;
            float aW = texture(mask_tex, UV + vec2( -wpx.x, 0.0)).a;
            clip_a = a0 * min(min(aN, aS), min(aE, aW));
        } else {
            clip_a = a0;
        }
    } else {
        float a0 = texture(TEXTURE, UV).a;
        if (wall_softness_px > 0.0) {
            vec2 wpx = TEXTURE_PIXEL_SIZE * wall_softness_px;
            float aN = texture(TEXTURE, UV + vec2( 0.0, -wpx.y)).a;
            float aS = texture(TEXTURE, UV + vec2( 0.0,  wpx.y)).a;
            float aE = texture(TEXTURE, UV + vec2(  wpx.x, 0.0)).a;
            float aW = texture(TEXTURE, UV + vec2( -wpx.x, 0.0)).a;
            clip_a = a0 * min(min(aN, aS), min(aE, aW));
        } else {
            clip_a = a0;
        }
    }

    // 4) (opcjonalnie) wzmocnij alfę w bardzo wąskim paśmie przy samym menisku (uv.y ≈ 0)
    float boost = 1.0;
    if (meniscus_boost > 0.0) {
        float band_uv = max(TEXTURE_PIXEL_SIZE.y, meniscus_band_px * TEXTURE_PIXEL_SIZE.y);
        float line_factor = 1.0 - smoothstep(0.0, band_uv, uv.y);
        boost = 1.0 + meniscus_boost * line_factor;
    }

    // 5) wynik – kolor z tekstury, alfa przycięta kształtem i poziomem, z ewentualnym boostem
    float out_a = col.a * clip_a * level_mask * boost;
    COLOR = vec4(col.rgb, clamp(out_a, 0.0, 1.0));
}
