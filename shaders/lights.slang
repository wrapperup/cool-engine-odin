float get_square_falloff_attenuation(float3 pos_to_light, float light_inv_radius) {
    let distance_square = dot(pos_to_light, pos_to_light);
    let factor = distance_square * light_inv_radius * light_inv_radius;
    let smooth_factor = saturate(1.0 - factor * factor);
    return (smooth_factor * smooth_factor) / max(distance_square, 1e-4);
}
