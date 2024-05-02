import subprocess
from os import path
import os
import shutil
from glob import glob
import typing
import sys
import platform

# TODO:
# - Make this file never show it's call stack. Call stacks should mean that a child script failed.
# - Add self-documenting build.ini or similar, as to not require anyone to look
#		at this file unless they want to add a new backend.
# - It could be nice to be able to generate into another folder, or just say --copy-into../../my_cool_folder

# @CONFIGURE: Must be key into below table
active_branch = "docking"
git_heads = {
	# Default Dear ImGui branch
	"master": { "imgui": "v1.90.1", "dear_bindings": "0c33579" },
	# Docking branch
	"docking": { "imgui": "v1.90.1-docking", "dear_bindings": "0c33579" },
}

# @CONFIGURE: Elements must be keys into below table
wanted_backends = ["vulkan", "sdl2", "opengl3", "sdlrenderer2", "glfw", "dx11", "dx12", "win32", "osx", "metal"]
# Supported means that an impl bindings file exists, and that it has been tested.
# Some backends (like dx12, win32) have bindings but not been tested.
backends = {
	"allegro5":     { "supported": False },
	"android":      { "supported": False },
	"dx9":          { "supported": False, "enabled_on": ["windows"] },
	"dx10":         { "supported": False, "enabled_on": ["windows"] },
	"dx11":         { "supported": True,  "enabled_on": ["windows"] },
	# Bindings exist for DX12, but they are untested
	"dx12":         { "supported": False, "enabled_on": ["windows"] },
	"glfw":         { "supported": True,  "deps": ["glfw"] },
	"glut":         { "supported": False },
	"metal":        { "supported": True,  "enabled_on": ["darwin"] },
	"opengl2":      { "supported": False },
	"opengl3":      { "supported": True  },
	"osx":          { "supported": False, "enabled_on": ["darwin"] },
	"sdl2":         { "supported": True,  "deps": ["sdl2"] },
	"sdl3":         { "supported": False },
	"sdlrenderer2": { "supported": True,  "deps": ["sdl2"] },
	"sdlrenderer3": { "supported": False },
	"vulkan":       { "supported": True,  "defines": ["VK_NO_PROTOTYPES"], "deps": ["vulkan"] },
	"wgpu":         { "supported": False },
	# Bindings exist for win32, but they are untested
	"win32":        { "supported": False, "enabled_on": ["windows"] },
}

# Indirection for backend dependencies, as some might have the same dependency, and their commits can't get out of sync.
backend_deps = {
	"sdl2":   { "repo": "https://github.com/libsdl-org/SDL.git",              "commit": "release-2.28.3", "path": "SDL2" },
	"glfw":   { "repo": "https://github.com/glfw/glfw.git",                   "commit": "3eaf125",        "path": "glfw" },
	"vulkan": { "repo": "https://github.com/KhronosGroup/Vulkan-Headers.git", "commit": "4f51aac",        "path": "Vulkan-Headers" },
}

# @CONFIGURE:
compile_debug = False

platform_win32_like = platform.system() == "Windows"
platform_unix_like = platform.system() == "Linux" or platform.system() == "Darwin"

# Assert which doesn't clutter the output
def assertx(cond: bool, msg: str):
	if not cond:
		print(msg)
		exit(1)

def hashes_are_same_ish(first: str, second: str) -> bool:
	smallest_hash_size = min(len(first), len(second))
	assertx(smallest_hash_size >= 7, "Hashes not long enough to be sure")
	return first[:smallest_hash_size] == second[:smallest_hash_size]

def exec(cmd: typing.List[str], what: str) -> str:
	max_what_len = 40
	if len(what) > max_what_len:
		what = what[:max_what_len - 2] + ".."
	print(what + (" " * (max_what_len - len(what))) + "> " + " ".join(cmd))
	return subprocess.check_output(cmd).decode().strip()

def copy(from_path: str, files: typing.List[str], to_path: str):
	for file in files:
		shutil.copy(path.join(from_path, file), to_path)

def glob_copy(root_dir: str, glob_pattern: str, dest_dir: str):
	the_files = glob(root_dir=root_dir, pathname=glob_pattern)
	copy(root_dir, the_files, dest_dir)
	return the_files

def platform_select(the_options):
	""" Given a dict like eg. { "windows": "/DCOOL_DEFINE", "linux, darwin": "-DCOOL_DEFINE" }
	Returns the correct value for the active platform. """
	our_platform = platform.system().lower()
	for platforms_string in the_options:
		if platforms_string.lower().find(our_platform) != -1:
			return the_options[platforms_string]

	print(the_options)
	assertx(False, f"Couldn't find active platform ({our_platform}) in the above options!")

def pp(the_path: str) -> str:
	""" Given a path with '/' as a delimiter, returns an appropriate sys.platform path """
	return path.join(*the_path.split("/"))

def map_to_folder(files: typing.List[str], folder: str) -> typing.List[str]:
	return list(map(lambda file: path.join(folder, file), files))

def has_tool(tool: str) -> bool:
	try: subprocess.check_output([tool], stderr=subprocess.DEVNULL)
	except FileNotFoundError: return False
	except: return True
	else: return True

def ensure_checked_out_with_commit(dir: str, repo: str, wanted_commit: str):
	if not path.exists(dir):
		exec(["git", "clone", repo, dir], f"Cloning {dir}")

	exec(["git", "-c", "advice.detachedHead=false", "-C", dir, "checkout", wanted_commit], f"Checking out {dir}")

def get_platform_imgui_lib_name() -> str:
	""" Returns imgui binary name for system/processor """

	system = platform.system()

	processor = None
	if platform.machine() in ["AMD64", "x86_64"]: processor = "x64"
	if platform.machine() in ["arm64"]:           processor = "arm64"

	binary_ext = "lib" if system == "Windows" else "a"

	assertx(system != "", "System could not be determined")
	assertx(processor != None, f"Unexpected processor: {platform.machine()}")

	return f'imgui_{system.lower()}_{processor}.{binary_ext}'

def run_vcvars(cmd: typing.List[str], what):
	assertx(subprocess.run(f"vcvarsall.bat x64 && {' '.join(cmd)}").returncode == 0, f"Failed to run command '{cmd}'")

# TODO[TS]: This works, but there's a bug in Python, which makes cl.exe return with
# exit code 2 for no god damn reason at all, if not run with run_vcvars.
# If we're on windows, we can check for cl.exe, and re execute after calling vcvarsall, if available.
def did_re_execute() -> bool:
	if platform.system() != "Windows": return False
	if has_tool("cl"): return False
	if "-no_reexecute" in sys.argv: return False
	print("Re-executing with vcvarsall..")
	os.system("".join(["vcvarsall.bat x64 && ", sys.executable, " build.py -no_reexecute"]))
	return True

def main():
	assertx(path.isfile("build.py"), "You have to run the script from within the repository for now!")

	if did_re_execute(): return

	# Check that CLI tools are available
	assertx(has_tool("git"), "Git not available!")

	if platform.system() == "Windows":
		pass
		# Fun times! We can't check for this, for the reasons described above did_re_execute()
		# assertx(has_tool("cl") and has_tool("lib"), "cl.exe or lib.exe not in path - did you run vcvarsall.bat?")
	else:
		assertx(has_tool("clang"), "clang not found!")
		assertx(has_tool("ar"), "ar not found!")

	# Check out bindings generator tools
	ensure_checked_out_with_commit("imgui", "https://github.com/ocornut/imgui.git", git_heads[active_branch]["imgui"])
	ensure_checked_out_with_commit("dear_bindings", "https://github.com/dearimgui/dear_bindings.git", git_heads[active_branch]["dear_bindings"])

	# Check out backend dependencies
	if not path.isdir("backend_deps"): os.mkdir("backend_deps")
	backend_deps_names = set()
	for backend_name in wanted_backends:
		backend = backends[backend_name]

		for dep in backend.get("deps", []):
			backend_deps_names.add(dep)

	for backend_dep in backend_deps_names:
		full_dep = backend_deps[backend_dep]
		ensure_checked_out_with_commit(path.join("backend_deps", full_dep["path"]), full_dep["repo"], full_dep["commit"])

	# Clear the temp folder
	shutil.rmtree(path="temp", ignore_errors=True)
	os.mkdir("temp")

	# Generate bindings for active ImGui branch
	exec([sys.executable, pp("dear_bindings/dear_bindings.py"), "-o", pp("temp/c_imgui"), pp("imgui/imgui.h")], "Running dear_bindings")
	# Generate odin bindings from dear_bindings json file
	exec([sys.executable, pp("gen_odin.py"), path.join("temp", "c_imgui.json"), "imgui.odin"], "Running odin-imgui")

	# Find and copy imgui sources to temp folder
	_imgui_headers = glob_copy("imgui", "*.h", "temp")
	imgui_sources = glob_copy("imgui", "*.cpp", "temp")

	# Gather sources, defines, includes etc
	all_sources = imgui_sources
	all_sources += ["c_imgui.cpp"]

	# Basic flags
	compile_flags = platform_select({
		"windows": ['/DIMGUI_IMPL_API=extern\\\"C\\\"'],
		"linux, darwin": ['-DIMGUI_IMPL_API=extern\"C\"', "-fPIC", "-fno-exceptions", "-fno-rtti", "-fno-threadsafe-statics", "-std=c++11"],
	})

	# Optimization flags
	if compile_debug: compile_flags += platform_select({ "windows": ["/Od", "/Z7"], "linux, darwin": ["-g", "-O0"] })
	else: compile_flags += platform_select({ "windows": ["/O2"], "linux, darwin": ["-O3"] })

	# Write file describing the enabled backends
	f = open("impl_enabled.odin", "w+")
	f.writelines([
		"package imgui\n",
		"\n",
		"// This is a generated helper file which you can use to know which\n",
		"// implementations have been compiled into the bindings.\n",
		"\n",
	])

	# Write branch. This can be used to toggle docking and multi viewports at compile time
	f.writelines([f'IMGUI_BRANCH :: "{active_branch}"\n\n'])

	for backend_name in backends:
		f.writelines([f"BACKEND_{backend_name.upper()}_ENABLED :: {'true' if backend_name in wanted_backends else 'false'}\n"])

	# Find and copy imgui backend sources to temp folder
	for backend_name in wanted_backends:
		backend = backends[backend_name]

		if "enabled_on" in backend and not platform.system().lower() in backend["enabled_on"]:
			continue

		if not backend["supported"]:
			print(f"Warning: compiling backend '{backend_name}' which is not officially supported")

		glob_copy(pp("imgui/backends"), f"imgui_impl_{backend_name}.*", "temp")

		if backend_name in ["osx", "metal"]: all_sources += [f"imgui_impl_{backend_name}.mm"]
		else:                                all_sources += [f"imgui_impl_{backend_name}.cpp"]

		if backend_name == "opengl3":
			shutil.copy(pp("imgui/backends/imgui_impl_opengl3_loader.h"), "temp")

		for define in backend.get("defines", []): compile_flags += [platform_select({ "windows": f"/D{define}", "linux, darwin": f"-D{define}" })]

	# Add backend dependency include paths
	for backend_dep in backend_deps_names:
		# NOTE: For all backend deps so far, the include path is simply repo/include.
		# So we just hard code this here. One day we might have to specify this in `backend_deps`
		if platform_win32_like:  compile_flags += ["/I" + path.join("..", "backend_deps", backend_deps[backend_dep]["path"], "include")]
		elif platform_unix_like: compile_flags += ["-I" + path.join("..", "backend_deps", backend_deps[backend_dep]["path"], "include")]

	all_objects = []
	if platform_win32_like:  all_objects += map(lambda file: file.removesuffix(".cpp") + ".obj", all_sources)
	elif platform_unix_like:
		for file in all_sources:
			if file.endswith(".cpp"): all_objects.append(file.removesuffix(".cpp") + ".o")
			elif file.endswith(".mm"): all_objects.append(file.removesuffix(".mm") + ".o")

	os.chdir("temp")

	# cl.exe, *in particular*, won't work without running vcvarsall first, even if cl.exe is in the path.
	# See did_re_execute
	if platform_win32_like:  run_vcvars(["cl"] + compile_flags + ["/c"] + all_sources, "Compiling sources")
	elif platform_unix_like: exec(["clang"] + compile_flags + ["-c"] + all_sources, "Compiling sources")

	os.chdir("..")

	dest_binary = get_platform_imgui_lib_name()

	if platform_win32_like:  exec(["lib", "/OUT:" + dest_binary] + map_to_folder(all_objects, "temp"), "Making library from objects")
	elif platform_unix_like: exec(["ar", "rcs", dest_binary] + map_to_folder(all_objects, "temp"), "Making library from objects")

	expected_files = ["imgui.odin", "impl_enabled.odin", dest_binary]

	for file in expected_files:
		assertx(path.isfile(file), f"Missing file '{file}' in build folder! Something went wrong..")

	print("Looks like everything went ok!")

if __name__ == "__main__":
	main()
