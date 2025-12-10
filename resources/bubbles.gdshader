shader_type canvas_item;

// Określa, czy w płynie mają pojawiać się bąbelki „wrzenia”
uniform bool boiling = false;

// Liczba pionowych kolumn bąbelków
uniform float bubbles_density = 10.0;

// Bazowy promień bąbelka w przestrzeni UV
uniform float bubble_radius = 0.02;

// Określa, jak mocno bąbelek rozjaśnia kolor pod sobą
uniform float bubble_alpha = 0.3;

// Prosty pseudo-losowy generator z jednej liczby
float rand(float n) {
    return fract(sin(n * 31.123) * 12345.678);
}

void fragment() {
    // Pobiera kolor z tekstury wejściowej
    vec4 tex = texture(TEXTURE, UV);
    vec3 col = tex.rgb;
    float alpha = tex.a;

    // Domyślnie nie dodaje bąbelków
    float bubble_mask = 0.0;

    // Sprawdza, czy ma generować bąbelki (wrzenie + sensowna gęstość)
    if (boiling && bubbles_density > 0.0) {
        float lanes = bubbles_density;                  // Ustala liczbę pionów
        float lane_id = floor(UV.x * lanes);            // Wyznacza numer pionu dla danego piksela
        float lane_center_x = (lane_id + 0.5) / lanes;  // Ustala środek pionu w osi X

        // Dodaje po dwa bąbelki na każdy pion
        for (int i = 0; i < 2; i++) {
            float seed = lane_id + float(i) * 10.0;     // Wyznacza ziarno dla danego bąbelka

            // Wylicza losową prędkość w zakresie ok. 0.3–0.9
            float speed = 0.3 + 0.6 * rand(seed);

            // Wylicza losową fazę startową, żeby bąbelki nie były zsynchronizowane
            float phase = rand(seed + 1.0);

            // t w [0,1] – pozycja w cyklu ruchu bąbelka
            float t = fract(TIME * speed + phase);

            // Przesuwa bąbelek z dołu do góry (trochę poniżej dna do trochę nad powierzchnię)
            float y = 1.1 - 1.2 * t;

            // Dodaje lekki poziomy jitter, żeby bąbel nie leciał po idealnej linii
            float jitter = (rand(seed + 2.0) - 0.5) * 0.08;
            vec2 center = vec2(lane_center_x + jitter, y);

            // Nadaje promieniowi lekką losową wariację (ok. 70–140% wartości bazowej)
            float r = bubble_radius * (0.7 + 0.7 * rand(seed + 3.0));

            // Liczy odległość piksela od środka bąbelka
            float d = length(UV - center);

            // Tworzy miękką maskę bąbelka (większa wartość bliżej środka)
            float m = smoothstep(r, r * 0.6, d);

            // Zapamiętuje najsilniejszy bąbelek w tym miejscu
            if (m > bubble_mask) {
                bubble_mask = m;
            }
        }
    }

    // Rozjaśnia kolor tam, gdzie wypadają bąbelki
    col += bubble_alpha * bubble_mask;

    // Zapisuje wynikowy kolor
    COLOR = vec4(col, alpha);
}
