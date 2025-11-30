shader_type canvas_item;

// 0 = żółty płomień "bez powietrza", 1 = niebieski płomień "z powietrzem"
uniform int  flame_mode       : hint_range(0, 1) = 0;

// Ogólna jasność
uniform float brightness      : hint_range(0.0, 3.0) = 1.4;

// Siła migotania
uniform float flicker_strength: hint_range(0.0, 0.5) = 0.18;

// Skala wysokości płomienia (1.0 = normalny, >1.0 = wyższy)
// Używana np. przy próbie płomieniowej (1.2 dla testu barwnego)
uniform float height_scale    : hint_range(0.5, 2.0) = 1.0;

// Kolory bazowe dwóch trybów
uniform vec4 yellow_color = vec4(1.0, 0.80, 0.30, 1.0); // trochę jaśniejszy żółty
uniform vec4 blue_color   = vec4(0.35, 0.95, 1.0, 1.0); // jaśniejszy niebieski

// Kolor testowy dla próby płomieniowej (np. Ba2+ → zielony, Sr2+ → czerwony itd.)
uniform bool use_test_color = false;
uniform vec4 test_color     = vec4(1.0, 0.9, 0.4, 1.0); // nadpisywane z kodu
uniform float test_mix      = 0.8;  // ile test_color domieszamy do bazowego (0..1)

void fragment()
{
	// UV 0..1, środek płomienia w x=0.5, dół w y=0.0, góra w y=1.0
	vec2 uv = UV;

	// „Fizyczna” wysokość w teksturze – nie modyfikujemy UV
	float y = clamp(uv.y, 0.0, 1.0);

	// x = 0 w środku, zakres -1..1
	float x = (uv.x - 0.5) * 2.0;

	// Delikatne falowanie tylko w górnej części płomienia
	float wobble = sin(y * 8.0 + TIME * 6.0) * (1.0 - y) * 0.03;
	x += wobble;

	// --- Skala wysokości ---
	float user_scale = max(height_scale, 0.01);   // z uniformu
	float base_vertical_scale = 1.25;            // bazowe „ściśnięcie” w pionie
	// Żółty płomień jest ~30% wyższy od niebieskiego
	float mode_scale = (flame_mode == 0) ? 1.3 : 1.0;
	// Im większy mode_scale → mniejszy vertical_scale → bardziej wydłużony płomień
	float vertical_scale = base_vertical_scale / (user_scale * mode_scale);

	// Kształt płomienia: elipsa / kropla
	vec2 flame_p = vec2(x * 0.65, (1.0 - y) * vertical_scale);
	float dist = length(flame_p);

	// Maska kształtu (1.0 w środku, 0.0 poza płomieniem)
	float flame_mask = 1.0 - smoothstep(0.45, 0.9, dist);

	// Zawężenie podstawy (żeby nie była kwadratowa)
	float base_cut = smoothstep(0.0, 0.1, y);
	flame_mask *= base_cut;

	// Jeśli praktycznie nie ma płomienia w tym miejscu – rysujemy przezroczystość.
	if (flame_mask <= 0.01)
	{
		COLOR = vec4(0.0);
	}
	else
	{
		// Rdzeń płomienia jaśniejszy w środku i bliżej podstawy
		float core_factor = 1.0 - smoothstep(0.0, 0.4, dist);
		float vertical = 1.0 - y; // dół jaśniejszy niż góra

		// Wybór koloru bazowego (tylko dwa tryby)
		vec4 base_color = (flame_mode == 0) ? yellow_color : blue_color;

		// Test płomieniowy: mieszamy bazę z test_color tylko dla płomienia niebieskiego
		if (use_test_color && flame_mode == 1)
		{
			float mix_val = clamp(test_mix, 0.0, 1.0);
			base_color.rgb = mix(base_color.rgb, test_color.rgb, mix_val);
		}

		// Delikatne „oddychanie” jasności – szybkie, ale o małej amplitudzie
		float flicker = 1.0 + sin(TIME * 10.0 + y * 7.0) * flicker_strength;

		// Ostateczna intensywność – trochę podbita
		float intensity = flame_mask
			* (0.5 + 0.7 * core_factor)   // mocniejszy rdzeń
			* (0.7 + 0.5 * vertical)      // jaśniejszy dół
			* flicker;

		vec3 color = base_color.rgb * intensity * brightness;
		float alpha = flame_mask * base_color.a;

		COLOR = vec4(color, alpha);
	}
}
