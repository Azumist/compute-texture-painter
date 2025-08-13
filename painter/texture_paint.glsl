#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba8, set = 0, binding = 0) uniform restrict image2D output_image;
layout(set = 0, binding = 1) uniform sampler2D brush_texture;

layout(push_constant, std430) uniform Params {
    vec4 brush_color;        // 16 bytes
    vec3 local_hit_point;    // 12 bytes
    float brush_size;        // 4 bytes
    
    vec3 vertex_0;           // 12 bytes
    float texture_width;     // 4 bytes
    
    vec3 vertex_1;           // 12 bytes  
    float texture_height;    // 4 bytes
    
    vec3 vertex_2;           // 12 bytes
    float brush_rotation;    // 4 bytes
    
    vec2 uv_0;               // 8 bytes
    vec2 uv_1;               // 8 bytes
    vec2 uv_2;               // 8 bytes
    vec2 _pad1;              // 8 bytes padding
    //total: 128 bytes
} params;

vec3 get_barycentric_coords(vec3 point, vec3 v0, vec3 v1, vec3 v2) {
    vec3 v0v1 = v1 - v0;
    vec3 v0v2 = v2 - v0;
    vec3 v0p = point - v0;

    float dot00 = dot(v0v2, v0v2);
    float dot01 = dot(v0v2, v0v1);
    float dot02 = dot(v0v2, v0p);
    float dot11 = dot(v0v1, v0v1);
    float dot12 = dot(v0v1, v0p);

    float denom = dot00 * dot11 - dot01 * dot01;
    if (abs(denom) < 0.0001) return vec3(0, 0, 0); //degenerate triangle

    float inv_denom = 1.0 / (dot00 * dot11 - dot01 * dot01);
    float u = (dot11 * dot02 - dot01 * dot12) * inv_denom;
    float v = (dot00 * dot12 - dot01 * dot02) * inv_denom;
    float w = 1.0 - u - v;

    return vec3(w, v, u);
}

mat2 rotate2D(float angle) {
    float s = sin(angle);
    float c = cos(angle);
    return mat2(c, -s, s, c);
}

void main() {
    ivec2 texel_coords = ivec2(gl_GlobalInvocationID.xy);
    ivec2 texture_size = ivec2(params.texture_width, params.texture_height);

    if ((texel_coords.x > texture_size.x) || (texel_coords.y > texture_size.y)) {
		return;
	}

    vec3 bary = get_barycentric_coords(params.local_hit_point, params.vertex_0, params.vertex_1, params.vertex_2);
    vec2 hit_uv = params.uv_0 * bary.x + params.uv_1 * bary.y + params.uv_2 * bary.z;
    vec2 uv = (vec2(texel_coords) + 0.5) / vec2(texture_size);

    vec2 offset = uv - hit_uv;
    float brush_radius_uv = params.brush_size / max(params.texture_width, params.texture_height);

    if (length(offset) > brush_radius_uv) {
        return;
    }

    vec2 brush_uv = (rotate2D(params.brush_rotation) * (offset / brush_radius_uv)) * 0.5 + 0.5;

    if (brush_uv.x < 0.0 || brush_uv.x > 1.0 || brush_uv.y < 0.0 || brush_uv.y > 1.0) {
        return;
    }

    vec4 brush = texture(brush_texture, brush_uv);
    vec4 bg_color = imageLoad(output_image, texel_coords);
    vec4 brush_color = vec4(params.brush_color.rgb * brush.rgb, params.brush_color.a * brush.a);
    vec4 final_color = mix(bg_color, brush_color, brush_color.a);

    imageStore(output_image, texel_coords, final_color);

    // no brush mode, todo: implement switching later
    // float hit_distance = length(uv - hit_uv);
    // float brush_radius_uv = params.brush_size / max(params.texture_width, params.texture_height);

    // if (hit_distance <= brush_radius_uv) {
    //     float falloff = 1.0 - (hit_distance / brush_radius_uv);
    //     falloff = smoothstep(0.0, 1.0, falloff);

    //     vec4 bg_color = imageLoad(output_image, texel_coords);
    //     vec4 brush_color = vec4(params.brush_color.rgb, params.brush_color.a * falloff);
    //     vec4 final_color = mix(bg_color, brush_color, brush_color.a);
        
    //     imageStore(output_image, texel_coords, final_color);
    // }
}

