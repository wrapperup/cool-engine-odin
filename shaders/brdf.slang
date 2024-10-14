#define PI 3.14159265359

float D_ggx(float NoH, float a) {
    float a2 = a * a;
    float f = (NoH * a2 - NoH) * NoH + 1.0;
    return a2 / (PI * f * f);
}

float3 F_schlick(float VoH, float3 f0) {
    return f0 + (float3(1.0) - f0) * pow(1.0 - VoH, 5.0);
}

float V_smith_ggx_correlated(float NoV, float NoL, float a) {
    float a2 = a * a;
    float GGXL = NoV * sqrt((-NoL * a2 + NoL) * NoL + a2);
    float GGXV = NoL * sqrt((-NoV * a2 + NoV) * NoV + a2);
    return 0.5 / (GGXV + GGXL);
}

float Fd_lambert() {
    return 1.0 / PI;
}

// https://google.github.io/filament/Filament.md.html#toc9.4
float2 hammersley(uint i, float numSamples) {
	uint bits = i;
	bits = (bits << 16) | (bits >> 16);
	bits = ((bits & 0x55555555) << 1) | ((bits & 0xAAAAAAAA) >> 1);
	bits = ((bits & 0x33333333) << 2) | ((bits & 0xCCCCCCCC) >> 2);
	bits = ((bits & 0x0F0F0F0F) << 4) | ((bits & 0xF0F0F0F0) >> 4);
	bits = ((bits & 0x00FF00FF) << 8) | ((bits & 0xFF00FF00) >> 8);
	return float2(i / numSamples, bits / pow(2.f,32.f));
}

float3 D_importance_sample_ggx(float2 u, float a) {
	float phi = 2.0 * float(PI) * u.x;
	// NOTE: (aa-1) == (a-1)(a+1) produces better fp accuracy
	float cosTheta2 = (1 - u.y) / (1 + (a + 1) * ((a - 1) * u.y));
	float cosTheta = sqrt(cosTheta2);
	float sinTheta = sqrt(1 - cosTheta2);
	return float3(sinTheta * cos(phi), sinTheta * sin(phi), cosTheta);
}
