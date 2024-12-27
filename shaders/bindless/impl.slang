implementing bindless;

import "../types";

public [vk_binding(0, 0)] __DynamicResource Textures[];
public [vk_binding(1, 0)] __DynamicResource<__DynamicResourceKind.Sampler> Samplers[];
public [vk_binding(2, 0)] __DynamicResource RWTextures[];

public struct _Tex<T, Shape: __ITextureShape, let isArray:int, let isMS:int, let sampleCount:int, let access:int, let format:int> {
    public typealias TextureType = _Texture<T, Shape, isArray, isMS, sampleCount, access, 0, 0, format>;
    public u32 index;
}

public struct Sampler {
    public u32 index;

    public SamplerState get() {
        return Samplers[this.index].as<SamplerState>();
    }
}

public struct SamplerComparison {
    public u32 index;

    public SamplerComparisonState get() {
        return Samplers[this.index].as<SamplerComparisonState>();
    }
}

// Take careful note of using the `Textures` array VS the `RWTextures` array in the specialized extensions.
// Read-only extensions should use `Textures` and Read/Write ones should use `RWTextures`.

// Read-only extensions
__generic<T, Shape: __ITextureShape, let isArray:int, let isMS:int, let sampleCount:int, let format:int>
public extension _Tex<T, Shape, isArray, isMS, sampleCount, 0, format> {
    public TextureType get() {
        return Textures[this.index].as<TextureType>();
    }

    public T sample(Sampler sampler_id, vector<float, isArray+Shape.dimensions> location) {
        TextureType texture = Textures[this.index];
        SamplerState sampler = Samplers[sampler_id.index].as<SamplerState>();

        return texture.Sample(sampler, location);
    }

    public T sample_level(Sampler sampler_id, vector<float, isArray+Shape.dimensions> location, float level) {
        TextureType texture = Textures[this.index];
        SamplerState sampler = Samplers[sampler_id.index].as<SamplerState>();

        return texture.SampleLevel(sampler, location, level);
    }

    public f32 sample_cmp_level_zero(
        SamplerComparison sampler_id, 
        vector<float, isArray+Shape.dimensions> location, 
        float compare_value, 
    ) {
        TextureType texture = Textures[this.index];
        SamplerComparisonState sampler = Samplers[sampler_id.index].as<SamplerComparisonState>();

        return texture.SampleCmpLevelZero(sampler, location, compare_value);
    }
}

// Read/Write extensions
__generic<T, Shape: __ITextureShape, let isArray:int, let isMS:int, let sampleCount:int, let format:int>
public extension _Tex<T, Shape, isArray, isMS, sampleCount, 1, format> {
    public TextureType get() {
        return RWTextures[this.index].as<TextureType>();
    }
}

// Read-only No Multisample extensions
__generic<T, Shape: __ITextureShape, let isArray:int, let sampleCount:int, let format:int>
public extension _Tex<T, Shape, isArray, 0, sampleCount, 0, format> {
    public T load(vector<i32, isArray+Shape.dimensions+1> location) {
        TextureType texture = Textures[this.index];
        return texture.Load(location);
    }

    public __subscript(vector<i32, isArray+Shape.dimensions+1> location) -> T {
        get { return load(location); }
    }
}

// Read/Write No Multisample extensions
__generic<T, Shape: __ITextureShape, let isArray:int, let sampleCount:int, let format:int>
public extension _Tex<T, Shape, isArray, 0, sampleCount, 1, format> {
    public T load(vector<i32, isArray+Shape.dimensions> location) {
        TextureType texture = RWTextures[this.index];
        return texture.Load(location);
    }

    public void store(vector<u32, isArray+Shape.dimensions> location, T value) {
        TextureType texture = RWTextures[this.index];
        return texture.Store(location, value);
    }

    public __subscript(vector<i32, isArray+Shape.dimensions> location) -> T {
        get { return load(location); }
    }
}

// Generated because holy shit theres a lot of them.
__include gen_get_dimensions;

public __generic<T = Vec4> typealias Tex1D   = _Tex<T, __Shape1D, 0, 0, 0, 0, 0>;
public __generic<T = Vec4> typealias Tex2D   = _Tex<T, __Shape2D, 0, 0, 0, 0, 0>;
public __generic<T = Vec4> typealias Tex3D   = _Tex<T, __Shape3D, 0, 0, 0, 0, 0>;
public __generic<T = Vec4> typealias TexCube = _Tex<T, __ShapeCube, 0, 0, 0, 0, 0>;

public __generic<T = Vec4> typealias Tex1DArray   = _Tex<T, __Shape1D, 1, 0, 0, 0, 0>;
public __generic<T = Vec4> typealias Tex2DArray   = _Tex<T, __Shape2D, 1, 0, 0, 0, 0>;
public __generic<T = Vec4> typealias Tex3DArray   = _Tex<T, __Shape3D, 1, 0, 0, 0, 0>;
public __generic<T = Vec4> typealias TexCubeArray = _Tex<T, __ShapeCube, 1, 0, 0, 0, 0>;

public __generic<T = Vec4> typealias RWTex1D = _Tex<T, __Shape1D, 0, 0, 0, 1, 0>;
public __generic<T = Vec4> typealias RWTex2D = _Tex<T, __Shape2D, 0, 0, 0, 1, 0>;
public __generic<T = Vec4> typealias RWTex3D = _Tex<T, __Shape3D, 0, 0, 0, 1, 0>;
