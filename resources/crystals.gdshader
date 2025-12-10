shader_type canvas_item;

uniform float progress : hint_range(0.0, 1.0) = 0.0; // Określa, ile komórek się „zapełnia”
uniform vec4  crystal_color : source_color = vec4(1.0);

// Określa gęstość siatki komórek (większa wartość = drobniejsze kryształki)
uniform float grain = 160.0;

// Określa miękkość krawędzi drobinek
uniform float edge_soft = 0.5;

// Opcjonalna maska kształtu szkła / probówki
uniform bool use_mask = false;
uniform sampler2D mask_tex;

// 0..1 – określa poziom napełnienia od dołu (0 = pusto, 1 = pełna probówka)
uniform float level01 = 1.0;

// Określa, jak szybko kryształki dryfują (mała wartość = bardzo powolny ruch)
uniform float drift_speed = 0.04;

// Określa, jak duży jest wychył kryształka w obrębie komórki (0..0.5)
uniform float drift_amount = 0.25;

// Prosta funkcja pseudo-losowa z wektora 2D
float hash(vec2 p) {
    p = fract(p * vec2(234.34, 435.345));
    p += dot(p, p + 34.345);
    return fract(p.x * p.y);
}

void fragment() {
    vec2 uv = UV;

    // --- Maska poziomu cieczy ---
    // UV.y = 0 u góry, 1 na dole.
    // level01 określa, jak wysoko sięga ciecz od dołu.
    float y_top = 1.0 - level01;

    // Kryształki pojawiają się tylko w cieczy (poniżej menisku)
    float level_mask = step(y_top, uv.y);

    // --- Siatka komórek i losowość ---
    vec2 cell = floor(uv * grain);  // Pobiera indeks komórki
    float r = hash(cell);           // Wyznacza losową wartość dla tej komórki

    // Im większy progress, tym więcej komórek się „zapala”
    float on = step(r, progress);

    // --- Powolny ruch kryształków w roztworze ---
    // Każda komórka dostaje własny kierunek i prędkość dryfu.
    float angle = hash(cell + 13.37) * 6.2831853; // Losuje kąt 0–2π
    vec2 dir = vec2(cos(angle), sin(angle));

    // Losowo modyfikuje prędkość, żeby nie wszystkie drobinki pływały tak samo
    float speed = drift_speed * (0.6 + 0.4 * hash(cell + 7.89));

    // Oblicza przesunięcie w przestrzeni komórki (0..1), bardzo powolne
    float t = TIME * speed;
    float drift_phase = sin(t); // Używa sinus, żeby ruch był wahadłowy, a nie liniowy
    vec2 drift = dir * (drift_phase * drift_amount);

    // --- Kształt drobinki wewnątrz komórki ---
    // Używa UV * grain, ale z dodanym dryfem (fract sprawia, że drobinka "krąży" w obrębie komórki)
    vec2 f = fract(uv * grain + drift);

    // Liczy odległość od krawędzi komórki (drobinka w środku komórki)
    float d = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y));

    // Tworzy miękką kropeczkę w środku komórki
    float shape = smoothstep(0.0, 0.25, d);

    // Łączy wszystko w jedną alfę: aktywna komórka + kształt drobinki
    float a = on * pow(shape, 1.0 + edge_soft);

    // --- Maska kształtu szkła (opcjonalnie) ---
    if (use_mask) {
        vec4 m = texture(mask_tex, UV);
        a *= m.a;
    }

    // --- Maska poziomu cieczy ---
    a *= level_mask;

    // Zapisuje wynikowy kolor kryształków
    COLOR = vec4(crystal_color.rgb, crystal_color.a * a);
}
