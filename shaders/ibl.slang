import bindless;
import brdf;
import common;
import types;

struct PBR_Params {
    ImageCube env_map;
    Image2D dfg;
    Sampler env_sampler;
    Sampler default_sampler;
}

Vec3 evaluate_specular_ibl(PBR_Params params, Vec3 r, f32 perceptualRoughness) {
    // This assumes a 256x256 cubemap, with 9 mip levels
    let lod = 8.0 * perceptualRoughness;
    return params.env_map.sample_level(params.env_sampler, r, lod).rgb;
}

Vec3 sample_dfg(PBR_Params params, f32 NoV, f32 p_roughness) {
    // The LUT's v axis is perceptual roughness (squared inside the generator) —
    // sample with Vec2(NoV, perceptualRoughness), per Filament.
    // env_sampler, NOT default_sampler: the LUT must CLAMP_TO_EDGE. default_sampler
    // is REPEAT, which wraps the last half-texel of NoV around to the NoV~0 grazing
    // column — a bright circular blob on flat surfaces wherever the view is
    // perpendicular (and the mirrored error at grazing / roughness extremes).
    return params.dfg.sample(params.env_sampler, Vec2(NoV, p_roughness)).rgb;
}

// Specular-only IBL: the environment reflection term. Diffuse irradiance now comes from
// the DDGI probe volume (ddgi_sample), so this drops the SH diffuse part of evaluate_ibl.
Vec3 evaluate_specular_ibl_term(PBR_Params params, Vec3 n, Vec3 v, Vec3 f0, f32 p_roughness) {
    let f90 = saturate(dot(f0, Vec3(50.0 * 0.33)));
    let NoV = max(dot(n, v), 0.0);
    let r = reflect(-v, n);

    let Lld = evaluate_specular_ibl(params, r, p_roughness);
    let Ldfg = sample_dfg(params, NoV, p_roughness).rg;

    return (f0 * Ldfg.r + f90 * Ldfg.g) * Lld;
}

Vec3 evaluate_ibl(PBR_Params params, Vec3 n, Vec3 v, Vec3 diffuse_color, Vec3 f0, f32 p_roughness) {
    let NoV = max(dot(n, v), 0.0);

    let Lr = evaluate_specular_ibl_term(params, n, v, f0, p_roughness);
    let Ld = diffuse_color;

    return Lr + Ld;
}

// ---------------------------------------------------------------------------
// Reflection probes (box-projected local cubemaps)
// ---------------------------------------------------------------------------

// Influence weight of a probe at a world point: 1 in the interior core, fading INWARD to 0 at the
// box walls over blend_distance (0 outside the box). Box projection is only valid inside the box,
// so the weight must vanish at the walls.
f32 reflection_probe_weight(ReflectionProbe probe, Vec3 pos_ws) {
    let d = abs(pos_ws - probe.center) - probe.half_extents;
    let outside = max(max(d.x, d.y), d.z);
    return saturate(-outside / max(probe.blend_distance, 1e-4));
}

// Box-parallax-corrected sample direction: intersect the reflection ray with the probe AABB and
// re-vector from the capture center to that hit (falls back to r right next to the wall).
Vec3 reflection_probe_parallax_dir(ReflectionProbe probe, Vec3 pos_ws, Vec3 r) {
    let t1 = (probe.center - probe.half_extents - pos_ws) / r;
    let t2 = (probe.center + probe.half_extents - pos_ws) / r;
    let tfar = min(min(max(t1.x, t2.x), max(t1.y, t2.y)), max(t1.z, t2.z));
    return tfar > 1e-3 ? normalize(pos_ws + r * tfar - probe.center) : r;
}

// Reflected radiance at pos_ws for reflection dir r at roughness p_roughness: box-parallax +
// inward-blended reflection probes where they cover the point, falling back to the environment
// map where coverage is incomplete. Does NOT apply the specular BRDF (DFG) weight — the caller
// multiplies that in. Reusable across the forward pass, debug views, capture, etc.
Vec3 sample_reflection_probes(GlobalData* gd, Vec3 pos_ws, Vec3 r, f32 p_roughness) {
    Vec3 probe_sum = Vec3(0.0);
    float probe_wsum = 0.0;

    // Perf: the influence weight is a cheap reject computed BEFORE any cube fetch, so cost scales
    // with probe *overlap* at this point, not the total probe count. Loop bound is uniform.
    let probe_count = gd.num_reflection_probes;
    for (uint pi = 0; pi < probe_count; pi++) {
        let probe = gd.reflection_probes[pi];

        let w = reflection_probe_weight(probe, pos_ws);
        if (w <= 0.0) {
            continue; // point not inside this probe's volume -> skip the expensive sample
        }

        // Budget fill: a probe claims only the coverage not already taken by higher-priority
        // probes (the array is sorted priority-desc on the CPU). So priority is a real precedence
        // in overlap regions, not just a blend-order tiebreak.
        let contrib = min(w, 1.0 - probe_wsum);
        let pdir = reflection_probe_parallax_dir(probe, pos_ws, r);
        let lod = p_roughness * float(probe.mip_count - 1);
        probe_sum += probe.cube.sample_level(probe.sampler, pdir, lod).rgb * probe.intensity * contrib;
        probe_wsum += contrib;

        if (probe_wsum >= 1.0) {
            break; // fully covered -> no need to keep sampling more probes
        }
    }

    if (probe_wsum >= 1.0) {
        return probe_sum / probe_wsum;
    }

    // Distant env map fills the remainder (only fetched where coverage is incomplete).
    PBR_Params ibl;
    ibl.env_map = gd.environment.env_map;
    ibl.dfg = gd.environment.dfg;
    ibl.env_sampler = gd.environment.env_sampler;
    ibl.default_sampler = gd.default_sampler;
    Vec3 env_refl = gd.sky_color * evaluate_specular_ibl(ibl, r, p_roughness);
    return probe_wsum > 0.0 ? lerp(env_refl, probe_sum / probe_wsum, probe_wsum) : env_refl;
}
