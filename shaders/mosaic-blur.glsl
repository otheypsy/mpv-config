//!HOOK MAIN
//!BIND HOOKED
//!DESC Mosaic-Blur (Pass 1, 64px)

#define MOSAIC_SIZE 64.0  // Size of each mosaic block (in pixels)
#define INTENSITY 1.0     // Intensity of the mosaic effect (0.0 to 1.0)

vec4 hook() {
    vec2 tex_size = HOOKED_size;
    vec2 tex_coord = HOOKED_pos * tex_size;

    vec2 mosaic_coord = floor(tex_coord / MOSAIC_SIZE) * MOSAIC_SIZE;
    vec2 mosaic_tex_coord = mosaic_coord / tex_size;
    vec4 mosaic_color = textureLod(HOOKED_raw, mosaic_tex_coord, 0.0);
    vec4 original_color = textureLod(HOOKED_raw, HOOKED_pos, 0.0);
    vec4 final_color = mix(original_color, mosaic_color, INTENSITY);

    return final_color;
}

//!HOOK MAIN
//!BIND HOOKED
//!DESC Mosaic-Blur (Pass 2, 32px)

#define MOSAIC_SIZE 32.0  // Size of each mosaic block (in pixels)
#define INTENSITY 1.0     // Intensity of the mosaic effect (0.0 to 1.0)

vec4 hook() {
    vec2 tex_size = HOOKED_size;
    vec2 tex_coord = HOOKED_pos * tex_size;

    vec2 mosaic_coord = floor(tex_coord / MOSAIC_SIZE) * MOSAIC_SIZE;
    vec2 mosaic_tex_coord = mosaic_coord / tex_size;
    vec4 mosaic_color = textureLod(HOOKED_raw, mosaic_tex_coord, 0.0);
    vec4 original_color = textureLod(HOOKED_raw, HOOKED_pos, 0.0);
    vec4 final_color = mix(original_color, mosaic_color, INTENSITY);

    return final_color;
}
