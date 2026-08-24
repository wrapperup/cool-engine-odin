bl_info = {
    "name": "Cool Engine Editor",
    "author": "vivian",
    "version": (2, 6, 1),
    "blender": (4, 0, 0),
    "location": "View3D > N-panel > Engine",
    "description": "Tag Blender objects as engine entities (reflection probes, ...) with gizmos + exported extras.",
    "category": "Object",
}

import hashlib
import math
import os
import struct
import time
import uuid
from array import array

import bpy
import gpu
from bpy.app.handlers import persistent
from gpu_extras.batch import batch_for_shader
from mathutils import Matrix, Vector

# Every engine entity carries this ID custom property (a string). It exports to glTF node.extras,
# so the engine dispatches entity creation on extras["engine_type"] instead of per-type booleans.
ENGINE_TYPE_KEY = "engine_type"
EXPORT_EXCLUDE_KEY = "engine_exclude_export"

# Every engine entity also carries a stable unique id (uuid4, canonical 8-4-4-4-12 string) in this
# custom property. It rides
# along to glTF node.extras and is the join key the engine's editor-data layer / bake sidecar use to
# attach derived data (baked atlases, bake status) to an entity across re-exports — surviving renames
# and node reordering, which names and indices don't. Stamped on tag/create; a pre-export pass
# (_ensure_engine_ids) guarantees uniqueness after Blender object duplication copies the prop verbatim.
ENGINE_ID_KEY = "engine_id"

# The engine loads asset paths relative to its working dir (project root), and everything lives under
# assets/. A derived `asset` that doesn't start with this means Asset Root is set too deep (e.g. at
# the assets/ folder itself), so the engine's path would be missing the prefix and fail to load.
EXPECTED_ASSET_PREFIX = "assets/"

HEIGHTFIELD_MAGIC = b"HFLD"
HEIGHTFIELD_VERSION = 1
HEIGHTFIELD_HEADER = struct.Struct("<4sIIIffffff")

HF_COUNT_X = "engine_heightfield_count_x"
HF_COUNT_Z = "engine_heightfield_count_z"
HF_MIN_X = "engine_heightfield_min_x"
HF_MAX_Y = "engine_heightfield_max_y"
HF_SPACING_X = "engine_heightfield_spacing_x"
HF_SPACING_Y = "engine_heightfield_spacing_y"
HF_TOPOLOGY_HASH = "engine_heightfield_topology_hash"

_AUTO_EXPORT_STATUS_KEY = "engine_scene_prep_auto_export_status"
_AUTO_EXPORT_RUNNING = False
SCENE_ASSET_NAME_KEY = "engine_asset_name"
SCENE_ASSET_ID_KEY = "engine_asset_id"
SCENE_VARIANT_ASSET_NAME_KEY = "engine_modifier_asset_name"
SCENE_VARIANT_ASSET_ID_KEY = "engine_modifier_asset_id"
_TEMP_EXPORT_COLLECTION_PREFIX = "__ENGINE_SCENE_EXPORT__"




# ---------------------------------------------------------------------------
# Add-on preferences (global, per-machine)
#
# The asset root is a property of the project checkout on this machine, not of any one scene, so it
# lives in AddonPreferences (saved with user preferences) instead of per-scene. Scenes saved by the
# old per-scene version keep a plain `scene["engine_asset_root"]` custom prop; _asset_root() still
# honors it as a fallback so old files keep exporting correctly until prefs are set.
# ---------------------------------------------------------------------------
class EngineScenePrepPreferences(bpy.types.AddonPreferences):
    bl_idname = __name__

    asset_root: bpy.props.StringProperty(
        name="Asset Root",
        description="Folder the engine's asset paths are relative to (the project root); static_mesh "
                    "'asset' auto-derives the linked library path against this. Global for all scenes",
        subtype='DIR_PATH',
        default="",
    )

    def draw(self, context):
        self.layout.prop(self, "asset_root")


def _prefs():
    """The add-on's preferences, or None when running unregistered from the Text Editor (Alt+P)."""
    addon = bpy.context.preferences.addons.get(__name__)
    return addon.preferences if addon else None


def _asset_root(context):
    """Absolute asset-root path. Prefs (global) > legacy per-scene value > the .blend's own folder."""
    prefs = _prefs()
    root = (prefs.asset_root if prefs else "") or context.scene.get("engine_asset_root", "") or "//"
    return bpy.path.abspath(root)

# ---------------------------------------------------------------------------
# Entity type registry
#
# Each type declares how to create it and its per-type properties. Properties are ID custom
# properties (obj["..."]) so they ride along in glTF extras. `ui` is passed straight to
# id_properties_ui(name).update(...) for drag range / precision / tooltip.
# ---------------------------------------------------------------------------
ENTITY_TYPES = {
    "reflection_probe": {
        "label": "Reflection Probe",
        "empty_display": 'CUBE',
        "note": "half_extents = object scale (keep rotation identity)",
        "props": {
            "blend_distance": (
                1.0,
                dict(min=0.0, soft_min=0.0, soft_max=20.0, precision=3,
                     description="World-space distance the reflection fades over, past the box surface"),
            ),
            "intensity": (
                1.0,
                dict(min=0.0, soft_min=0.0, soft_max=4.0, precision=3,
                     description="Reflection strength multiplier"),
            ),
            "priority": (
                0.0,
                dict(soft_min=0.0, soft_max=16.0, precision=0,
                     description="Higher wins where probes overlap (claims coverage first)"),
            ),
        },
    },
    # `tag_only` types are applied to an EXISTING object (a local mesh, or a collection instance
    # linked from an asset .blend) instead of spawning an empty. Local meshes are built beside the
    # scene in <scene-name>/<asset-name>.glb; linked instances retain their external asset path.
    "static_mesh": {
        "label": "Static Mesh",
        "tag_only": True,
        "note": "linked assets stay external; local meshes build into the scene's asset folder",
        "props": {
            "asset": (
                "",
                dict(description="Engine mesh path relative to the asset root, e.g. "
                     "assets/meshes/static/sm_x.glb (derived automatically during scene export)"),
            ),
            "material": (
                0.0,
                dict(min=0.0, soft_min=0.0, soft_max=16.0, precision=0,
                     description="Material id/index the engine binds for this mesh"),
            ),
        },
    },
    "heightfield": {
        "label": "Terrain Heightfield",
        "tag_only": True,
        "note": "fixed grid; Sculpt Terrain locks local X/Y and permits elevation changes only",
        "props": {
            "heightfield_asset": (
                "",
                dict(description="Generated collision/render data; assigned automatically on export"),
            ),
            "material": (
                0.0,
                dict(min=0.0, soft_min=0.0, soft_max=16.0, precision=0,
                     description="Material id/index the engine binds for this terrain"),
            ),
            "uv_scale": (
                1.0,
                dict(min=0.001, soft_min=0.01, soft_max=32.0, precision=3,
                     description="Number of texture repeats across the complete terrain"),
            ),
        },
    },
    "ddgi_volume": {
        "label": "DDGI Volume",
        "empty_display": 'CUBE',
        "note": "grid AABB half-extents = object scale (keep rotation identity)",
        "props": {
            "probe_spacing": (
                2.5,
                dict(min=0.1, soft_min=0.5, soft_max=10.0, precision=2,
                     description="Target world units between probes; the engine derives probe counts "
                                 "from the box size and re-fits spacing to span it exactly"),
            ),
            "edge_fade": (
                1.0,
                dict(min=0.0, soft_min=0.0, soft_max=10.0, precision=2,
                     description="World units outside the box over which GI influence fades out "
                                 "(only matters at volume seams/overlaps)"),
            ),
            "priority": (
                0.0,
                dict(soft_min=0.0, soft_max=16.0, precision=0,
                     description="Higher wins where volumes overlap (claims coverage first)"),
            ),
        },
    },
    # Add more here, e.g.:
    # "point_light":  {"label": "Point Light",  "empty_display": 'SPHERE',      "props": {...}},
    # "spawn_point":  {"label": "Spawn Point",  "empty_display": 'PLAIN_AXES',  "props": {}},
}


def _derive_asset_path(context, obj):
    """If `obj` instances a collection linked from an external .blend, return the engine mesh path:
    the library file, made relative to the configured asset root, with a .glb extension and forward
    slashes. Returns "" when not derivable (not a linked instance, or a different drive) so callers
    leave any hand-entered `asset` value untouched."""
    col = getattr(obj, "instance_collection", None)
    if col is None or col.library is None:
        return ""
    lib_abs = bpy.path.abspath(col.library.filepath)
    root = _asset_root(context)
    try:
        rel = os.path.relpath(lib_abs, root)
    except ValueError:
        return ""  # library on a different Windows drive than the asset root
    return (os.path.splitext(rel)[0] + ".glb").replace("\\", "/")


def _is_linked_instance(obj):
    """True if `obj` is a collection instance whose collection is linked from an external .blend —
    i.e. a prop dragged in from the Asset Browser with Import Method = Link."""
    col = getattr(obj, "instance_collection", None)
    return col is not None and col.library is not None


def _is_local_scene_mesh(obj):
    """A mesh authored by this scene rather than supplied by a linked Blender library."""
    return (obj.type == 'MESH' and obj.library is None and obj.data is not None and
            obj.data.library is None and not _is_linked_instance(obj) and
            obj.get(ENGINE_TYPE_KEY) != "heightfield")




def _export_objects(context):
    return list(context.scene.objects)


def _refresh_derived_assets(context, autotag=False):
    """Classify scene geometry and refresh linked static-mesh paths before a scene build.

    Linked collection instances keep their existing external assets. Untagged local mesh objects are
    scene-owned static meshes; their generated paths are assigned later once the scene filename is
    known. Returns (#tagged, #synced).
    """
    tagged = synced = 0
    for obj in _export_objects(context):
        tag = obj.get(ENGINE_TYPE_KEY)
        if tag is None:
            if autotag and _is_linked_instance(obj):
                apply_entity_type(obj, "static_mesh")
                tag = "static_mesh"
                tagged += 1
            elif _is_local_scene_mesh(obj):
                apply_entity_type(obj, "static_mesh")
                tag = "static_mesh"
                tagged += 1
        if tag == "static_mesh":
            derived = _derive_asset_path(context, obj)
            if derived:
                if obj.get("asset") != derived:
                    obj["asset"] = derived
                    synced += 1
    return tagged, synced


def _static_mesh_warnings(context):
    """Read-only: problems with tagged static_mesh objects, so a dead asset reference is caught in
    Blender instead of crashing the engine at load. Safe from panel draw (no mutation). Flags:
      - empty `asset` after path preparation, and
      - an `asset` path outside EXPECTED_ASSET_PREFIX (Asset Root set too deep)."""
    out = []
    for obj in _export_objects(context):
        if obj.get(ENGINE_TYPE_KEY) != "static_mesh":
            continue
        path = obj.get("asset", "")
        if not path:
            out.append(obj.name + ": no linked or scene-local asset path")
        elif not path.startswith(EXPECTED_ASSET_PREFIX):
            out.append(obj.name + ": '" + path + "' not under '" + EXPECTED_ASSET_PREFIX +
                       "' (set Asset Root to the project root)")
    return out


def _heightfield_topology_hash(mesh):
    """Stable fingerprint for the vertex/face connectivity that terrain sculpting must preserve."""
    digest = hashlib.sha256()
    digest.update(struct.pack("<II", len(mesh.vertices), len(mesh.polygons)))
    for polygon in mesh.polygons:
        digest.update(struct.pack("<I", len(polygon.vertices)))
        for vertex_index in polygon.vertices:
            digest.update(struct.pack("<I", vertex_index))
    return digest.hexdigest()


def _set_heightfield_metadata(mesh, count_x, count_z, min_x, max_y, spacing_x, spacing_y):
    mesh[HF_COUNT_X] = count_x
    mesh[HF_COUNT_Z] = count_z
    mesh[HF_MIN_X] = min_x
    mesh[HF_MAX_Y] = max_y
    mesh[HF_SPACING_X] = spacing_x
    mesh[HF_SPACING_Y] = spacing_y
    mesh[HF_TOPOLOGY_HASH] = _heightfield_topology_hash(mesh)


def _heightfield_info(obj, check_xy=True):
    """Return (sample metadata, errors) for a terrain created by this add-on.

    Rows are stored in increasing engine Z order, which is decreasing Blender local Y because the
    glTF coordinate conversion is (x, y, z) -> (x, z, -y).
    """
    errors = []
    if obj.type != 'MESH':
        return None, [obj.name + ": heightfield must be a mesh object"]
    mesh = obj.data
    required = (HF_COUNT_X, HF_COUNT_Z, HF_MIN_X, HF_MAX_Y, HF_SPACING_X, HF_SPACING_Y,
                HF_TOPOLOGY_HASH)
    missing = [key for key in required if key not in mesh]
    if missing:
        return None, [obj.name + ": not an Engine-created terrain grid (missing metadata)"]

    count_x = int(mesh[HF_COUNT_X])
    count_z = int(mesh[HF_COUNT_Z])
    min_x = float(mesh[HF_MIN_X])
    max_y = float(mesh[HF_MAX_Y])
    spacing_x = float(mesh[HF_SPACING_X])
    spacing_y = float(mesh[HF_SPACING_Y])
    if count_x < 2 or count_z < 2 or spacing_x <= 0 or spacing_y <= 0:
        errors.append(obj.name + ": invalid grid metadata")
    expected_vertices = count_x * count_z
    expected_faces = (count_x - 1) * (count_z - 1)
    if len(mesh.vertices) != expected_vertices:
        errors.append(f"{obj.name}: topology changed ({len(mesh.vertices)} vertices, expected "
                      f"{expected_vertices})")
    if len(mesh.polygons) != expected_faces:
        errors.append(f"{obj.name}: topology changed ({len(mesh.polygons)} faces, expected "
                      f"{expected_faces})")
    if _heightfield_topology_hash(mesh) != mesh[HF_TOPOLOGY_HASH]:
        errors.append(obj.name + ": face connectivity changed")
    if obj.modifiers:
        errors.append(obj.name + ": modifiers are not supported by the fixed-grid terrain MVP")

    _, rotation, scale = obj.matrix_basis.decompose()
    if any(abs(component - 1.0) > 1e-5 for component in scale):
        errors.append(obj.name + ": apply object scale before export")
    if abs(abs(rotation.normalized().w) - 1.0) > 1e-5:
        errors.append(obj.name + ": apply object rotation before export")

    if check_xy and len(mesh.vertices) == expected_vertices:
        tolerance = max(spacing_x, spacing_y) * 1e-4
        drifted = 0
        for row in range(count_z):
            expected_y = max_y - row * spacing_y
            for column in range(count_x):
                vertex = mesh.vertices[row * count_x + column]
                expected_x = min_x + column * spacing_x
                if abs(vertex.co.x - expected_x) > tolerance or abs(vertex.co.y - expected_y) > tolerance:
                    drifted += 1
        if drifted:
            errors.append(f"{obj.name}: {drifted} grid vertices moved horizontally (use Repair XY Grid)")

    heights = []
    if len(mesh.vertices) == expected_vertices:
        heights = [float(vertex.co.z) for vertex in mesh.vertices]
        if any(not math.isfinite(height) for height in heights):
            errors.append(obj.name + ": terrain contains a non-finite height")

    return {
        "count_x": count_x,
        "count_z": count_z,
        "min_x": min_x,
        "origin_z": -max_y,
        "spacing_x": spacing_x,
        "spacing_z": spacing_y,
        "heights": heights,
    }, errors


def _heightfield_objects(context):
    return [obj for obj in _export_objects(context)
            if obj.get(ENGINE_TYPE_KEY) == "heightfield"]


def _heightfield_relative_path(obj):
    return "assets/gen/heightfields/" + obj[ENGINE_ID_KEY] + ".hfld"


def _export_heightfields(context):
    """Validate every terrain first, then atomically write all sidecars. Returns (count, errors)."""
    terrains = _heightfield_objects(context)
    if not terrains:
        return 0, []

    root = os.path.normpath(_asset_root(context))
    if not os.path.isdir(os.path.join(root, "assets")):
        return 0, ["Asset Root must be the project root containing the assets/ folder: " + root]

    prepared = []
    errors = []
    for obj in terrains:
        info, obj_errors = _heightfield_info(obj)
        errors.extend(obj_errors)
        if not obj_errors:
            relative = _heightfield_relative_path(obj)
            prepared.append((obj, info, relative, os.path.join(root, *relative.split("/"))))
    if errors:
        return 0, errors

    for obj, info, relative, absolute in prepared:
        heights = info["heights"]
        minimum = min(heights)
        maximum = max(heights)
        header = HEIGHTFIELD_HEADER.pack(
            HEIGHTFIELD_MAGIC,
            HEIGHTFIELD_VERSION,
            info["count_x"],
            info["count_z"],
            info["spacing_x"],
            info["spacing_z"],
            info["min_x"],
            info["origin_z"],
            minimum,
            maximum,
        )
        try:
            os.makedirs(os.path.dirname(absolute), exist_ok=True)
            temporary = absolute + ".tmp"
            with open(temporary, "wb") as output:
                output.write(header)
                output.write(struct.pack(f"<{len(heights)}f", *heights))
            os.replace(temporary, absolute)
        except OSError as exc:
            errors.append(f"{obj.name}: failed to write {absolute}: {exc}")
            continue
        if obj.get("heightfield_asset") != relative:
            obj["heightfield_asset"] = relative

    return len(prepared) - len(errors), errors


def _safe_asset_name(name):
    """Turn a Blender data name into a stable, readable filename stem."""
    cleaned = []
    previous_was_separator = False
    for character in name.strip():
        keep = character.isalnum() or character in "-_"
        if keep:
            cleaned.append(character)
            previous_was_separator = False
        elif not previous_was_separator:
            cleaned.append("_")
            previous_was_separator = True
    result = "".join(cleaned).strip("_. ")
    return result or "mesh"


def _scene_mesh_objects(context):
    return [obj for obj in _export_objects(context)
            if obj.get(ENGINE_TYPE_KEY) == "static_mesh" and _is_local_scene_mesh(obj)]


def _hash_foreach(digest, collection, property_name, value_count, typecode):
    values = array(typecode, [0]) * value_count
    collection.foreach_get(property_name, values)
    digest.update(values.tobytes())


def _evaluated_mesh(context, obj):
    depsgraph = context.evaluated_depsgraph_get()
    return bpy.data.meshes.new_from_object(
        obj.evaluated_get(depsgraph),
        preserve_all_data_layers=True,
        depsgraph=depsgraph,
    )


def _mesh_signature(mesh):
    """Fingerprint static mesh payload, including normals and texture/color layers."""
    mesh.calc_loop_triangles()

    digest = hashlib.sha256()
    digest.update(struct.pack(
        "<IIII",
        len(mesh.vertices),
        len(mesh.loops),
        len(mesh.polygons),
        len(mesh.loop_triangles),
    ))
    _hash_foreach(digest, mesh.vertices, "co", len(mesh.vertices) * 3, 'f')
    _hash_foreach(digest, mesh.loop_triangles, "vertices", len(mesh.loop_triangles) * 3, 'I')
    _hash_foreach(digest, mesh.loop_triangles, "loops", len(mesh.loop_triangles) * 3, 'I')
    _hash_foreach(digest, mesh.polygons, "material_index", len(mesh.polygons), 'i')
    _hash_foreach(digest, mesh.polygons, "use_smooth", len(mesh.polygons), 'b')

    corner_normals = getattr(mesh, "corner_normals", None)
    if corner_normals is not None:
        _hash_foreach(digest, corner_normals, "vector", len(corner_normals) * 3, 'f')

    for layer in mesh.uv_layers:
        digest.update(layer.name.encode("utf-8") + b"\0")
        _hash_foreach(digest, layer.data, "uv", len(layer.data) * 2, 'f')

    for attribute in mesh.color_attributes:
        digest.update((attribute.name + "\0" + attribute.domain + "\0" + attribute.data_type).encode("utf-8"))
        _hash_foreach(digest, attribute.data, "color", len(attribute.data) * 4, 'f')

    for layer in mesh.uv_layers:
        digest.update(bytes([layer.active_render]))
    digest.update(struct.pack("<iii", mesh.uv_layers.active_index,
                              mesh.color_attributes.active_color_index,
                              mesh.color_attributes.render_color_index))
    if mesh.shape_keys:
        for key in mesh.shape_keys.key_blocks:
            digest.update(key.name.encode("utf-8") + b"\0")
            _hash_foreach(digest, key.data, "co", len(key.data) * 3, 'f')
    return digest.hexdigest()


def _evaluated_mesh_signature(context, obj):
    """Hash the payload-relevant result of an Object's evaluated modifier stack."""
    mesh = None
    try:
        mesh = _evaluated_mesh(context, obj)
        if not mesh.vertices or not mesh.polygons:
            return None, obj.name + ": evaluated mesh has no triangles"
        return _mesh_signature(mesh), None
    except Exception as exc:
        return None, f"{obj.name}: failed to evaluate modifiers: {exc}"
    finally:
        if mesh is not None and mesh.users == 0:
            bpy.data.meshes.remove(mesh)


def _prepare_scene_mesh_jobs(context, blend):
    """Build raw Mesh assets plus deduplicated evaluated variants for modified Objects."""
    objects = sorted(_scene_mesh_objects(context), key=lambda obj: obj.name)
    if not objects:
        return [], []
    if not blend:
        return [], ["Save the .blend before exporting scene-local meshes"]

    root = os.path.normpath(_asset_root(context))
    scene_folder = os.path.splitext(os.path.abspath(blend))[0]
    try:
        inside_root = os.path.normcase(os.path.commonpath((root, scene_folder))) == os.path.normcase(root)
    except ValueError:
        inside_root = False
    if not inside_root:
        return [], ["Scene must be inside the configured Asset Root: " + root]

    mesh_groups = {}
    for obj in objects:
        key = obj.data.as_pointer()
        if key not in mesh_groups:
            mesh_groups[key] = [obj.data, []]
        mesh_groups[key][1].append(obj)

    meshes = sorted(mesh_groups.values(), key=lambda group: (group[0].name.casefold(), group[0].name))
    seen_ids = set()
    for mesh, _ in meshes:
        asset_id = mesh.get(SCENE_ASSET_ID_KEY)
        if not asset_id or asset_id in seen_ids:
            asset_id = _new_id()
            mesh[SCENE_ASSET_ID_KEY] = asset_id
        seen_ids.add(asset_id)
        mesh.id_properties_ui(SCENE_ASSET_ID_KEY).update(
            description="Stable identity for this scene-owned mesh asset",
        )

    entries = []
    errors = []
    for mesh, users in meshes:
        plain_users = [obj for obj in users if not obj.modifiers]
        if plain_users:
            entries.append({
                "mesh": mesh,
                "signature": _mesh_signature(mesh),
                "representative": None,
                "users": plain_users,
                "sort_key": (mesh.name.casefold(), "", mesh.name),
            })

        variants = {}
        for obj in (candidate for candidate in users if candidate.modifiers):
            signature, error = _evaluated_mesh_signature(context, obj)
            if error:
                errors.append(error)
                continue
            variants.setdefault(signature, []).append(obj)
        for signature, variant_users in variants.items():
            representative = variant_users[0]
            entries.append({
                "mesh": mesh,
                "signature": signature,
                "representative": representative,
                "users": variant_users,
                "sort_key": (mesh.name.casefold(), representative.name.casefold(), signature),
            })

    entries.sort(key=lambda entry: entry["sort_key"])
    seen_asset_ids = set()
    for entry in entries:
        mesh = entry["mesh"]
        representative = entry["representative"]
        users = entry["users"]
        if representative is None:
            asset_id = mesh[SCENE_ASSET_ID_KEY]
        else:
            asset_id = next(
                (obj.get(SCENE_VARIANT_ASSET_ID_KEY) for obj in users
                 if obj.get(SCENE_VARIANT_ASSET_ID_KEY)),
                "",
            )
            if not asset_id or asset_id in seen_asset_ids:
                asset_id = _new_id()
            for obj in users:
                obj[SCENE_VARIANT_ASSET_ID_KEY] = asset_id
                obj.id_properties_ui(SCENE_VARIANT_ASSET_ID_KEY).update(
                    description="Stable identity for this evaluated modifier result",
                )
        if asset_id in seen_asset_ids:
            asset_id = _new_id()
            if representative is None:
                mesh[SCENE_ASSET_ID_KEY] = asset_id
            else:
                for obj in users:
                    obj[SCENE_VARIANT_ASSET_ID_KEY] = asset_id
        seen_asset_ids.add(asset_id)

        if representative is None:
            # v2.4.0 stored this on the Object. Adopt that value when upgrading a file.
            legacy_name = next(
                (obj.get(SCENE_ASSET_NAME_KEY) for obj in users if obj.get(SCENE_ASSET_NAME_KEY)),
                "",
            )
            base = _safe_asset_name(mesh.get(SCENE_ASSET_NAME_KEY, "") or legacy_name or mesh.name)
        else:
            legacy_name = next(
                (obj.get(SCENE_VARIANT_ASSET_NAME_KEY) for obj in users
                 if obj.get(SCENE_VARIANT_ASSET_NAME_KEY)),
                "",
            )
            base = _safe_asset_name(legacy_name or representative.name or mesh.name)
        entry["asset_id"] = asset_id
        entry["base_name"] = base

    used_names = set()
    jobs = []
    for entry in entries:
        mesh = entry["mesh"]
        representative = entry["representative"]
        users = entry["users"]
        asset_id = entry["asset_id"]
        base = entry["base_name"]
        candidate = base
        if candidate.casefold() in used_names:
            candidate = base + "_" + asset_id[:8]
        serial = 2
        while candidate.casefold() in used_names:
            candidate = base + "_" + asset_id[:8] + "_" + str(serial)
            serial += 1
        used_names.add(candidate.casefold())
        if representative is None:
            mesh[SCENE_ASSET_NAME_KEY] = candidate
            mesh.id_properties_ui(SCENE_ASSET_NAME_KEY).update(
                description="Stable filename inside the scene's generated asset folder",
            )
        else:
            for obj in users:
                obj[SCENE_VARIANT_ASSET_NAME_KEY] = candidate
                obj.id_properties_ui(SCENE_VARIANT_ASSET_NAME_KEY).update(
                    description="Stable filename for this evaluated modifier result",
                )

        absolute = os.path.join(scene_folder, candidate + ".glb")
        relative = os.path.relpath(absolute, root).replace("\\", "/")
        for obj in users:
            if obj.get("asset") != relative:
                obj["asset"] = relative
        jobs.append((mesh, representative, users, relative, absolute, entry["signature"]))
    return jobs, errors


def _new_temp_export_collection(context):
    collection = bpy.data.collections.new(_TEMP_EXPORT_COLLECTION_PREFIX + uuid.uuid4().hex[:8])
    context.scene.collection.children.link(collection)
    return collection


def _remove_temp_export_collection(collection):
    for obj in list(collection.objects):
        mesh = obj.data if obj.type == 'MESH' else None
        bpy.data.objects.remove(obj, do_unlink=True)
        if mesh is not None and mesh.users == 0:
            bpy.data.meshes.remove(mesh)
    bpy.data.collections.remove(collection)


def _export_scene_mesh_job(context, job):
    """Export a raw Mesh datablock or one deduplicated evaluated modifier result."""
    source_mesh, representative, _, _, absolute, _ = job
    collection = _new_temp_export_collection(context)
    temporary = absolute + ".tmp.glb"
    previously_selected = list(context.selected_objects)
    previously_active = context.view_layer.objects.active
    try:
        mesh = _evaluated_mesh(context, representative) if representative else source_mesh.copy()
        if not mesh.vertices or not mesh.polygons:
            label = representative.name if representative else source_mesh.name
            return label + ": mesh has no triangles"
        proxy = bpy.data.objects.new("Mesh", mesh)
        collection.objects.link(proxy)
        proxy.matrix_world = Matrix.Identity(4)

        # Select the evaluated proxy explicitly to avoid exporting Geometry Nodes
        # pieces again as separate depsgraph objects.
        for selected in previously_selected:
            selected.select_set(False)
        proxy.select_set(True)
        context.view_layer.objects.active = proxy

        os.makedirs(os.path.dirname(absolute), exist_ok=True)
        result = bpy.ops.export_scene.gltf(
            'EXEC_DEFAULT',
            filepath=temporary,
            export_format='GLB',
            export_extras=False,
            export_tangents=True,
            export_materials='NONE',
            collection=collection.name,
            use_selection=True,
        )
        if 'FINISHED' not in result:
            label = representative.name if representative else source_mesh.name
            return label + ": mesh GLB export was cancelled"
        os.replace(temporary, absolute)
        return None
    except Exception as exc:
        label = representative.name if representative else source_mesh.name
        return f"{label}: mesh GLB export failed: {exc}"
    finally:
        if os.path.exists(temporary):
            try:
                os.remove(temporary)
            except OSError:
                pass
        _remove_temp_export_collection(collection)
        for selected in previously_selected:
            if selected.name in context.view_layer.objects:
                selected.select_set(True)
        if (previously_active is not None and
                previously_active.name in context.view_layer.objects):
            context.view_layer.objects.active = previously_active


def _copy_entity_properties(source, proxy):
    type_id = source.get(ENGINE_TYPE_KEY)
    keys = (ENGINE_TYPE_KEY, ENGINE_ID_KEY, *ENTITY_TYPES[type_id]["props"].keys())
    for key in keys:
        if key in source:
            proxy[key] = source[key]


def _export_scene_proxies(context, out):
    """Export only engine entity proxies; mesh payloads live in their separate asset GLBs."""
    collection = _new_temp_export_collection(context)
    temporary = out + ".tmp.glb"
    try:
        for source in sorted(_tagged_objects(context), key=lambda obj: obj.name):
            proxy = bpy.data.objects.new("Entity_" + source.name, None)
            collection.objects.link(proxy)
            proxy.matrix_world = source.matrix_world.copy()
            _copy_entity_properties(source, proxy)
        result = bpy.ops.export_scene.gltf(
            'EXEC_DEFAULT',
            filepath=temporary,
            export_format='GLB',
            export_extras=True,
            export_materials='NONE',
            collection=collection.name,
        )
        if 'FINISHED' in result:
            os.replace(temporary, out)
        return result
    finally:
        if os.path.exists(temporary):
            try:
                os.remove(temporary)
            except OSError:
                pass
        _remove_temp_export_collection(collection)


def _prepare_export_metadata(context, blend=None):
    """Apply lightweight metadata mutations before a .blend save or an explicit export."""
    tagged, synced = _refresh_derived_assets(
        context,
        autotag=getattr(context.scene, "engine_autotag_linked", True),
    )
    stamped = _ensure_engine_ids(context)
    scene_mesh_jobs, scene_mesh_errors = _prepare_scene_mesh_jobs(context, blend)
    if scene_mesh_errors:
        raise RuntimeError(scene_mesh_errors[0])
    for obj in _heightfield_objects(context):
        relative = _heightfield_relative_path(obj)
        if obj.get("heightfield_asset") != relative:
            obj["heightfield_asset"] = relative
    return tagged, synced, stamped, scene_mesh_jobs




def _set_auto_export_status(message):
    bpy.app.driver_namespace[_AUTO_EXPORT_STATUS_KEY] = message


def _layer_collections(root):
    """Yield a view layer's collection tree, including descendants of excluded collections."""
    yield root
    for child in root.children:
        yield from _layer_collections(child)


def _include_excluded_engine_collections(context):
    """Temporarily include excluded collections that contain engine entities.

    Blender 5.2 can export stale identity matrix_world values for objects in collections excluded
    from the active view layer. The glTF still contains those nodes when use_selection/use_visible
    filtering is disabled, but their translation and scale are lost. Including them long enough for
    a dependency-graph update makes the exporter see the correct transforms.
    """
    changed = []
    excluded = set()
    for layer_collection in _layer_collections(context.view_layer.layer_collection):
        if not layer_collection.exclude:
            continue
        if any(obj not in excluded and
               (obj.get(ENGINE_TYPE_KEY) in ENTITY_TYPES or _is_local_scene_mesh(obj))
               for obj in layer_collection.collection.all_objects):
            layer_collection.exclude = False
            changed.append(layer_collection)
    if changed:
        context.view_layer.update()
    return changed


def _restore_excluded_collections(context, changed):
    for layer_collection in reversed(changed):
        layer_collection.exclude = True
    if changed:
        context.view_layer.update()


def _export_scene(context, blend):
    """Shared manual/automatic export path. Returns (success, message, warnings)."""
    if not blend:
        return False, "Save the .blend first — export writes <blend>.glb next to it", []

    start = time.perf_counter()
    out = os.path.splitext(blend)[0] + ".glb"
    included_collections = _include_excluded_engine_collections(context)
    try:
        tagged, _, stamped, scene_mesh_jobs = _prepare_export_metadata(context, blend)
        heightfield_count, heightfield_errors = _export_heightfields(context)
        if heightfield_errors:
            for error in heightfield_errors:
                print("[engine terrain] ERROR:", error)
            message = "Terrain export failed: " + heightfield_errors[0]
            if len(heightfield_errors) > 1:
                message += " (see console)"
            return False, message, []

        warnings = _static_mesh_warnings(context)
        for warning in warnings:
            print("[engine export] WARNING:", warning)

        scene_mesh_count = 0
        for job in scene_mesh_jobs:
            error = _export_scene_mesh_job(context, job)
            if error is not None:
                return False, "Scene mesh export failed: " + error, warnings
            scene_mesh_count += 1

        try:
            result = _export_scene_proxies(context, out)
        except Exception as exc:
            print("[engine export] ERROR:", exc)
            return False, "Scene GLB export failed — see System Console", warnings
        if 'FINISHED' not in result:
            return False, "glTF export was cancelled", warnings

        parts = []
        if tagged:
            parts.append(f"+{tagged} auto-tagged")
        if stamped:
            parts.append(f"+{stamped} id-stamped")
        if heightfield_count:
            parts.append(f"{heightfield_count} terrain baked")
        if scene_mesh_count:
            parts.append(f"{scene_mesh_count} mesh asset(s) rebuilt")
        suffix = f" ({', '.join(parts)})" if parts else ""
        message = f"Exported {os.path.basename(out)} in {time.perf_counter() - start:.2f}s" + suffix
        if warnings:
            return True, message + f" with {len(warnings)} asset issue(s) — see System Console", warnings
        return True, message, warnings
    finally:
        _restore_excluded_collections(context, included_collections)


def _new_id():
    """A fresh entity id: uuid4 in canonical 8-4-4-4-12 form (e.g. '3f2504e0-4f89-41d3-9a0c-0305e82c3301').
    The dashed form is what the engine's core:encoding/uuid `read` expects — bare .hex (no dashes) is
    rejected as Invalid_Length."""
    return str(uuid.uuid4())


def _tagged_objects(context):
    """Exportable objects currently tagged as an engine entity (any type)."""
    return [o for o in _export_objects(context) if o.get(ENGINE_TYPE_KEY) in ENTITY_TYPES]


def _ensure_engine_ids(context):
    """Guarantee every tagged entity has a unique engine_id; return how many were (re)stamped.

    Blender duplication (Shift+D / Alt+D / copy-paste) copies custom props verbatim, so a duplicate
    inherits the source's engine_id — two entities sharing one join key would silently corrupt each
    other's derived data. Run this right before export (the moment the id reaches the engine): scan in
    name order so a stable winner keeps the id, then re-stamp anything missing or colliding. Blender
    names duplicates 'X.001', which sorts after the original 'X', so the original keeps its id and the
    duplicate takes the fresh one."""
    seen = set()
    stamped = 0
    for obj in sorted(_tagged_objects(context), key=lambda o: o.name):
        cur = obj.get(ENGINE_ID_KEY)
        if not cur or cur in seen:
            cur = _new_id()
            obj[ENGINE_ID_KEY] = cur
            stamped += 1
        seen.add(cur)
    return stamped


def apply_entity_type(obj, type_id):
    """Tag `obj` as `type_id`, stamp a stable engine_id if it has none, and (re)apply default props +
    UI limits. Existing property VALUES are preserved — only missing ones are seeded — so this doubles
    as a 'refresh limits'."""
    spec = ENTITY_TYPES[type_id]
    obj[ENGINE_TYPE_KEY] = type_id
    if not obj.get(ENGINE_ID_KEY):
        obj[ENGINE_ID_KEY] = _new_id()
    if type_id == "static_mesh" and _is_local_scene_mesh(obj):
        mesh = obj.data
        if not mesh.get(SCENE_ASSET_ID_KEY):
            mesh[SCENE_ASSET_ID_KEY] = _new_id()
        if not mesh.get(SCENE_ASSET_NAME_KEY):
            mesh[SCENE_ASSET_NAME_KEY] = _safe_asset_name(mesh.name or obj.name)
        mesh.id_properties_ui(SCENE_ASSET_NAME_KEY).update(
            description="Stable filename inside the scene's generated asset folder",
        )
        if obj.modifiers:
            if not obj.get(SCENE_VARIANT_ASSET_ID_KEY):
                obj[SCENE_VARIANT_ASSET_ID_KEY] = _new_id()
            if not obj.get(SCENE_VARIANT_ASSET_NAME_KEY):
                obj[SCENE_VARIANT_ASSET_NAME_KEY] = _safe_asset_name(obj.name)
            obj.id_properties_ui(SCENE_VARIANT_ASSET_NAME_KEY).update(
                description="Stable filename for this evaluated modifier result",
            )
    for name, (default, ui) in spec["props"].items():
        if name not in obj.keys():
            obj[name] = default
        elif type(obj[name]) is not type(default):
            # A hand-added prop can arrive as the wrong type (e.g. `material` typed as a whole
            # number in the Custom Properties panel is stored as an int). Applying the spec's
            # float UI limits to an int property raises TypeError — coerce to the spec's type
            # first, keeping the value.
            try:
                obj[name] = type(default)(obj[name])
            except (TypeError, ValueError):
                obj[name] = default
        obj.id_properties_ui(name).update(**ui)


# ---------------------------------------------------------------------------
# Gizmos
# ---------------------------------------------------------------------------
def _box_line_coords(center, ext):
    c, e = Vector(center), Vector(ext)
    signs = [(-1, -1, -1), (1, -1, -1), (1, 1, -1), (-1, 1, -1),
             (-1, -1,  1), (1, -1,  1), (1, 1,  1), (-1, 1,  1)]
    p = [c + Vector((sx * e.x, sy * e.y, sz * e.z)) for (sx, sy, sz) in signs]
    edges = [(0, 1), (1, 2), (2, 3), (3, 0), (4, 5), (5, 6), (6, 7), (7, 4),
             (0, 4), (1, 5), (2, 6), (3, 7)]
    out = []
    for a, b in edges:
        out.append(tuple(p[a]))
        out.append(tuple(p[b]))
    return out


def _draw_reflection_probe(obj, shader):
    m = obj.matrix_world
    center = m.translation
    ext = m.to_scale()                       # world-AABB half-extents (rotation ignored)
    blend = float(obj.get("blend_distance", 1.0))

    # The engine fades influence INWARD from the walls over blend_distance (Unity-style, and the
    # only region where box projection is valid). So the object's box is the influence boundary
    # (w=0 at the walls) and the full-strength core is that box shrunk inward by blend (w=1).
    core = (max(ext.x - blend, 0.0), max(ext.y - blend, 0.0), max(ext.z - blend, 0.0))
    for coords, color in (
        (_box_line_coords(center, ext),  (0.25, 0.8, 1.0, 1.0)),   # influence boundary (w=0 outside)
        (_box_line_coords(center, core), (0.25, 0.8, 1.0, 0.35)),  # full-strength core (w=1)
    ):
        batch = batch_for_shader(shader, 'LINES', {"pos": coords})
        shader.bind()
        shader.uniform_float("color", color)
        batch.draw(shader)


def _ddgi_probe_coords(center, ext, spacing_target):
    """Probe grid positions, mirroring the engine's derivation (src/scene.odin \"ddgi_volume\"):
    counts from the target spacing (clamped 2..64 per axis), spacing re-fit so the grid spans
    the box exactly."""
    counts = []
    spacing = []
    for i in range(3):
        size = 2.0 * ext[i]
        n = max(2, min(64, int(round(size / max(spacing_target, 1e-4))) + 1))
        counts.append(n)
        spacing.append(size / (n - 1))
    origin = (center[0] - ext[0], center[1] - ext[1], center[2] - ext[2])
    return [
        (origin[0] + ix * spacing[0], origin[1] + iy * spacing[1], origin[2] + iz * spacing[2])
        for ix in range(counts[0])
        for iy in range(counts[1])
        for iz in range(counts[2])
    ]


# obj name -> (params key, probe point batch). A 32x8x32 volume is ~8k points; rebuilding the
# vertex buffer every viewport redraw is the expensive part, so cache until the params change.
# Stale entries for deleted/renamed objects are just a little memory until the next reload.
_PROBE_BATCH_CACHE = {}

_MAX_PROBE_DOTS = 70000  # 64^3 worst case is ~262k points; skip dots for absurd grids


def _draw_ddgi_volume(obj, shader):
    m = obj.matrix_world
    center = m.translation
    ext = [abs(s) for s in m.to_scale()]     # grid AABB half-extents (rotation ignored)
    fade = float(obj.get("edge_fade", 1.0))

    # Influence fades OUTWARD from the walls over edge_fade (unlike reflection probes, which fade
    # inward): the object's box is the grid AABB at full strength; the faint outer box is where
    # influence reaches 0 in overlaps/seams.
    outer = (ext[0] + fade, ext[1] + fade, ext[2] + fade)
    for coords, color in (
        (_box_line_coords(center, ext),   (1.0, 0.7, 0.25, 1.0)),   # grid AABB (full strength)
        (_box_line_coords(center, outer), (1.0, 0.7, 0.25, 0.35)),  # influence boundary (w=0)
    ):
        batch = batch_for_shader(shader, 'LINES', {"pos": coords})
        shader.bind()
        shader.uniform_float("color", color)
        batch.draw(shader)

    # Probe dots.
    spacing_target = float(obj.get("probe_spacing", 2.5))
    key = (tuple(center), tuple(ext), spacing_target)
    cached = _PROBE_BATCH_CACHE.get(obj.name)
    if cached is None or cached[0] != key:
        coords = _ddgi_probe_coords(center, ext, spacing_target)
        if len(coords) > _MAX_PROBE_DOTS:
            coords = []
        cached = (key, batch_for_shader(shader, 'POINTS', {"pos": coords}))
        _PROBE_BATCH_CACHE[obj.name] = cached
    gpu.state.point_size_set(4.0)
    shader.bind()
    shader.uniform_float("color", (1.0, 0.7, 0.25, 0.7))
    cached[1].draw(shader)
    gpu.state.point_size_set(1.0)


# engine_type -> gizmo drawer(obj, shader)
GIZMOS = {
    "reflection_probe": _draw_reflection_probe,
    "ddgi_volume": _draw_ddgi_volume,
}


# Stashed in driver_namespace (persists across script re-runs) so a re-run removes the previous
# handler instead of leaking a duplicate.
_DRAW_NS_KEY = "engine_scene_prep_draw_handle"


def _draw():
    shader = gpu.shader.from_builtin('UNIFORM_COLOR')  # '3D_UNIFORM_COLOR' on Blender 3.x
    gpu.state.blend_set('ALPHA')
    gpu.state.line_width_set(1.5)
    view_layer = bpy.context.view_layer
    for obj in view_layer.objects:
        if not obj.visible_get(view_layer=view_layer):
            continue
        drawer = GIZMOS.get(obj.get(ENGINE_TYPE_KEY))
        if drawer is not None:
            drawer(obj, shader)
    gpu.state.line_width_set(1.0)
    gpu.state.blend_set('NONE')


# ---------------------------------------------------------------------------
# Operators + panel
# ---------------------------------------------------------------------------
class OBJECT_OT_engine_add_entity(bpy.types.Operator):
    bl_idname = "object.engine_add_entity"
    bl_label = "Add Engine Entity"
    bl_options = {'REGISTER', 'UNDO'}

    type_id: bpy.props.StringProperty()

    def execute(self, context):
        spec = ENTITY_TYPES.get(self.type_id)
        if spec is None:
            self.report({'ERROR'}, f"Unknown engine_type: {self.type_id}")
            return {'CANCELLED'}
        bpy.ops.object.empty_add(type=spec["empty_display"], radius=1.0, location=context.scene.cursor.location)
        obj = context.active_object
        obj.name = spec["label"].replace(" ", "")
        obj.empty_display_size = 1.0
        apply_entity_type(obj, self.type_id)
        return {'FINISHED'}


class OBJECT_OT_engine_add_heightfield(bpy.types.Operator):
    bl_idname = "object.engine_add_heightfield"
    bl_label = "Add Terrain"
    bl_description = "Create a fixed quad grid suitable for constrained heightfield sculpting"
    bl_options = {'REGISTER', 'UNDO'}

    resolution_x: bpy.props.IntProperty(
        name="Resolution X", default=129, min=2, max=1025,
        description="Number of height samples along local X",
    )
    resolution_z: bpy.props.IntProperty(
        name="Resolution Z", default=129, min=2, max=1025,
        description="Number of height samples along engine Z (Blender local Y)",
    )
    size_x: bpy.props.FloatProperty(
        name="Size X", default=128.0, min=0.001, soft_max=2048.0,
    )
    size_z: bpy.props.FloatProperty(
        name="Size Z", default=128.0, min=0.001, soft_max=2048.0,
    )

    def execute(self, context):
        count_x = self.resolution_x
        count_z = self.resolution_z
        spacing_x = self.size_x / (count_x - 1)
        spacing_y = self.size_z / (count_z - 1)
        min_x = -0.5 * self.size_x
        max_y = 0.5 * self.size_z

        # Rows run from +Blender-Y to -Blender-Y so their existing row-major order becomes
        # increasing engine Z after Blender's glTF axis conversion (engine Z = -Blender Y).
        vertices = [
            (min_x + column * spacing_x, max_y - row * spacing_y, 0.0)
            for row in range(count_z)
            for column in range(count_x)
        ]
        faces = []
        for row in range(count_z - 1):
            for column in range(count_x - 1):
                top_left = row * count_x + column
                top_right = top_left + 1
                bottom_left = top_left + count_x
                bottom_right = bottom_left + 1
                faces.append((top_left, bottom_left, bottom_right, top_right))

        mesh = bpy.data.meshes.new("TerrainHeightfield")
        mesh.from_pydata(vertices, [], faces)
        mesh.update()
        _set_heightfield_metadata(mesh, count_x, count_z, min_x, max_y, spacing_x, spacing_y)

        obj = bpy.data.objects.new("Terrain", mesh)
        context.collection.objects.link(obj)
        obj.location = context.scene.cursor.location
        obj.lock_rotation = (True, True, True)
        obj.lock_scale = (True, True, True)
        apply_entity_type(obj, "heightfield")

        for selected in context.selected_objects:
            selected.select_set(False)
        obj.select_set(True)
        context.view_layer.objects.active = obj
        self.report({'INFO'}, f"Created {count_x} x {count_z} terrain ({len(vertices)} samples)")
        return {'FINISHED'}


class OBJECT_OT_engine_sculpt_heightfield(bpy.types.Operator):
    bl_idname = "object.engine_sculpt_heightfield"
    bl_label = "Sculpt Terrain"
    bl_description = "Enter Sculpt Mode with local X/Y deformation locked and Z elevation unlocked"
    bl_options = {'REGISTER'}

    @classmethod
    def poll(cls, context):
        obj = context.active_object
        return obj is not None and obj.get(ENGINE_TYPE_KEY) == "heightfield"

    def execute(self, context):
        obj = context.active_object
        _, errors = _heightfield_info(obj)
        if errors:
            self.report({'ERROR'}, errors[0])
            return {'CANCELLED'}
        if obj.mode != 'OBJECT':
            bpy.ops.object.mode_set(mode='OBJECT')
        bpy.ops.object.mode_set(mode='SCULPT')

        sculpt = context.scene.tool_settings.sculpt
        sculpt.lock_x = True
        sculpt.lock_y = True
        sculpt.lock_z = False
        if getattr(obj, "use_dynamic_topology_sculpting", False):
            bpy.ops.sculpt.dynamic_topology_toggle()
        self.report({'INFO'}, "Terrain sculpt: local X/Y locked, Z unlocked, Dyntopo disabled")
        return {'FINISHED'}


class OBJECT_OT_engine_validate_heightfield(bpy.types.Operator):
    bl_idname = "object.engine_validate_heightfield"
    bl_label = "Validate Terrain"
    bl_description = "Check transforms, topology, grid positions, and height samples"
    bl_options = {'REGISTER'}

    @classmethod
    def poll(cls, context):
        obj = context.active_object
        return obj is not None and obj.get(ENGINE_TYPE_KEY) == "heightfield"

    def execute(self, context):
        obj = context.active_object
        info, errors = _heightfield_info(obj)
        if errors:
            for error in errors:
                print("[engine terrain] ERROR:", error)
            self.report({'ERROR'}, errors[0] + (" (see console)" if len(errors) > 1 else ""))
            return {'CANCELLED'}
        minimum = min(info["heights"])
        maximum = max(info["heights"])
        self.report({'INFO'}, f"Valid {info['count_x']} x {info['count_z']} terrain; "
                    f"height {minimum:.3f} .. {maximum:.3f}")
        return {'FINISHED'}


class OBJECT_OT_engine_repair_heightfield_xy(bpy.types.Operator):
    bl_idname = "object.engine_repair_heightfield_xy"
    bl_label = "Repair XY Grid"
    bl_description = "Restore every sample's original local X/Y while preserving sculpted heights"
    bl_options = {'REGISTER', 'UNDO'}

    @classmethod
    def poll(cls, context):
        obj = context.active_object
        return obj is not None and obj.get(ENGINE_TYPE_KEY) == "heightfield"

    def execute(self, context):
        obj = context.active_object
        if obj.mode != 'OBJECT':
            bpy.ops.object.mode_set(mode='OBJECT')
        info, errors = _heightfield_info(obj, check_xy=False)
        structural = [error for error in errors if "topology changed" in error or
                      "connectivity changed" in error or "metadata" in error]
        if structural:
            self.report({'ERROR'}, structural[0])
            return {'CANCELLED'}

        mesh = obj.data
        max_y = float(mesh[HF_MAX_Y])
        spacing_y = float(mesh[HF_SPACING_Y])
        for row in range(info["count_z"]):
            expected_y = max_y - row * spacing_y
            for column in range(info["count_x"]):
                vertex = mesh.vertices[row * info["count_x"] + column]
                vertex.co.x = info["min_x"] + column * info["spacing_x"]
                vertex.co.y = expected_y
        mesh.update()
        self.report({'INFO'}, "Restored terrain XY grid; sculpted heights were preserved")
        return {'FINISHED'}


class OBJECT_OT_engine_tag_entity(bpy.types.Operator):
    bl_idname = "object.engine_tag_entity"
    bl_label = "Tag Active Object"
    bl_description = "Tag the active object as this engine entity (for tag_only types like static_mesh)"
    bl_options = {'REGISTER', 'UNDO'}

    type_id: bpy.props.StringProperty()

    def execute(self, context):
        obj = context.active_object
        if obj is None:
            self.report({'ERROR'}, "No active object to tag")
            return {'CANCELLED'}
        if self.type_id not in ENTITY_TYPES:
            self.report({'ERROR'}, f"Unknown engine_type: {self.type_id}")
            return {'CANCELLED'}
        apply_entity_type(obj, self.type_id)
        derived = _derive_asset_path(context, obj)
        if derived:
            obj["asset"] = derived
            self.report({'INFO'}, f"Tagged {obj.name} -> {derived}")
        else:
            self.report({'INFO'}, f"Tagged {obj.name} as {self.type_id} (set 'asset' manually)")
        return {'FINISHED'}


class OBJECT_OT_engine_refresh(bpy.types.Operator):
    bl_idname = "object.engine_refresh"
    bl_label = "Refresh Limits"
    bl_description = "Re-apply default properties + UI limits to selected engine entities"
    bl_options = {'REGISTER', 'UNDO'}

    def execute(self, context):
        n = 0
        for obj in context.selected_objects:
            t = obj.get(ENGINE_TYPE_KEY)
            if t in ENTITY_TYPES:
                apply_entity_type(obj, t)
                n += 1
        self.report({'INFO'}, f"Refreshed {n} entity(ies)")
        return {'FINISHED'}




class VIEW3D_PT_engine_scene_prep(bpy.types.Panel):
    bl_space_type = 'VIEW_3D'
    bl_region_type = 'UI'
    bl_category = "Engine"
    bl_label = "Scene Prep"

    def draw(self, context):
        layout = self.layout

        if context.collection is not None:
            box = layout.box()
            box.label(text="Collection: " + context.collection.name, icon='OUTLINER_COLLECTION')
            box.prop(context.collection, EXPORT_EXCLUDE_KEY)

        col = layout.column(align=True)
        col.label(text="Add / tag entity:")
        col.operator("object.engine_add_heightfield", text="Terrain Heightfield", icon='MESH_GRID')
        # tag_only types (static_mesh) have no button: linked instances are auto-tagged on export,
        # and the object.engine_tag_entity operator stays available via search for manual cases.
        for type_id, spec in ENTITY_TYPES.items():
            if spec.get("tag_only"):
                continue
            col.operator("object.engine_add_entity", text=spec["label"], icon='CUBE').type_id = type_id

        obj = context.active_object
        t = obj.get(ENGINE_TYPE_KEY) if obj else None
        if t in ENTITY_TYPES:
            spec = ENTITY_TYPES[t]
            box = layout.box()
            box.label(text=f"{spec['label']}  ({t})", icon='CHECKMARK')
            eid = obj.get(ENGINE_ID_KEY)
            box.label(text=("id: " + eid[:12] + "...") if eid else "id: (stamped on export)")
            for name in spec["props"]:
                if t == "static_mesh" and _is_local_scene_mesh(obj) and name == "asset":
                    continue
                if name in obj.keys():
                    box.prop(obj, f'["{name}"]', slider=True)  # slider=True => shows the range
            if t == "static_mesh":
                if _is_linked_instance(obj):
                    box.label(text="Source: Linked Asset", icon='LINKED')
                elif _is_local_scene_mesh(obj):
                    box.label(text="Source: Scene Local", icon='MESH_DATA')
                    mesh = obj.data
                    box.label(text=f"Mesh: {mesh.name} ({mesh.users} object users)")
                    if obj.modifiers:
                        box.label(text=f"Evaluated modifiers: {len(obj.modifiers)}", icon='MODIFIER')
                        if SCENE_VARIANT_ASSET_NAME_KEY in obj:
                            box.prop(obj, f'["{SCENE_VARIANT_ASSET_NAME_KEY}"]', text="Asset Name")
                        else:
                            box.label(text="Modifier asset name assigned on export", icon='INFO')
                    elif SCENE_ASSET_NAME_KEY in mesh:
                        box.prop(mesh, f'["{SCENE_ASSET_NAME_KEY}"]', text="Asset Name")
                    if obj.get("asset"):
                        box.label(text=obj["asset"])
            if t == "heightfield" and obj.type == 'MESH':
                mesh = obj.data
                if HF_COUNT_X in mesh and HF_COUNT_Z in mesh:
                    box.label(text=f"Grid: {mesh[HF_COUNT_X]} x {mesh[HF_COUNT_Z]}")
                row = box.row(align=True)
                row.operator("object.engine_sculpt_heightfield", icon='SCULPTMODE_HLT')
                row.operator("object.engine_validate_heightfield", text="Validate", icon='CHECKMARK')
                box.operator("object.engine_repair_heightfield_xy", icon='LOOP_BACK')
                sculpt = context.scene.tool_settings.sculpt
                constrained = sculpt.lock_x and sculpt.lock_y and not sculpt.lock_z
                box.label(text="X/Y locked; Z editable" if constrained else
                          "Use Sculpt Terrain to lock X/Y", icon='LOCKED' if constrained else 'ERROR')
            box.operator("object.engine_refresh", icon='FILE_REFRESH')
            if spec.get("note"):
                box.label(text=spec["note"])
        elif obj is not None:
            layout.label(text="Active object is not an engine entity.")

        # Asset Browser: register the Asset Root as a library, then drag props into the scene with
        # Import Method = Link. Auto-tag turns those linked instances into static_mesh on export.
        layout.separator()
        col = layout.column(align=True)
        # Asset Root is global now — set it in Edit > Preferences > Add-ons > Engine Scene Prep.
        col.label(text="Asset Browser:")
        col.operator("scene.engine_register_asset_library", icon='ASSET_MANAGER')
        col.prop(context.scene, "engine_autotag_linked")
        col.label(text="Drag props with Import Method = Link", icon='INFO')
        col.label(text="Local meshes build into <scene-name>/", icon='MESH_DATA')

        # Quick Export: write <current_blend>.glb next to the file, no dialog. Right-click the
        # button -> Assign Shortcut to bind a key for fast iterate-in-game loops.
        layout.separator()
        col = layout.column(align=True)
        if bpy.data.filepath:
            col.label(text="Export -> " + os.path.splitext(os.path.basename(bpy.data.filepath))[0] + ".glb")
        else:
            col.label(text="Save the .blend to enable export", icon='ERROR')
        col.operator("scene.engine_quick_export", icon='EXPORT')
        auto_status = bpy.app.driver_namespace.get(_AUTO_EXPORT_STATUS_KEY, "")
        if auto_status:
            col.label(text=auto_status, icon='INFO')

        warnings = _static_mesh_warnings(context)
        if warnings:
            box = layout.box()
            box.label(text=str(len(warnings)) + " static_mesh issue(s):", icon='ERROR')
            for w in warnings[:6]:
                box.label(text=w)


class SCENE_OT_engine_quick_export(bpy.types.Operator):
    bl_idname = "scene.engine_quick_export"
    bl_label = "Quick Export glTF"
    bl_description = (
        "Export the current .blend to a GLB sitting next to it (<blend>.glb; GLB + custom "
        "properties, no dialog) — the file the engine loads for this asset/scene. "
        "Right-click > Assign Shortcut to bind a key"
    )

    def execute(self, context):
        success, message, warnings = _export_scene(context, bpy.data.filepath)
        _set_auto_export_status(message)
        if not success:
            self.report({'ERROR'}, message)
            return {'CANCELLED'}
        if warnings:
            self.report({'WARNING'}, message)
        else:
            self.report({'INFO'}, message)
        return {'FINISHED'}


class SCENE_OT_engine_register_asset_library(bpy.types.Operator):
    bl_idname = "scene.engine_register_asset_library"
    bl_label = "Register Asset Library"
    bl_description = (
        "Add the Asset Root folder to Blender's Asset Libraries so the .blend props inside it show "
        "up in the Asset Browser. Drag them into the scene with Import Method = Link"
    )

    def execute(self, context):
        root = _asset_root(context)
        if not os.path.isdir(root):
            self.report({'ERROR'}, "Set Asset Root to an existing folder first: " + root)
            return {'CANCELLED'}
        target = os.path.normpath(root)
        for lib in context.preferences.filepaths.asset_libraries:
            if os.path.normpath(bpy.path.abspath(lib.path)) == target:
                self.report({'INFO'}, "Already registered as '" + lib.name + "'")
                return {'CANCELLED'}
        bpy.ops.preferences.asset_library_add('EXEC_DEFAULT', directory=root)
        self.report({'INFO'}, "Registered asset library: " + root + " (save preferences to persist)")
        return {'FINISHED'}






_classes = (
    EngineScenePrepPreferences,
    OBJECT_OT_engine_add_entity,
    OBJECT_OT_engine_add_heightfield,
    OBJECT_OT_engine_sculpt_heightfield,
    OBJECT_OT_engine_validate_heightfield,
    OBJECT_OT_engine_repair_heightfield_xy,
    OBJECT_OT_engine_tag_entity,
    OBJECT_OT_engine_refresh,
    SCENE_OT_engine_register_asset_library,
    SCENE_OT_engine_quick_export,
    VIEW3D_PT_engine_scene_prep,
)


def _remove_stale_draw_handler():
    old = bpy.app.driver_namespace.pop(_DRAW_NS_KEY, None)
    if old is not None:
        try:
            bpy.types.SpaceView3D.draw_handler_remove(old, 'WINDOW')
        except Exception:
            pass




def register():
    _remove_stale_draw_handler()
    for c in _classes:
        try:
            bpy.utils.unregister_class(c)
        except RuntimeError:
            pass
        bpy.utils.register_class(c)
    bpy.types.Scene.engine_autotag_linked = bpy.props.BoolProperty(
        name="Auto-tag Linked Instances",
        description="On export, tag any collection instance linked from a library as a static_mesh, "
                    "so props dragged from the Asset Browser export without a manual tag step",
        default=True,
    )
    bpy.app.driver_namespace[_DRAW_NS_KEY] = bpy.types.SpaceView3D.draw_handler_add(
        _draw, (), 'WINDOW', 'POST_VIEW'
    )


def unregister():
    _remove_stale_draw_handler()
    if hasattr(bpy.types.Scene, "engine_autotag_linked"):
        del bpy.types.Scene.engine_autotag_linked
    for c in reversed(_classes):
        try:
            bpy.utils.unregister_class(c)
        except RuntimeError:
            pass


# Text Editor (Alt+P) hits this; installing as an add-on calls register() directly.
if __name__ == "__main__":
    register()
