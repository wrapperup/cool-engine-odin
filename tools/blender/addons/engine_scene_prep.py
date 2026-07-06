bl_info = {
    "name": "Cool Engine Editor",
    "author": "vivian",
    "version": (2, 1, 0),
    "blender": (4, 0, 0),
    "location": "View3D > N-panel > Engine",
    "description": "Tag Blender objects as engine entities (reflection probes, ...) with gizmos + exported extras.",
    "category": "Object",
}

import os
import uuid

import bpy
import gpu
from gpu_extras.batch import batch_for_shader
from mathutils import Vector

# Every engine entity carries this ID custom property (a string). It exports to glTF node.extras,
# so the engine dispatches entity creation on extras["engine_type"] instead of per-type booleans.
ENGINE_TYPE_KEY = "engine_type"

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
    # `tag_only` types are applied to an EXISTING object (a mesh, or a collection instance linked
    # from an asset .blend) instead of spawning an empty — so the artist sees real geometry in the
    # viewport while the engine only reads the `asset` path + node transform and ignores the mesh.
    "static_mesh": {
        "label": "Static Mesh",
        "tag_only": True,
        "note": "asset auto-derives from a linked collection instance on export",
        "props": {
            "asset": (
                "",
                dict(description="Engine mesh path relative to the asset root, e.g. "
                     "assets/meshes/static/sm_x.glb (auto-derived for linked collection instances)"),
            ),
            "material": (
                0.0,
                dict(min=0.0, soft_min=0.0, soft_max=16.0, precision=0,
                     description="Material id/index the engine binds for this mesh"),
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


def _refresh_derived_assets(context, autotag=False):
    """Keep every static-mesh instance's `asset` in sync with the collection it links. Called before
    export. When `autotag` is on, also tag any *untagged* linked instance as a static_mesh first — so
    props dragged from the Asset Browser export with no manual tagging step. Returns (#tagged, #synced)."""
    tagged = synced = 0
    for obj in context.view_layer.objects:
        tag = obj.get(ENGINE_TYPE_KEY)
        if tag is None and autotag and _is_linked_instance(obj):
            apply_entity_type(obj, "static_mesh")  # only claims untagged objects, never reclassifies
            tag = "static_mesh"
            tagged += 1
        if tag == "static_mesh":
            derived = _derive_asset_path(context, obj)
            if derived:
                obj["asset"] = derived
                synced += 1
    return tagged, synced


def _static_mesh_warnings(context):
    """Read-only: problems with tagged static_mesh objects, so a dead asset reference is caught in
    Blender instead of crashing the engine at load. Safe from panel draw (no mutation). Flags:
      - empty `asset` (object isn't a linked instance, or derive failed), and
      - an `asset` path outside EXPECTED_ASSET_PREFIX (Asset Root set too deep)."""
    out = []
    for obj in context.view_layer.objects:
        if obj.get(ENGINE_TYPE_KEY) != "static_mesh":
            continue
        path = obj.get("asset", "")
        if not path:
            out.append(obj.name + ": no asset path (not a linked collection instance?)")
        elif not path.startswith(EXPECTED_ASSET_PREFIX):
            out.append(obj.name + ": '" + path + "' not under '" + EXPECTED_ASSET_PREFIX +
                       "' (set Asset Root to the project root)")
    return out


def _new_id():
    """A fresh entity id: uuid4 in canonical 8-4-4-4-12 form (e.g. '3f2504e0-4f89-41d3-9a0c-0305e82c3301').
    The dashed form is what the engine's core:encoding/uuid `read` expects — bare .hex (no dashes) is
    rejected as Invalid_Length."""
    return str(uuid.uuid4())


def _tagged_objects(context):
    """Every object in the view layer currently tagged as an engine entity (any type)."""
    return [o for o in context.view_layer.objects if o.get(ENGINE_TYPE_KEY) in ENTITY_TYPES]


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
    for obj in bpy.context.view_layer.objects:
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

        col = layout.column(align=True)
        col.label(text="Add / tag entity:")
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
                if name in obj.keys():
                    box.prop(obj, f'["{name}"]', slider=True)  # slider=True => shows the range
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

        # Quick Export: write <current_blend>.glb next to the file, no dialog. Right-click the
        # button -> Assign Shortcut to bind a key for fast iterate-in-game loops.
        layout.separator()
        col = layout.column(align=True)
        if bpy.data.filepath:
            col.label(text="Export -> " + os.path.splitext(os.path.basename(bpy.data.filepath))[0] + ".glb")
        else:
            col.label(text="Save the .blend to enable export", icon='ERROR')
        col.operator("scene.engine_quick_export", icon='EXPORT')

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
        # Target mirrors the source: props/barrel.blend -> props/barrel.glb, which is exactly the
        # path _derive_asset_path reconstructs. Press it while authoring a prop to refresh its .glb.
        blend = bpy.data.filepath
        if not blend:
            self.report({'ERROR'}, "Save the .blend first — export writes <blend>.glb next to it")
            return {'CANCELLED'}
        out = os.path.splitext(blend)[0] + ".glb"
        # Sync (and optionally auto-tag) static_mesh paths against their linked libraries first,
        # then validate so a dead asset reference surfaces here instead of asserting in the engine.
        tagged, _ = _refresh_derived_assets(context, autotag=context.scene.engine_autotag_linked)
        stamped = _ensure_engine_ids(context)
        warnings = _static_mesh_warnings(context)
        for w in warnings:
            print("[engine export] WARNING:", w)  # full detail in the system console
        bpy.ops.export_scene.gltf(
            'EXEC_DEFAULT',                 # execute directly, skip the file browser
            filepath=out,
            export_format='GLB',
            export_extras=True,            # object custom props -> node.extras (engine_type, priority, ...)
            export_tangents=True,          # bake tangents so the engine skips per-load mikktspace (needs a UV map)
            use_selection=False,
        )
        parts = []
        if tagged:
            parts.append(f"+{tagged} auto-tagged")
        if stamped:
            parts.append(f"+{stamped} id-stamped")
        suffix = f" ({', '.join(parts)})" if parts else ""
        if warnings:
            self.report({'WARNING'},
                        "Exported " + os.path.basename(out) + " with " + str(len(warnings)) +
                        " asset issue(s) — see System Console")
        else:
            self.report({'INFO'}, "Exported " + os.path.basename(out) + suffix)
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
