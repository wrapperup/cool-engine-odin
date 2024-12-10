// Generated boilerplate code for _Tex.get_dimensions method.

implementing bindless;

// Shape 1D, Read-Only, Non-array, Non-MS
__generic<T, let sampleCount:int, let format:int>
public extension _Tex<T, __Shape1D, 0, 0, sampleCount, 0, format> {
    public void get_dimensions(out float width) {
        TextureType texture = Textures[this.index];
        texture.GetDimensions(width);
    }
    public void get_dimensions(uint mipLevel, out float width, out float numberOfLevels) {
        TextureType texture = Textures[this.index];
        texture.GetDimensions(mipLevel, width, numberOfLevels);
    }
    public void get_dimensions(out int width) {
        TextureType texture = Textures[this.index];
        texture.GetDimensions(width);
    }
    public void get_dimensions(uint mipLevel, out int width, out int numberOfLevels) {
        TextureType texture = Textures[this.index];
        texture.GetDimensions(mipLevel, width, numberOfLevels);
    }
    public void get_dimensions(out uint width) {
        TextureType texture = Textures[this.index];
        texture.GetDimensions(width);
    }
    public void get_dimensions(uint mipLevel, out uint width, out uint numberOfLevels) {
        TextureType texture = Textures[this.index];
        texture.GetDimensions(mipLevel, width, numberOfLevels);
    }
}

// Shape 1D, Read/Write, Non-array, Non-MS
__generic<T, let sampleCount:int, let format:int>
public extension _Tex<T, __Shape1D, 0, 0, sampleCount, 1, format> {
    public void get_dimensions(out float width) {
        TextureType texture = RWTextures[this.index];
        texture.GetDimensions(width);
    }
    public void get_dimensions(uint mipLevel, out float width, out float numberOfLevels) {
        TextureType texture = RWTextures[this.index];
        texture.GetDimensions(mipLevel, width, numberOfLevels);
    }
    public void get_dimensions(out int width) {
        TextureType texture = RWTextures[this.index];
        texture.GetDimensions(width);
    }
    public void get_dimensions(uint mipLevel, out int width, out int numberOfLevels) {
        TextureType texture = RWTextures[this.index];
        texture.GetDimensions(mipLevel, width, numberOfLevels);
    }
    public void get_dimensions(out uint width) {
        TextureType texture = RWTextures[this.index];
        texture.GetDimensions(width);
    }
    public void get_dimensions(uint mipLevel, out uint width, out uint numberOfLevels) {
        TextureType texture = RWTextures[this.index];
        texture.GetDimensions(mipLevel, width, numberOfLevels);
    }
}

// Shape 1D, Read-Only, Array, Non-MS
__generic<T, let sampleCount:int, let format:int>
public extension _Tex<T, __Shape1D, 1, 0, sampleCount, 0, format> {
    public void get_dimensions(out float width, out float elements) {
        TextureType texture = Textures[this.index];
        texture.GetDimensions(width, elements);
    }
    public void get_dimensions(uint mipLevel, out float width, out float elements, out float numberOfLevels) {
        TextureType texture = Textures[this.index];
        texture.GetDimensions(mipLevel, width, elements, numberOfLevels);
    }
    public void get_dimensions(out int width, out int elements) {
        TextureType texture = Textures[this.index];
        texture.GetDimensions(width, elements);
    }
    public void get_dimensions(uint mipLevel, out int width, out int elements, out int numberOfLevels) {
        TextureType texture = Textures[this.index];
        texture.GetDimensions(mipLevel, width, elements, numberOfLevels);
    }
    public void get_dimensions(out uint width, out uint elements) {
        TextureType texture = Textures[this.index];
        texture.GetDimensions(width, elements);
    }
    public void get_dimensions(uint mipLevel, out uint width, out uint elements, out uint numberOfLevels) {
        TextureType texture = Textures[this.index];
        texture.GetDimensions(mipLevel, width, elements, numberOfLevels);
    }
}

// Shape 1D, Read/Write, Array, Non-MS
__generic<T, let sampleCount:int, let format:int>
public extension _Tex<T, __Shape1D, 1, 0, sampleCount, 1, format> {
    public void get_dimensions(out float width, out float elements) {
        TextureType texture = RWTextures[this.index];
        texture.GetDimensions(width, elements);
    }
    public void get_dimensions(uint mipLevel, out float width, out float elements, out float numberOfLevels) {
        TextureType texture = RWTextures[this.index];
        texture.GetDimensions(mipLevel, width, elements, numberOfLevels);
    }
    public void get_dimensions(out int width, out int elements) {
        TextureType texture = RWTextures[this.index];
        texture.GetDimensions(width, elements);
    }
    public void get_dimensions(uint mipLevel, out int width, out int elements, out int numberOfLevels) {
        TextureType texture = RWTextures[this.index];
        texture.GetDimensions(mipLevel, width, elements, numberOfLevels);
    }
    public void get_dimensions(out uint width, out uint elements) {
        TextureType texture = RWTextures[this.index];
        texture.GetDimensions(width, elements);
    }
    public void get_dimensions(uint mipLevel, out uint width, out uint elements, out uint numberOfLevels) {
        TextureType texture = RWTextures[this.index];
        texture.GetDimensions(mipLevel, width, elements, numberOfLevels);
    }
}

// Shape 2D, Read-Only, Non-array, Non-MS
__generic<T, let sampleCount:int, let format:int>
public extension _Tex<T, __Shape2D, 0, 0, sampleCount, 0, format> {
    public void get_dimensions(out float width, out float height) {
        TextureType texture = Textures[this.index];
        texture.GetDimensions(width, height);
    }
    public void get_dimensions(uint mipLevel, out float width, out float height, out float numberOfLevels) {
        TextureType texture = Textures[this.index];
        texture.GetDimensions(mipLevel, width, height, numberOfLevels);
    }
    public void get_dimensions(out int width, out int height) {
        TextureType texture = Textures[this.index];
        texture.GetDimensions(width, height);
    }
    public void get_dimensions(uint mipLevel, out int width, out int height, out int numberOfLevels) {
        TextureType texture = Textures[this.index];
        texture.GetDimensions(mipLevel, width, height, numberOfLevels);
    }
    public void get_dimensions(out uint width, out uint height) {
        TextureType texture = Textures[this.index];
        texture.GetDimensions(width, height);
    }
    public void get_dimensions(uint mipLevel, out uint width, out uint height, out uint numberOfLevels) {
        TextureType texture = Textures[this.index];
        texture.GetDimensions(mipLevel, width, height, numberOfLevels);
    }
}

// Shape 2D, Read/Write, Non-array, Non-MS
__generic<T, let sampleCount:int, let format:int>
public extension _Tex<T, __Shape2D, 0, 0, sampleCount, 1, format> {
    public void get_dimensions(out float width, out float height) {
        TextureType texture = RWTextures[this.index];
        texture.GetDimensions(width, height);
    }
    public void get_dimensions(uint mipLevel, out float width, out float height, out float numberOfLevels) {
        TextureType texture = RWTextures[this.index];
        texture.GetDimensions(mipLevel, width, height, numberOfLevels);
    }
    public void get_dimensions(out int width, out int height) {
        TextureType texture = RWTextures[this.index];
        texture.GetDimensions(width, height);
    }
    public void get_dimensions(uint mipLevel, out int width, out int height, out int numberOfLevels) {
        TextureType texture = RWTextures[this.index];
        texture.GetDimensions(mipLevel, width, height, numberOfLevels);
    }
    public void get_dimensions(out uint width, out uint height) {
        TextureType texture = RWTextures[this.index];
        texture.GetDimensions(width, height);
    }
    public void get_dimensions(uint mipLevel, out uint width, out uint height, out uint numberOfLevels) {
        TextureType texture = RWTextures[this.index];
        texture.GetDimensions(mipLevel, width, height, numberOfLevels);
    }
}

// Shape 2D, Read-Only, Non-array, MS
__generic<T, let sampleCount:int, let format:int>
public extension _Tex<T, __Shape2D, 0, 1, sampleCount, 0, format> {
    public void get_dimensions(out float width, out float height, out float sampleCount) {
        TextureType texture = Textures[this.index];
        texture.GetDimensions(width, height, sampleCount);
    }
    public void get_dimensions(out int width, out int height, out int sampleCount) {
        TextureType texture = Textures[this.index];
        texture.GetDimensions(width, height, sampleCount);
    }
    public void get_dimensions(out uint width, out uint height, out uint sampleCount) {
        TextureType texture = Textures[this.index];
        texture.GetDimensions(width, height, sampleCount);
    }
}

// Shape 2D, Read/Write, Non-array, MS
__generic<T, let sampleCount:int, let format:int>
public extension _Tex<T, __Shape2D, 0, 1, sampleCount, 1, format> {
    public void get_dimensions(out float width, out float height, out float sampleCount) {
        TextureType texture = RWTextures[this.index];
        texture.GetDimensions(width, height, sampleCount);
    }
    public void get_dimensions(out int width, out int height, out int sampleCount) {
        TextureType texture = RWTextures[this.index];
        texture.GetDimensions(width, height, sampleCount);
    }
    public void get_dimensions(out uint width, out uint height, out uint sampleCount) {
        TextureType texture = RWTextures[this.index];
        texture.GetDimensions(width, height, sampleCount);
    }
}

// Shape 2D, Read-Only, Array, Non-MS
__generic<T, let sampleCount:int, let format:int>
public extension _Tex<T, __Shape2D, 1, 0, sampleCount, 0, format> {
    public void get_dimensions(out float width, out float height, out float elements) {
        TextureType texture = Textures[this.index];
        texture.GetDimensions(width, height, elements);
    }
    public void get_dimensions(uint mipLevel, out float width, out float height, out float elements, out float numberOfLevels) {
        TextureType texture = Textures[this.index];
        texture.GetDimensions(mipLevel, width, height, elements, numberOfLevels);
    }
    public void get_dimensions(out int width, out int height, out int elements) {
        TextureType texture = Textures[this.index];
        texture.GetDimensions(width, height, elements);
    }
    public void get_dimensions(uint mipLevel, out int width, out int height, out int elements, out int numberOfLevels) {
        TextureType texture = Textures[this.index];
        texture.GetDimensions(mipLevel, width, height, elements, numberOfLevels);
    }
    public void get_dimensions(out uint width, out uint height, out uint elements) {
        TextureType texture = Textures[this.index];
        texture.GetDimensions(width, height, elements);
    }
    public void get_dimensions(uint mipLevel, out uint width, out uint height, out uint elements, out uint numberOfLevels) {
        TextureType texture = Textures[this.index];
        texture.GetDimensions(mipLevel, width, height, elements, numberOfLevels);
    }
}

// Shape 2D, Read/Write, Array, Non-MS
__generic<T, let sampleCount:int, let format:int>
public extension _Tex<T, __Shape2D, 1, 0, sampleCount, 1, format> {
    public void get_dimensions(out float width, out float height, out float elements) {
        TextureType texture = RWTextures[this.index];
        texture.GetDimensions(width, height, elements);
    }
    public void get_dimensions(uint mipLevel, out float width, out float height, out float elements, out float numberOfLevels) {
        TextureType texture = RWTextures[this.index];
        texture.GetDimensions(mipLevel, width, height, elements, numberOfLevels);
    }
    public void get_dimensions(out int width, out int height, out int elements) {
        TextureType texture = RWTextures[this.index];
        texture.GetDimensions(width, height, elements);
    }
    public void get_dimensions(uint mipLevel, out int width, out int height, out int elements, out int numberOfLevels) {
        TextureType texture = RWTextures[this.index];
        texture.GetDimensions(mipLevel, width, height, elements, numberOfLevels);
    }
    public void get_dimensions(out uint width, out uint height, out uint elements) {
        TextureType texture = RWTextures[this.index];
        texture.GetDimensions(width, height, elements);
    }
    public void get_dimensions(uint mipLevel, out uint width, out uint height, out uint elements, out uint numberOfLevels) {
        TextureType texture = RWTextures[this.index];
        texture.GetDimensions(mipLevel, width, height, elements, numberOfLevels);
    }
}

// Shape 2D, Read-Only, Array, MS
__generic<T, let sampleCount:int, let format:int>
public extension _Tex<T, __Shape2D, 1, 1, sampleCount, 0, format> {
    public void get_dimensions(out float width, out float height, out float elements, out float sampleCount) {
        TextureType texture = Textures[this.index];
        texture.GetDimensions(width, height, elements, sampleCount);
    }
    public void get_dimensions(out int width, out int height, out int elements, out int sampleCount) {
        TextureType texture = Textures[this.index];
        texture.GetDimensions(width, height, elements, sampleCount);
    }
    public void get_dimensions(out uint width, out uint height, out uint elements, out uint sampleCount) {
        TextureType texture = Textures[this.index];
        texture.GetDimensions(width, height, elements, sampleCount);
    }
}

// Shape 2D, Read/Write, Array, MS
__generic<T, let sampleCount:int, let format:int>
public extension _Tex<T, __Shape2D, 1, 1, sampleCount, 1, format> {
    public void get_dimensions(out float width, out float height, out float elements, out float sampleCount) {
        TextureType texture = RWTextures[this.index];
        texture.GetDimensions(width, height, elements, sampleCount);
    }
    public void get_dimensions(out int width, out int height, out int elements, out int sampleCount) {
        TextureType texture = RWTextures[this.index];
        texture.GetDimensions(width, height, elements, sampleCount);
    }
    public void get_dimensions(out uint width, out uint height, out uint elements, out uint sampleCount) {
        TextureType texture = RWTextures[this.index];
        texture.GetDimensions(width, height, elements, sampleCount);
    }
}

// Shape 3D, Read-Only, Non-array, Non-MS
__generic<T, let sampleCount:int, let format:int>
public extension _Tex<T, __Shape3D, 0, 0, sampleCount, 0, format> {
    public void get_dimensions(out float width, out float height, out float depth) {
        TextureType texture = Textures[this.index];
        texture.GetDimensions(width, height, depth);
    }
    public void get_dimensions(uint mipLevel, out float width, out float height, out float depth, out float numberOfLevels) {
        TextureType texture = Textures[this.index];
        texture.GetDimensions(mipLevel, width, height, depth, numberOfLevels);
    }
    public void get_dimensions(out int width, out int height, out int depth) {
        TextureType texture = Textures[this.index];
        texture.GetDimensions(width, height, depth);
    }
    public void get_dimensions(uint mipLevel, out int width, out int height, out int depth, out int numberOfLevels) {
        TextureType texture = Textures[this.index];
        texture.GetDimensions(mipLevel, width, height, depth, numberOfLevels);
    }
    public void get_dimensions(out uint width, out uint height, out uint depth) {
        TextureType texture = Textures[this.index];
        texture.GetDimensions(width, height, depth);
    }
    public void get_dimensions(uint mipLevel, out uint width, out uint height, out uint depth, out uint numberOfLevels) {
        TextureType texture = Textures[this.index];
        texture.GetDimensions(mipLevel, width, height, depth, numberOfLevels);
    }
}

// Shape 3D, Read/Write, Non-array, Non-MS
__generic<T, let sampleCount:int, let format:int>
public extension _Tex<T, __Shape3D, 0, 0, sampleCount, 1, format> {
    public void get_dimensions(out float width, out float height, out float depth) {
        TextureType texture = RWTextures[this.index];
        texture.GetDimensions(width, height, depth);
    }
    public void get_dimensions(uint mipLevel, out float width, out float height, out float depth, out float numberOfLevels) {
        TextureType texture = RWTextures[this.index];
        texture.GetDimensions(mipLevel, width, height, depth, numberOfLevels);
    }
    public void get_dimensions(out int width, out int height, out int depth) {
        TextureType texture = RWTextures[this.index];
        texture.GetDimensions(width, height, depth);
    }
    public void get_dimensions(uint mipLevel, out int width, out int height, out int depth, out int numberOfLevels) {
        TextureType texture = RWTextures[this.index];
        texture.GetDimensions(mipLevel, width, height, depth, numberOfLevels);
    }
    public void get_dimensions(out uint width, out uint height, out uint depth) {
        TextureType texture = RWTextures[this.index];
        texture.GetDimensions(width, height, depth);
    }
    public void get_dimensions(uint mipLevel, out uint width, out uint height, out uint depth, out uint numberOfLevels) {
        TextureType texture = RWTextures[this.index];
        texture.GetDimensions(mipLevel, width, height, depth, numberOfLevels);
    }
}

// Shape Cube, Read-Only, Non-array, Non-MS
__generic<T, let sampleCount:int, let format:int>
public extension _Tex<T, __ShapeCube, 0, 0, sampleCount, 0, format> {
    public void get_dimensions(out float width, out float height) {
        TextureType texture = Textures[this.index];
        texture.GetDimensions(width, height);
    }
    public void get_dimensions(uint mipLevel, out float width, out float height, out float numberOfLevels) {
        TextureType texture = Textures[this.index];
        texture.GetDimensions(mipLevel, width, height, numberOfLevels);
    }
    public void get_dimensions(out int width, out int height) {
        TextureType texture = Textures[this.index];
        texture.GetDimensions(width, height);
    }
    public void get_dimensions(uint mipLevel, out int width, out int height, out int numberOfLevels) {
        TextureType texture = Textures[this.index];
        texture.GetDimensions(mipLevel, width, height, numberOfLevels);
    }
    public void get_dimensions(out uint width, out uint height) {
        TextureType texture = Textures[this.index];
        texture.GetDimensions(width, height);
    }
    public void get_dimensions(uint mipLevel, out uint width, out uint height, out uint numberOfLevels) {
        TextureType texture = Textures[this.index];
        texture.GetDimensions(mipLevel, width, height, numberOfLevels);
    }
}

// Shape Cube, Read/Write, Non-array, Non-MS
__generic<T, let sampleCount:int, let format:int>
public extension _Tex<T, __ShapeCube, 0, 0, sampleCount, 1, format> {
    public void get_dimensions(out float width, out float height) {
        TextureType texture = RWTextures[this.index];
        texture.GetDimensions(width, height);
    }
    public void get_dimensions(uint mipLevel, out float width, out float height, out float numberOfLevels) {
        TextureType texture = RWTextures[this.index];
        texture.GetDimensions(mipLevel, width, height, numberOfLevels);
    }
    public void get_dimensions(out int width, out int height) {
        TextureType texture = RWTextures[this.index];
        texture.GetDimensions(width, height);
    }
    public void get_dimensions(uint mipLevel, out int width, out int height, out int numberOfLevels) {
        TextureType texture = RWTextures[this.index];
        texture.GetDimensions(mipLevel, width, height, numberOfLevels);
    }
    public void get_dimensions(out uint width, out uint height) {
        TextureType texture = RWTextures[this.index];
        texture.GetDimensions(width, height);
    }
    public void get_dimensions(uint mipLevel, out uint width, out uint height, out uint numberOfLevels) {
        TextureType texture = RWTextures[this.index];
        texture.GetDimensions(mipLevel, width, height, numberOfLevels);
    }
}

// Shape Cube, Read-Only, Array, Non-MS
__generic<T, let sampleCount:int, let format:int>
public extension _Tex<T, __ShapeCube, 1, 0, sampleCount, 0, format> {
    public void get_dimensions(out float width, out float height, out float elements) {
        TextureType texture = Textures[this.index];
        texture.GetDimensions(width, height, elements);
    }
    public void get_dimensions(uint mipLevel, out float width, out float height, out float elements, out float numberOfLevels) {
        TextureType texture = Textures[this.index];
        texture.GetDimensions(mipLevel, width, height, elements, numberOfLevels);
    }
    public void get_dimensions(out int width, out int height, out int elements) {
        TextureType texture = Textures[this.index];
        texture.GetDimensions(width, height, elements);
    }
    public void get_dimensions(uint mipLevel, out int width, out int height, out int elements, out int numberOfLevels) {
        TextureType texture = Textures[this.index];
        texture.GetDimensions(mipLevel, width, height, elements, numberOfLevels);
    }
    public void get_dimensions(out uint width, out uint height, out uint elements) {
        TextureType texture = Textures[this.index];
        texture.GetDimensions(width, height, elements);
    }
    public void get_dimensions(uint mipLevel, out uint width, out uint height, out uint elements, out uint numberOfLevels) {
        TextureType texture = Textures[this.index];
        texture.GetDimensions(mipLevel, width, height, elements, numberOfLevels);
    }
}

// Shape Cube, Read/Write, Array, Non-MS
__generic<T, let sampleCount:int, let format:int>
public extension _Tex<T, __ShapeCube, 1, 0, sampleCount, 1, format> {
    public void get_dimensions(out float width, out float height, out float elements) {
        TextureType texture = RWTextures[this.index];
        texture.GetDimensions(width, height, elements);
    }
    public void get_dimensions(uint mipLevel, out float width, out float height, out float elements, out float numberOfLevels) {
        TextureType texture = RWTextures[this.index];
        texture.GetDimensions(mipLevel, width, height, elements, numberOfLevels);
    }
    public void get_dimensions(out int width, out int height, out int elements) {
        TextureType texture = RWTextures[this.index];
        texture.GetDimensions(width, height, elements);
    }
    public void get_dimensions(uint mipLevel, out int width, out int height, out int elements, out int numberOfLevels) {
        TextureType texture = RWTextures[this.index];
        texture.GetDimensions(mipLevel, width, height, elements, numberOfLevels);
    }
    public void get_dimensions(out uint width, out uint height, out uint elements) {
        TextureType texture = RWTextures[this.index];
        texture.GetDimensions(width, height, elements);
    }
    public void get_dimensions(uint mipLevel, out uint width, out uint height, out uint elements, out uint numberOfLevels) {
        TextureType texture = RWTextures[this.index];
        texture.GetDimensions(mipLevel, width, height, elements, numberOfLevels);
    }
}
