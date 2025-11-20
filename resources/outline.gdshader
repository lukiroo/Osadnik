shader_type canvas_item;

uniform bool  highlight = false;
uniform float highlight_strength : hint_range(0,1) = 0.0;
uniform vec4  outline_color : source_color = vec4(1.0, 0.95, 0.2, 1.0); // bardziej żółty
uniform float outline_width = 10.0;     // grubość w px tekstury (zwiększ jeśli trzeba)
uniform float alpha_threshold = 0.35;   // większe = agresywniej wykrywa krawędź

void fragment() {
    vec4 tex = texture(TEXTURE, UV);
    float a  = tex.a;

    vec2 px = TEXTURE_PIXEL_SIZE * outline_width;

    float aN  = texture(TEXTURE, UV + vec2( 0.0, -px.y)).a;
    float aS  = texture(TEXTURE, UV + vec2( 0.0,  px.y)).a;
    float aE  = texture(TEXTURE, UV + vec2( px.x, 0.0)).a;
    float aW  = texture(TEXTURE, UV + vec2(-px.x, 0.0)).a;
    float aNE = texture(TEXTURE, UV + vec2( px.x, -px.y)).a;
    float aNW = texture(TEXTURE, UV + vec2(-px.x, -px.y)).a;
    float aSE = texture(TEXTURE, UV + vec2( px.x,  px.y)).a;
    float aSW = texture(TEXTURE, UV + vec2(-px.x,  px.y)).a;

    bool near_edge = (a < alpha_threshold) && (
        aN>alpha_threshold || aS>alpha_threshold || aE>alpha_threshold || aW>alpha_threshold ||
        aNE>alpha_threshold|| aNW>alpha_threshold|| aSE>alpha_threshold|| aSW>alpha_threshold
    );

    if (highlight && highlight_strength > 0.0 && near_edge) {
        vec4 outc = outline_color;
        outc.a *= clamp(highlight_strength, 0.0, 1.0);
        // mocniejsze mieszanie – żółć „wygryza” tło
        COLOR.rgb = mix(tex.rgb, outc.rgb, outc.a);
        COLOR.a   = max(tex.a, outc.a);
    } else {
        COLOR = tex;
    }
}
