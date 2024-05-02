# Odin ImGui

## Generated Dear ImGui bindings using dear_bindings

 - Generates bindings for both the `master` and `docking` ImGui branches, using [`dear_bindings`](https://github.com/dearimgui/dear_bindings)
 - Contains bindings for most of the Dear ImGui implementations
	- All backends which exist in `vendor:` have bindings
	- These include: `vulkan, sdl2, opengl3, sdlrenderer2, glfw, dx11, dx12, win32, osx, metal`
 - Compiles bindings as well as any wanted backends
 - Tested on Windows, Linux, and Mac
 - Includes several examples which can be used as a reference
	- `GLFW + OpenGL, SDL2 + D3D11, SDL2 + Metal, SDL2 + OpenGL, SDL2 + SDL2 Renderer, SDL2 + Vulkan`

## Usage
If you don't want to configure and or build yourself, a prebuilt binary has been committed to the repository.
 - Only binaries for Windows are committed at the moment. I've tested on Linux, it's just hard to manually get both binaries in there.
 - It has all backends listed in `build.py` enabled, which almost definitely more than you need. I strongly suggest building yourself with your wanted backends.

## Building

Building is entirely automated, using `build.py`. All platforms should work (not not: open an issue!), but currently Mac backends are untested as I don't have a Mac (help wanted!)

 0. Dependencies
	- `git` must be in your path
	- `dear_bindings` depends on a library called "`ply`". [link](https://www.dabeaz.com/ply/).
		- You can probably install this with `python -m pip install ply`
		- If your distro manages Python packages, it may be called `python-ply` or similar.
	- Windows depends on that [`vcvarsall.bat`](https://learn.microsoft.com/en-us/cpp/build/building-on-the-command-line?view=msvc-170) is in your path.
	- Linux and OSX depend on `clang`, `ar`
 1. Clone this repository.
	- Optionally configure build at the top of `build.py`
 2. Run `python build.py`
 3. Repository is importable. Copy into your project, or import directly.

## Configuring

Search for `@CONFIGURE` to see everything configurable.

### `active_branch`
The bindings have been tested against the main two branches of Dear ImGui: `master` and `docking`.
You can choose between the two by changing `active_branch`

### `wanted_backends`
This project allows you to compile ImGui backends alongside imgui itself, which is what Dear ImGui recommends you do.
Bindings have been written for a subset of the backends provided by ImGui
 - You can see if a backend is supported by checking the `backends` table in `build.py`.
 - If a backend is supported it means that:
	- Bindings have been written to `imgui_impl.odin`
	- It has been successfully compiled in the latest revision, for both supported branches.
 - Some backends have external dependencies. These will automatically be cloned into `backend_deps` if necessary.
 - You can enable a backend by adding it to `wanted_backends`
 - You can enable backends not officially supported. (If it works, please MR!)

### `compile_debug`
If set to true, will compile with debug flags

## Examples

There are some examples in `examples/`. They are runnable directly.

## Available backends

All backends which can be supported with only `vendor` have bindings now.
It seems likely to me that SDL3, maybe WebGPU (and Android?) will exist in vendor in the future, at which point I'll add support.

| Backend        | Has bindings | Has example | Comment                                                              |
|----------------|:------------:|:-----------:|----------------------------------------------------------------------|
| Allegro 5      |      No      |     No      | No odin bindings in vendor                                           |
| Android        |      No      |     No      | No odin bindings in vendor                                           |
| Directx 9      |      No      |     No      | No odin bindings in vendor                                           |
| Directx 10     |      No      |     No      | No odin bindings in vendor                                           |
| Directx 11     |     Yes      |     Yes     |                                                                      |
| Directx 12     |     Yes      |     No      | Bindings created, but not tested                                     |
| GLFW           |     Yes      |     Yes     |                                                                      |
| GLUT           |      No      |     No      | Obsolete. Likely will never be implemented.                          |
| Metal          |     Yes      |     Yes     |                                                                      |
| OpenGL 2       |      No      |     No      |                                                                      |
| OpenGL 3       |     Yes      |     Yes     |                                                                      |
| OSX            |     Yes      |     No      |                                                                      |
| SDL 2          |     Yes      |     Yes     |                                                                      |
| SDL 3          |      No      |     No      | No odin bindings in vendor (yet)                                     |
| SDL_Renderer 2 |     Yes      |     Yes     | Has example, but Odin vendor library lacks required version (2.0.18) |
| SDL_Renderer 3 |      No      |     No      | No odin bindings in vendor (yet)                                     |
| Vulkan         |     Yes      |     No      | Tested in my own engine, but no example yet due to size              |
| WebGPU         |      No      |     No      | No odin bindings in vendor                                           |
| win32          |      No      |     No      | Bindings created, but not tested                                     |

## Updating

The Dear ImGui commits which have been tested against are listed in `build.py`.
You can mess with these all you want and see if it works.

When updating, a new commit should be chosen for `master` which is right before `master` was merged into `docking`. The `docking` commit should be the following merge commit.
Additionally, when updating, all backends in `imgui_impl.odin` should be checked for new commits, and updated where necessary.

## Coming soon
 - Respect defines from `imconfig.h`
 - Generate functions to restore overloads from `imgui.h` C++ header.
 - Helper file to work with ImGui in a way that is more Odin-ey

## Help wanted!

 - If there are any issues, or this package doesn't do everything you want it to, feel free to make an issue, or message me on Discord @ldash4.
 - I have not yet tested on Apple devices (though I intend to). If someone with more knowledge about OSX started this initiative though, it would be appreciated!
 - A few useful examples have yet to be created in `examples/`.
	- Vulkan - This is implicitly tested against my own private project, but it would be good to have an example.
	- Win32 - This should be quite easy, I just haven't had the time.
	- DX12 - I'm not a DX12 expert, and this is one of the more complicated examples.
	- All apple examples
