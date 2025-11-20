shader_type canvas_item;

uniform float progress : hint_range(0.0, 1.0) = 0.0; // gęstość igiełek
uniform vec4  crystal_color : source_color = vec4(1.0);
uniform float grain = 160.0;     // gęstość komórek (większa = drobniej)
uniform float edge_soft = 0.5;   // miękkość krawędzi drobinek

// Opcjonalne: maska i poziom napełnienia
uniform bool use_mask = false;
uniform sampler2D mask_tex;
uniform vec2  mask_texel = vec2(0.0);
uniform float level01 = 1.0;     // 0..1 (ta sama konwencja co w TurbidityOverlay)

float hash(vec2 p){
	p = fract(p * vec2(234.34, 435.345));
	p += dot(p, p + 34.345);
	return fract(p.x * p.y);
}

void fragment() {
	vec2 uv = UV;

	// Maska poziomu cieczy: 1 poniżej menisku, 0 powyżej
	float level_mask = 1.0 - step(level01, uv.y);

	// prosty "speckle" na siatce komórek
	vec2 cell = floor(uv * grain);
	float r = hash(cell);

	// im większy progress, tym więcej komórek zapala się
	float on = step(r, progress);

	// delikatny "kształt drobinki" w środku komórki
	vec2 f = fract(uv * grain);
	float d = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y)); // odległość do krawędzi komórki
	float shape = smoothstep(0.0, 0.25, d); // miękka kropeczka
	float a = on * pow(shape, 1.0 + edge_soft);

	// maska kształtu szkła (opcjonalnie)
	if (use_mask) {
		vec4 m = texture(mask_tex, UV);
		a *= m.a;
	}

	// zastosuj maskę poziomu
	a *= level_mask;

	COLOR = vec4(crystal_color.rgb, crystal_color.a * a);
}
