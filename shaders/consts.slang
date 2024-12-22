import bindless;

public static const Tex2DArray<float> SHADOW_ID = Tex2DArray<float>(0);
public static const Tex3D<float3> TONY_MC_MAPFACE_ID = Tex3D<float3>(1);
public static const Tex2D DFG_ID = Tex2D<float4>(2);
public static const TexCube ENVIRONMENT_MAP_ID = TexCube<float4>(3);

public static const Sampler DEFAULT_SAMPLER_ID = Sampler(0);
public static const SamplerComparison SHADOW_SAMPLER_ID = SamplerComparison(1);
public static const Sampler ENVIRONMENT_SAMPLER_ID = Sampler(2);

public static const RWTex2D RESOLVED_IMAGE_ID = RWTex2D<float4>(0);
