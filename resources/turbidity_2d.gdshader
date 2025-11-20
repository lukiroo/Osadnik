shader_type canvas_item;

/* siła mętności + kolor */
uniform float turbidity : hint_range(0.0,1.0) = 0.0;
uniform vec4  fog_color : source_color = vec4(1.0,1.0,1.0,1.0);

/* POZIOM cieczy (z kodu) */
uniform float level01 : hint_range(0.0,1.0) = 0.0;            // 0=pusto, 1=pełno
uniform float level_softness_px : hint_range(0.0,8.0) = 2.0;  // miękki menisk w px
uniform float level_scale = 1.0;   // dopasowanie UV pionowe (kalibracja)
uniform float level_bias  = 0.0;   // dopasowanie UV offset (kalibracja)

/* SZUM – tekstura LUB proceduralny fallback */
uniform bool use_procedural_noise = false;
uniform sampler2D noise_tex;
uniform float noise_scale   = 6.0;
uniform float flow_speed    = 0.12;
uniform float noise_strength = 0.6;

/* głębia i brzegi */
uniform float top_clear_zone = 0.10;   // trochę czystsze u góry
uniform float depth_bias     = 0.20;   // „gęściej” w całej objętości (0 = klasyczne, 1 = bardzo gęsto)
uniform float wall_softness_px : hint_range(0.0,8.0) = 2.0; // miękki brzeg przy ściankach

/* front opadania osadu od góry w dół:
   settle_front = 0.0  -> mętność tylko na samej górze,
   settle_front = 1.0  -> mętność w całej kolumnie cieczy */
uniform float settle_front : hint_range(0.0,1.0) = 1.0;
uniform float settle_softness : hint_range(0.0,0.3) = 0.12;

/* --- proceduralny fallback --- */
float hash(vec2 p) {
    p = vec2(dot(p, vec2(127.1,311.7)), dot(p, vec2(269.5,183.3)));
    return fract(sin(p.x + p.y) * 43758.5453123);
}

float noise2d(vec2 p){
    vec2 i = floor(p);
    vec2 f = fract(p);
    float a = hash(i + vec2(0.0,0.0));
    float b = hash(i + vec2(1.0,0.0));
    float c = hash(i + vec2(0.0,1.0));
    float d = hash(i + vec2(1.0,1.0));
    vec2 u = f*f*(3.0-2.0*f);
    return mix(mix(a,b,u.x), mix(c,d,u.x), u.y);
}

void fragment() {
    // kształt = alfa TEGO sprite’a (jak wcześniej, zero prostokątów)
    float inside = texture(TEXTURE, UV).a;

    // miękkie „odjechanie” od ścian na bazie własnej alfy
    vec2 px = TEXTURE_PIXEL_SIZE * wall_softness_px;
    float aN = texture(TEXTURE, UV + vec2( 0.0,-px.y)).a;
    float aS = texture(TEXTURE, UV + vec2( 0.0, px.y)).a;
    float aE = texture(TEXTURE, UV + vec2( px.x, 0.0)).a;
    float aW = texture(TEXTURE, UV + vec2(-px.x, 0.0)).a;
    float interior = min(min(aN,aS), min(aE,aW));

    // przycięcie do poziomu (z dopasowaniem UV, jeśli trzeba)
    float lvl = clamp(level01 * level_scale + level_bias, 0.0, 1.0);
    float cut  = 1.0 - lvl; // UV.y: 0=góra
    float soft = max(1e-6, level_softness_px * TEXTURE_PIXEL_SIZE.y);
    float level_mask = clamp(smoothstep(0.0, 1.0, (UV.y - cut) / soft), 0.0, 1.0);

    // szum „pływający”
    vec2 uv1 = UV * noise_scale + vec2( TIME*flow_speed, -TIME*flow_speed*0.5 );
    vec2 uv2 = UV * (noise_scale*0.5) + vec2(-TIME*flow_speed*0.7, TIME*flow_speed*0.33);
    float n = use_procedural_noise
        ? (noise2d(uv1)*0.6 + noise2d(uv2)*0.4)
        : (texture(noise_tex, uv1).r*0.6 + texture(noise_tex, uv2).r*0.4);

    // gęściej w głębi (UV.y ~ 1.0 = dół), ale nie aż tak ekstremalnie
    float depth = smoothstep(top_clear_zone, 1.0, UV.y);
    depth = mix(depth, 1.0, depth_bias);   // depth_bias ~0.2 = lekko „zagęszcza” całą kolumnę

    // podstawowa gęstość mgły
    float fog_a = turbidity * depth * (0.6 + noise_strength * (n - 0.5) * 2.0);
    fog_a = clamp(fog_a, 0.0, 1.0);

    // FRONT OPADANIA: mętność zaczyna się przy powierzchni i schodzi w dół
    float front = clamp(settle_front, 0.0, 1.0);
    // dla UV.y < front → 1, poniżej frontu wygaszamy
    float front_mask = smoothstep(-settle_softness, settle_softness, front - UV.y);
    fog_a *= front_mask;

    // final: kształt × „odjechanie” od ścian × POD poziomem
    fog_a *= inside * interior * level_mask;

    COLOR = vec4(fog_color.rgb, fog_color.a * fog_a);
}
