shader_type canvas_item;

// 0 = żółty płomień, 1 = niebieski płomień
uniform int  flame_mode        : hint_range(0, 1) = 0;

// Określa ogólną jasność płomienia
uniform float brightness       : hint_range(0.0, 3.0) = 1.8;

// Określa siłę migotania
uniform float flicker_strength : hint_range(0.0, 0.5) = 0.18;

// Skaluje wysokość płomienia (1.0 = normalny, >1.0 = wyższy)
uniform float height_scale     : hint_range(0.5, 2.0) = 1.0;

// Określa kolory bazowe dwóch trybów
uniform vec4 yellow_color = vec4(1.0, 0.82, 0.32, 1.0);
uniform vec4 blue_color   = vec4(0.35, 0.95, 1.0, 1.0);

// Kolor dla próby płomieniowej
uniform bool use_test_color = false;
uniform vec4 test_color     = vec4(1.0, 0.9, 0.4, 1.0); // nadpisywane z kodu
uniform float test_mix      = 0.8;  // domieszka koloru testu do koloru bazy

void fragment() {
    // Przepisuje UV, żeby łatwiej się do nich odwoływać
    vec2 uv = UV;

    // Odcina y do zakresu [0,1]
    float y = clamp(uv.y, 0.0, 1.0);

    // Przesuwa x tak, żeby 0 było na środku i skaluje do [-1,1]
    float x = (uv.x - 0.5) * 2.0;

    // Dodaje falowanie płomienia (lekko odchyla środek w poziomie)
    float wobble = sin(y * 8.0 + TIME * 6.0) * (1.0 - y) * 0.03;
    x += wobble;

    // Skala wysokości
    float user_scale = max(height_scale, 0.01);   // chroni przed dzieleniem przez 0
    float base_vertical_scale = 1.25;            // bazowe „ściśnięcie” w pionie
    // Żółty płomień jest trochę wyższy od niebieskiego
    float mode_scale = (flame_mode == 0) ? 1.3 : 1.0;
    float vertical_scale = base_vertical_scale / (user_scale * mode_scale);

    // Wyznacza kształt płomienia w postaci „kropli”
    vec2 flame_p = vec2(x * 0.65, (1.0 - y) * vertical_scale);
    float dist = length(flame_p);

    // Tworzy maskę kształtu 0–1
    float flame_mask = 1.0 - smoothstep(0.45, 0.9, dist);

    // Zawęża podstawę płomienia przy palniku
    float base_cut = smoothstep(0.0, 0.1, y);
    flame_mask *= base_cut;

    // Jeśli w danym miejscu nie ma praktycznie płomienia, robi piksel całkowicie przezroczysty
    if (flame_mask <= 0.01) {
        COLOR = vec4(0.0);
    } else {
        // Wyznacza „rdzeń” płomienia – jaśniejszy w środku niż na brzegu
        float core_factor = 1.0 - smoothstep(0.0, 0.4, dist);

        // Dół płomienia jest jaśniejszy niż góra
        float vertical = 1.0 - y;

        // Wybiera bazowy kolor (żółty albo niebieski)
        vec4 base_color = (flame_mode == 0) ? yellow_color : blue_color;

        // Dla próby płomieniowej miesza kolor testowy z bazowym (tylko w trybie niebieskim)
        if (use_test_color && flame_mode == 1) {
            float m = clamp(test_mix, 0.0, 1.0);
            base_color.rgb = base_color.rgb * (1.0 - m) + test_color.rgb * m;
        }

        // Dodaje lekkie „oddychanie” jasności (migotanie)
        float flicker = 1.0 + sin(TIME * 10.0 + y * 7.0) * flicker_strength;

        // Liczy bazową intensywność płomienia (środek i dół mocniejsze)
        float raw_intensity = flame_mask
            * (0.5 + 0.7 * core_factor)
            * (0.7 + 0.5 * vertical)
            * flicker;

        // Ogranicza zakres intensywności
        float intensity = clamp(raw_intensity, 0.0, 1.5);

        // Dodaje minimalną jasność, żeby brzegi nie były zupełnie czarne
        float edge_fill = 0.3 + 0.7 * intensity;

        // Wylicza końcowy kolor – zawsze lekko świecący, najmocniej w rdzeniu
        vec3 color = base_color.rgb * edge_fill * brightness;

        // Ustawia alfę na podstawie maski kształtu
        float alpha = flame_mask * base_color.a;

        // Zapisuje wynikowy kolor płomienia
        COLOR = vec4(color, alpha);
    }
}
