implementing bindless;

import "../types";

public [vk_binding(0, 0)] __DynamicResource Images[];
public [vk_binding(1, 0)] __DynamicResource<__DynamicResourceKind.Sampler> Samplers[];
public [vk_binding(2, 0)] __DynamicResource RWImages[];

public struct _Image<T:ITexelElement, Shape: __ITextureShape, let isArray:int, let isMS:int, let sampleCount:int, let access:int, let format:int> {
    public typealias ImageType = _Texture<T, Shape, isArray, isMS, sampleCount, access, 0, 0, format>;
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

// Take careful note of using the `Images` array VS the `RWTextures` array in the specialized extensions.
// Read-only extensions should use `Images` and Read/Write ones should use `RWTextures`.

// Read-only extensions
__generic<T:ITexelElement, Shape: __ITextureShape, let isArray:int, let isMS:int, let sampleCount:int, let format:int>
public extension _Image<T, Shape, isArray, isMS, sampleCount, 0, format> {
    public ImageType get() {
        return Images[this.index].as<ImageType>();
    }

    public T sample(Sampler sampler_id, vector<float, isArray+Shape.dimensions> location) {
        ImageType image = Images[this.index];
        SamplerState sampler = Samplers[sampler_id.index].as<SamplerState>();

        return image.Sample(sampler, location);
    }

    public T sample_level(Sampler sampler_id, vector<float, isArray+Shape.dimensions> location, float level) {
        ImageType image = Images[this.index];
        SamplerState sampler = Samplers[sampler_id.index].as<SamplerState>();

        return image.SampleLevel(sampler, location, level);
    }

    public f32 sample_cmp_level_zero(
        SamplerComparison sampler_id, 
        vector<float, isArray+Shape.dimensions> location, 
        float compare_value, 
    ) {
        ImageType image = Images[this.index];
        SamplerComparisonState sampler = Samplers[sampler_id.index].as<SamplerComparisonState>();

        return image.SampleCmpLevelZero(sampler, location, compare_value);
    }
}

// Read/Write extensions
__generic<T:ITexelElement, Shape: __ITextureShape, let isArray:int, let isMS:int, let sampleCount:int, let format:int>
public extension _Image<T, Shape, isArray, isMS, sampleCount, 1, format> {
    public ImageType get() {
        return RWImages[this.index].as<ImageType>();
    }
}

// Read-only No Multisample extensions
__generic<T:ITexelElement, Shape: __ITextureShape, let isArray:int, let sampleCount:int, let format:int>
public extension _Image<T, Shape, isArray, 0, sampleCount, 0, format> {
    public T load(vector<i32, isArray+Shape.dimensions+1> location) {
        ImageType image = Images[this.index];
        return image.Load(location);
    }

    public __subscript(vector<i32, isArray+Shape.dimensions+1> location) -> T {
        get { return load(location); }
    }
}

// Read/Write No Multisample extensions
__generic<T:ITexelElement, Shape: __ITextureShape, let isArray:int, let sampleCount:int, let format:int>
public extension _Image<T, Shape, isArray, 0, sampleCount, 1, format> {
    public T load(vector<i32, isArray+Shape.dimensions> location) {
        ImageType image = RWImages[this.index];
        return image.Load(location);
    }

    public void store(vector<u32, isArray+Shape.dimensions> location, T value) {
        ImageType image = RWImages[this.index];
        return image.Store(location, value);
    }

    public __subscript(vector<i32, isArray+Shape.dimensions> location) -> T {
        get { return load(location); }
    }
}

// Generated because holy shit theres a lot of them.
__include gen_get_dimensions;

public __generic<T:ITexelElement = Vec4> typealias Image1D   = _Image<T, __Shape1D, 0, 0, 0, 0, 0>;
public __generic<T:ITexelElement = Vec4> typealias Image2D   = _Image<T, __Shape2D, 0, 0, 0, 0, 0>;
public __generic<T:ITexelElement = Vec4> typealias Image3D   = _Image<T, __Shape3D, 0, 0, 0, 0, 0>;
public __generic<T:ITexelElement = Vec4> typealias ImageCube = _Image<T, __ShapeCube, 0, 0, 0, 0, 0>;

public __generic<T:ITexelElement = Vec4> typealias Image1DArray   = _Image<T, __Shape1D, 1, 0, 0, 0, 0>;
public __generic<T:ITexelElement = Vec4> typealias Image2DArray   = _Image<T, __Shape2D, 1, 0, 0, 0, 0>;
public __generic<T:ITexelElement = Vec4> typealias Image3DArray   = _Image<T, __Shape3D, 1, 0, 0, 0, 0>;
public __generic<T:ITexelElement = Vec4> typealias ImageCubeArray = _Image<T, __ShapeCube, 1, 0, 0, 0, 0>;

public __generic<T:ITexelElement = Vec4> typealias RWImage1D = _Image<T, __Shape1D, 0, 0, 0, 1, 0>;
public __generic<T:ITexelElement = Vec4> typealias RWImage2D = _Image<T, __Shape2D, 0, 0, 0, 1, 0>;
public __generic<T:ITexelElement = Vec4> typealias RWImage3D = _Image<T, __Shape3D, 0, 0, 0, 1, 0>;
