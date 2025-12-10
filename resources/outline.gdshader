shader_type canvas_item;

// Określa, czy rysuje obrys podświetlenia
uniform bool highlight = false;

// Określa moc podświetlenia (0–1)
uniform float highlight_strength : hint_range(0.0, 1.0) = 0.0;

// Określa kolor obrysu (lekko żółtawy)
uniform vec4 outline_color : source_color = vec4(1.0, 0.95, 0.2, 1.0);

// Określa grubość obrysu w pikselach tekstury
uniform float outline_width = 10.0;

// Określa próg alfy, powyżej którego traktuje piksel jako „pełny”
uniform float alpha_threshold = 0.35;

void fragment() {
    // Pobiera kolor i alfę z tekstury
    vec4 tex = texture(TEXTURE, UV);
    float a = tex.a;

    // Przelicza grubość obrysu na przesunięcie w przestrzeni UV
    vec2 px = TEXTURE_PIXEL_SIZE * outline_width;

    // Sprawdza alfę sąsiadów w ośmiu kierunkach
    float a_n  = texture(TEXTURE, UV + vec2( 0.0, -px.y)).a;
    float a_s  = texture(TEXTURE, UV + vec2( 0.0,  px.y)).a;
    float a_e  = texture(TEXTURE, UV + vec2(  px.x, 0.0)).a;
    float a_w  = texture(TEXTURE, UV + vec2(-px.x, 0.0)).a;
    float a_ne = texture(TEXTURE, UV + vec2(  px.x, -px.y)).a;
    float a_nw = texture(TEXTURE, UV + vec2(-px.x, -px.y)).a;
    float a_se = texture(TEXTURE, UV + vec2(  px.x,  px.y)).a;
    float a_sw = texture(TEXTURE, UV + vec2(-px.x,  px.y)).a;

    // Sprawdza, czy któryś sąsiad ma „pełną” alfę
    bool has_solid_neighbor =
        a_n  > alpha_threshold ||
        a_s  > alpha_threshold ||
        a_e  > alpha_threshold ||
        a_w  > alpha_threshold ||
        a_ne > alpha_threshold ||
        a_nw > alpha_threshold ||
        a_se > alpha_threshold ||
        a_sw > alpha_threshold;

    // Określa, czy piksel leży przy krawędzi (on sam jest półprzezroczysty, sąsiad pełny)
    bool near_edge = (a < alpha_threshold) && has_solid_neighbor;

    // Startowo przyjmuje oryginalny kolor tekstury
    vec4 color_out = tex;

    // Jeśli ma podświetlać i piksel leży na krawędzi, to nakłada obrys
    if (highlight && highlight_strength > 0.0 && near_edge) {
        float s = clamp(highlight_strength, 0.0, 1.0);
        vec4 oc = outline_color;
        oc.a *= s;

        // Miesza kolor obrysu z kolorem tekstury (obrys „przykrywa” tło)
        color_out.rgb = tex.rgb * (1.0 - oc.a) + oc.rgb * oc.a;
        color_out.a   = max(tex.a, oc.a);
    }

    // Zapisuje wynikowy kolor
    COLOR = color_out;
}
