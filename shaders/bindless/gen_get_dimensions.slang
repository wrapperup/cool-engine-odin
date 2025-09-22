// Generated boilerplate code for _Image.get_dimensions method.

implementing bindless;

// Shape 1D, Read-Only, Non-array, Non-MS
__generic<T:ITexelElement, let sampleCount:int, let format:int>
public extension _Image<T, __Shape1D, 0, 0, sampleCount, 0, format> {
    public void get_dimensions(out float width) {
        ImageType texture = Images[this.index];
        texture.GetDimensions(width);
    }
    public void get_dimensions(uint mipLevel, out float width, out float numberOfLevels) {
        ImageType texture = Images[this.index];
        texture.GetDimensions(mipLevel, width, numberOfLevels);
    }
    public void get_dimensions(out int width) {
        ImageType texture = Images[this.index];
        texture.GetDimensions(width);
    }
    public void get_dimensions(uint mipLevel, out int width, out int numberOfLevels) {
        ImageType texture = Images[this.index];
        texture.GetDimensions(mipLevel, width, numberOfLevels);
    }
    public void get_dimensions(out uint width) {
        ImageType texture = Images[this.index];
        texture.GetDimensions(width);
    }
    public void get_dimensions(uint mipLevel, out uint width, out uint numberOfLevels) {
        ImageType texture = Images[this.index];
        texture.GetDimensions(mipLevel, width, numberOfLevels);
    }
}

// Shape 1D, Read/Write, Non-array, Non-MS
__generic<T:ITexelElement, let sampleCount:int, let format:int>
public extension _Image<T, __Shape1D, 0, 0, sampleCount, 1, format> {
    public void get_dimensions(out float width) {
        ImageType texture = RWImages[this.index];
        texture.GetDimensions(width);
    }
    public void get_dimensions(uint mipLevel, out float width, out float numberOfLevels) {
        ImageType texture = RWImages[this.index];
        texture.GetDimensions(mipLevel, width, numberOfLevels);
    }
    public void get_dimensions(out int width) {
        ImageType texture = RWImages[this.index];
        texture.GetDimensions(width);
    }
    public void get_dimensions(uint mipLevel, out int width, out int numberOfLevels) {
        ImageType texture = RWImages[this.index];
        texture.GetDimensions(mipLevel, width, numberOfLevels);
    }
    public void get_dimensions(out uint width) {
        ImageType texture = RWImages[this.index];
        texture.GetDimensions(width);
    }
    public void get_dimensions(uint mipLevel, out uint width, out uint numberOfLevels) {
        ImageType texture = RWImages[this.index];
        texture.GetDimensions(mipLevel, width, numberOfLevels);
    }
}

// Shape 1D, Read-Only, Array, Non-MS
__generic<T:ITexelElement, let sampleCount:int, let format:int>
public extension _Image<T, __Shape1D, 1, 0, sampleCount, 0, format> {
    public void get_dimensions(out float width, out float elements) {
        ImageType texture = Images[this.index];
        texture.GetDimensions(width, elements);
    }
    public void get_dimensions(uint mipLevel, out float width, out float elements, out float numberOfLevels) {
        ImageType texture = Images[this.index];
        texture.GetDimensions(mipLevel, width, elements, numberOfLevels);
    }
    public void get_dimensions(out int width, out int elements) {
        ImageType texture = Images[this.index];
        texture.GetDimensions(width, elements);
    }
    public void get_dimensions(uint mipLevel, out int width, out int elements, out int numberOfLevels) {
        ImageType texture = Images[this.index];
        texture.GetDimensions(mipLevel, width, elements, numberOfLevels);
    }
    public void get_dimensions(out uint width, out uint elements) {
        ImageType texture = Images[this.index];
        texture.GetDimensions(width, elements);
    }
    public void get_dimensions(uint mipLevel, out uint width, out uint elements, out uint numberOfLevels) {
        ImageType texture = Images[this.index];
        texture.GetDimensions(mipLevel, width, elements, numberOfLevels);
    }
}

// Shape 1D, Read/Write, Array, Non-MS
__generic<T:ITexelElement, let sampleCount:int, let format:int>
public extension _Image<T, __Shape1D, 1, 0, sampleCount, 1, format> {
    public void get_dimensions(out float width, out float elements) {
        ImageType texture = RWImages[this.index];
        texture.GetDimensions(width, elements);
    }
    public void get_dimensions(uint mipLevel, out float width, out float elements, out float numberOfLevels) {
        ImageType texture = RWImages[this.index];
        texture.GetDimensions(mipLevel, width, elements, numberOfLevels);
    }
    public void get_dimensions(out int width, out int elements) {
        ImageType texture = RWImages[this.index];
        texture.GetDimensions(width, elements);
    }
    public void get_dimensions(uint mipLevel, out int width, out int elements, out int numberOfLevels) {
        ImageType texture = RWImages[this.index];
        texture.GetDimensions(mipLevel, width, elements, numberOfLevels);
    }
    public void get_dimensions(out uint width, out uint elements) {
        ImageType texture = RWImages[this.index];
        texture.GetDimensions(width, elements);
    }
    public void get_dimensions(uint mipLevel, out uint width, out uint elements, out uint numberOfLevels) {
        ImageType texture = RWImages[this.index];
        texture.GetDimensions(mipLevel, width, elements, numberOfLevels);
    }
}

// Shape 2D, Read-Only, Non-array, Non-MS
__generic<T:ITexelElement, let sampleCount:int, let format:int>
public extension _Image<T, __Shape2D, 0, 0, sampleCount, 0, format> {
    public void get_dimensions(out float width, out float height) {
        ImageType texture = Images[this.index];
        texture.GetDimensions(width, height);
    }
    public void get_dimensions(uint mipLevel, out float width, out float height, out float numberOfLevels) {
        ImageType texture = Images[this.index];
        texture.GetDimensions(mipLevel, width, height, numberOfLevels);
    }
    public void get_dimensions(out int width, out int height) {
        ImageType texture = Images[this.index];
        texture.GetDimensions(width, height);
    }
    public void get_dimensions(uint mipLevel, out int width, out int height, out int numberOfLevels) {
        ImageType texture = Images[this.index];
        texture.GetDimensions(mipLevel, width, height, numberOfLevels);
    }
    public void get_dimensions(out uint width, out uint height) {
        ImageType texture = Images[this.index];
        texture.GetDimensions(width, height);
    }
    public void get_dimensions(uint mipLevel, out uint width, out uint height, out uint numberOfLevels) {
        ImageType texture = Images[this.index];
        texture.GetDimensions(mipLevel, width, height, numberOfLevels);
    }
}

// Shape 2D, Read/Write, Non-array, Non-MS
__generic<T:ITexelElement, let sampleCount:int, let format:int>
public extension _Image<T, __Shape2D, 0, 0, sampleCount, 1, format> {
    public void get_dimensions(out float width, out float height) {
        ImageType texture = RWImages[this.index];
        texture.GetDimensions(width, height);
    }
    public void get_dimensions(uint mipLevel, out float width, out float height, out float numberOfLevels) {
        ImageType texture = RWImages[this.index];
        texture.GetDimensions(mipLevel, width, height, numberOfLevels);
    }
    public void get_dimensions(out int width, out int height) {
        ImageType texture = RWImages[this.index];
        texture.GetDimensions(width, height);
    }
    public void get_dimensions(uint mipLevel, out int width, out int height, out int numberOfLevels) {
        ImageType texture = RWImages[this.index];
        texture.GetDimensions(mipLevel, width, height, numberOfLevels);
    }
    public void get_dimensions(out uint width, out uint height) {
        ImageType texture = RWImages[this.index];
        texture.GetDimensions(width, height);
    }
    public void get_dimensions(uint mipLevel, out uint width, out uint height, out uint numberOfLevels) {
        ImageType texture = RWImages[this.index];
        texture.GetDimensions(mipLevel, width, height, numberOfLevels);
    }
}

// Shape 2D, Read-Only, Non-array, MS
__generic<T:ITexelElement, let sampleCount:int, let format:int>
public extension _Image<T, __Shape2D, 0, 1, sampleCount, 0, format> {
    public void get_dimensions(out float width, out float height, out float sampleCount) {
        ImageType texture = Images[this.index];
        texture.GetDimensions(width, height, sampleCount);
    }
    public void get_dimensions(out int width, out int height, out int sampleCount) {
        ImageType texture = Images[this.index];
        texture.GetDimensions(width, height, sampleCount);
    }
    public void get_dimensions(out uint width, out uint height, out uint sampleCount) {
        ImageType texture = Images[this.index];
        texture.GetDimensions(width, height, sampleCount);
    }
}

// Shape 2D, Read/Write, Non-array, MS
__generic<T:ITexelElement, let sampleCount:int, let format:int>
public extension _Image<T, __Shape2D, 0, 1, sampleCount, 1, format> {
    public void get_dimensions(out float width, out float height, out float sampleCount) {
        ImageType texture = RWImages[this.index];
        texture.GetDimensions(width, height, sampleCount);
    }
    public void get_dimensions(out int width, out int height, out int sampleCount) {
        ImageType texture = RWImages[this.index];
        texture.GetDimensions(width, height, sampleCount);
    }
    public void get_dimensions(out uint width, out uint height, out uint sampleCount) {
        ImageType texture = RWImages[this.index];
        texture.GetDimensions(width, height, sampleCount);
    }
}

// Shape 2D, Read-Only, Array, Non-MS
__generic<T:ITexelElement, let sampleCount:int, let format:int>
public extension _Image<T, __Shape2D, 1, 0, sampleCount, 0, format> {
    public void get_dimensions(out float width, out float height, out float elements) {
        ImageType texture = Images[this.index];
        texture.GetDimensions(width, height, elements);
    }
    public void get_dimensions(uint mipLevel, out float width, out float height, out float elements, out float numberOfLevels) {
        ImageType texture = Images[this.index];
        texture.GetDimensions(mipLevel, width, height, elements, numberOfLevels);
    }
    public void get_dimensions(out int width, out int height, out int elements) {
        ImageType texture = Images[this.index];
        texture.GetDimensions(width, height, elements);
    }
    public void get_dimensions(uint mipLevel, out int width, out int height, out int elements, out int numberOfLevels) {
        ImageType texture = Images[this.index];
        texture.GetDimensions(mipLevel, width, height, elements, numberOfLevels);
    }
    public void get_dimensions(out uint width, out uint height, out uint elements) {
        ImageType texture = Images[this.index];
        texture.GetDimensions(width, height, elements);
    }
    public void get_dimensions(uint mipLevel, out uint width, out uint height, out uint elements, out uint numberOfLevels) {
        ImageType texture = Images[this.index];
        texture.GetDimensions(mipLevel, width, height, elements, numberOfLevels);
    }
}

// Shape 2D, Read/Write, Array, Non-MS
__generic<T:ITexelElement, let sampleCount:int, let format:int>
public extension _Image<T, __Shape2D, 1, 0, sampleCount, 1, format> {
    public void get_dimensions(out float width, out float height, out float elements) {
        ImageType texture = RWImages[this.index];
        texture.GetDimensions(width, height, elements);
    }
    public void get_dimensions(uint mipLevel, out float width, out float height, out float elements, out float numberOfLevels) {
        ImageType texture = RWImages[this.index];
        texture.GetDimensions(mipLevel, width, height, elements, numberOfLevels);
    }
    public void get_dimensions(out int width, out int height, out int elements) {
        ImageType texture = RWImages[this.index];
        texture.GetDimensions(width, height, elements);
    }
    public void get_dimensions(uint mipLevel, out int width, out int height, out int elements, out int numberOfLevels) {
        ImageType texture = RWImages[this.index];
        texture.GetDimensions(mipLevel, width, height, elements, numberOfLevels);
    }
    public void get_dimensions(out uint width, out uint height, out uint elements) {
        ImageType texture = RWImages[this.index];
        texture.GetDimensions(width, height, elements);
    }
    public void get_dimensions(uint mipLevel, out uint width, out uint height, out uint elements, out uint numberOfLevels) {
        ImageType texture = RWImages[this.index];
        texture.GetDimensions(mipLevel, width, height, elements, numberOfLevels);
    }
}

// Shape 2D, Read-Only, Array, MS
__generic<T:ITexelElement, let sampleCount:int, let format:int>
public extension _Image<T, __Shape2D, 1, 1, sampleCount, 0, format> {
    public void get_dimensions(out float width, out float height, out float elements, out float sampleCount) {
        ImageType texture = Images[this.index];
        texture.GetDimensions(width, height, elements, sampleCount);
    }
    public void get_dimensions(out int width, out int height, out int elements, out int sampleCount) {
        ImageType texture = Images[this.index];
        texture.GetDimensions(width, height, elements, sampleCount);
    }
    public void get_dimensions(out uint width, out uint height, out uint elements, out uint sampleCount) {
        ImageType texture = Images[this.index];
        texture.GetDimensions(width, height, elements, sampleCount);
    }
}

// Shape 2D, Read/Write, Array, MS
__generic<T:ITexelElement, let sampleCount:int, let format:int>
public extension _Image<T, __Shape2D, 1, 1, sampleCount, 1, format> {
    public void get_dimensions(out float width, out float height, out float elements, out float sampleCount) {
        ImageType texture = RWImages[this.index];
        texture.GetDimensions(width, height, elements, sampleCount);
    }
    public void get_dimensions(out int width, out int height, out int elements, out int sampleCount) {
        ImageType texture = RWImages[this.index];
        texture.GetDimensions(width, height, elements, sampleCount);
    }
    public void get_dimensions(out uint width, out uint height, out uint elements, out uint sampleCount) {
        ImageType texture = RWImages[this.index];
        texture.GetDimensions(width, height, elements, sampleCount);
    }
}

// Shape 3D, Read-Only, Non-array, Non-MS
__generic<T:ITexelElement, let sampleCount:int, let format:int>
public extension _Image<T, __Shape3D, 0, 0, sampleCount, 0, format> {
    public void get_dimensions(out float width, out float height, out float depth) {
        ImageType texture = Images[this.index];
        texture.GetDimensions(width, height, depth);
    }
    public void get_dimensions(uint mipLevel, out float width, out float height, out float depth, out float numberOfLevels) {
        ImageType texture = Images[this.index];
        texture.GetDimensions(mipLevel, width, height, depth, numberOfLevels);
    }
    public void get_dimensions(out int width, out int height, out int depth) {
        ImageType texture = Images[this.index];
        texture.GetDimensions(width, height, depth);
    }
    public void get_dimensions(uint mipLevel, out int width, out int height, out int depth, out int numberOfLevels) {
        ImageType texture = Images[this.index];
        texture.GetDimensions(mipLevel, width, height, depth, numberOfLevels);
    }
    public void get_dimensions(out uint width, out uint height, out uint depth) {
        ImageType texture = Images[this.index];
        texture.GetDimensions(width, height, depth);
    }
    public void get_dimensions(uint mipLevel, out uint width, out uint height, out uint depth, out uint numberOfLevels) {
        ImageType texture = Images[this.index];
        texture.GetDimensions(mipLevel, width, height, depth, numberOfLevels);
    }
}

// Shape 3D, Read/Write, Non-array, Non-MS
__generic<T:ITexelElement, let sampleCount:int, let format:int>
public extension _Image<T, __Shape3D, 0, 0, sampleCount, 1, format> {
    public void get_dimensions(out float width, out float height, out float depth) {
        ImageType texture = RWImages[this.index];
        texture.GetDimensions(width, height, depth);
    }
    public void get_dimensions(uint mipLevel, out float width, out float height, out float depth, out float numberOfLevels) {
        ImageType texture = RWImages[this.index];
        texture.GetDimensions(mipLevel, width, height, depth, numberOfLevels);
    }
    public void get_dimensions(out int width, out int height, out int depth) {
        ImageType texture = RWImages[this.index];
        texture.GetDimensions(width, height, depth);
    }
    public void get_dimensions(uint mipLevel, out int width, out int height, out int depth, out int numberOfLevels) {
        ImageType texture = RWImages[this.index];
        texture.GetDimensions(mipLevel, width, height, depth, numberOfLevels);
    }
    public void get_dimensions(out uint width, out uint height, out uint depth) {
        ImageType texture = RWImages[this.index];
        texture.GetDimensions(width, height, depth);
    }
    public void get_dimensions(uint mipLevel, out uint width, out uint height, out uint depth, out uint numberOfLevels) {
        ImageType texture = RWImages[this.index];
        texture.GetDimensions(mipLevel, width, height, depth, numberOfLevels);
    }
}

// Shape Cube, Read-Only, Non-array, Non-MS
__generic<T:ITexelElement, let sampleCount:int, let format:int>
public extension _Image<T, __ShapeCube, 0, 0, sampleCount, 0, format> {
    public void get_dimensions(out float width, out float height) {
        ImageType texture = Images[this.index];
        texture.GetDimensions(width, height);
    }
    public void get_dimensions(uint mipLevel, out float width, out float height, out float numberOfLevels) {
        ImageType texture = Images[this.index];
        texture.GetDimensions(mipLevel, width, height, numberOfLevels);
    }
    public void get_dimensions(out int width, out int height) {
        ImageType texture = Images[this.index];
        texture.GetDimensions(width, height);
    }
    public void get_dimensions(uint mipLevel, out int width, out int height, out int numberOfLevels) {
        ImageType texture = Images[this.index];
        texture.GetDimensions(mipLevel, width, height, numberOfLevels);
    }
    public void get_dimensions(out uint width, out uint height) {
        ImageType texture = Images[this.index];
        texture.GetDimensions(width, height);
    }
    public void get_dimensions(uint mipLevel, out uint width, out uint height, out uint numberOfLevels) {
        ImageType texture = Images[this.index];
        texture.GetDimensions(mipLevel, width, height, numberOfLevels);
    }
}

// Shape Cube, Read/Write, Non-array, Non-MS
__generic<T:ITexelElement, let sampleCount:int, let format:int>
public extension _Image<T, __ShapeCube, 0, 0, sampleCount, 1, format> {
    public void get_dimensions(out float width, out float height) {
        ImageType texture = RWImages[this.index];
        texture.GetDimensions(width, height);
    }
    public void get_dimensions(uint mipLevel, out float width, out float height, out float numberOfLevels) {
        ImageType texture = RWImages[this.index];
        texture.GetDimensions(mipLevel, width, height, numberOfLevels);
    }
    public void get_dimensions(out int width, out int height) {
        ImageType texture = RWImages[this.index];
        texture.GetDimensions(width, height);
    }
    public void get_dimensions(uint mipLevel, out int width, out int height, out int numberOfLevels) {
        ImageType texture = RWImages[this.index];
        texture.GetDimensions(mipLevel, width, height, numberOfLevels);
    }
    public void get_dimensions(out uint width, out uint height) {
        ImageType texture = RWImages[this.index];
        texture.GetDimensions(width, height);
    }
    public void get_dimensions(uint mipLevel, out uint width, out uint height, out uint numberOfLevels) {
        ImageType texture = RWImages[this.index];
        texture.GetDimensions(mipLevel, width, height, numberOfLevels);
    }
}

// Shape Cube, Read-Only, Array, Non-MS
__generic<T:ITexelElement, let sampleCount:int, let format:int>
public extension _Image<T, __ShapeCube, 1, 0, sampleCount, 0, format> {
    public void get_dimensions(out float width, out float height, out float elements) {
        ImageType texture = Images[this.index];
        texture.GetDimensions(width, height, elements);
    }
    public void get_dimensions(uint mipLevel, out float width, out float height, out float elements, out float numberOfLevels) {
        ImageType texture = Images[this.index];
        texture.GetDimensions(mipLevel, width, height, elements, numberOfLevels);
    }
    public void get_dimensions(out int width, out int height, out int elements) {
        ImageType texture = Images[this.index];
        texture.GetDimensions(width, height, elements);
    }
    public void get_dimensions(uint mipLevel, out int width, out int height, out int elements, out int numberOfLevels) {
        ImageType texture = Images[this.index];
        texture.GetDimensions(mipLevel, width, height, elements, numberOfLevels);
    }
    public void get_dimensions(out uint width, out uint height, out uint elements) {
        ImageType texture = Images[this.index];
        texture.GetDimensions(width, height, elements);
    }
    public void get_dimensions(uint mipLevel, out uint width, out uint height, out uint elements, out uint numberOfLevels) {
        ImageType texture = Images[this.index];
        texture.GetDimensions(mipLevel, width, height, elements, numberOfLevels);
    }
}

// Shape Cube, Read/Write, Array, Non-MS
__generic<T:ITexelElement, let sampleCount:int, let format:int>
public extension _Image<T, __ShapeCube, 1, 0, sampleCount, 1, format> {
    public void get_dimensions(out float width, out float height, out float elements) {
        ImageType texture = RWImages[this.index];
        texture.GetDimensions(width, height, elements);
    }
    public void get_dimensions(uint mipLevel, out float width, out float height, out float elements, out float numberOfLevels) {
        ImageType texture = RWImages[this.index];
        texture.GetDimensions(mipLevel, width, height, elements, numberOfLevels);
    }
    public void get_dimensions(out int width, out int height, out int elements) {
        ImageType texture = RWImages[this.index];
        texture.GetDimensions(width, height, elements);
    }
    public void get_dimensions(uint mipLevel, out int width, out int height, out int elements, out int numberOfLevels) {
        ImageType texture = RWImages[this.index];
        texture.GetDimensions(mipLevel, width, height, elements, numberOfLevels);
    }
    public void get_dimensions(out uint width, out uint height, out uint elements) {
        ImageType texture = RWImages[this.index];
        texture.GetDimensions(width, height, elements);
    }
    public void get_dimensions(uint mipLevel, out uint width, out uint height, out uint elements, out uint numberOfLevels) {
        ImageType texture = RWImages[this.index];
        texture.GetDimensions(mipLevel, width, height, elements, numberOfLevels);
    }
}
