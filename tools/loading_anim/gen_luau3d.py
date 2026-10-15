"""Emit Libraries/PaperPlaneLoadingScreen/LoadingAnimData.lua (3D variant) from the Blender motion + mesh.

Run inside Blender: gen(). Rows carry position, scale and rotation quaternion;
the plane itself is built in Roblox from the exported triangles (WedgeParts),
so no asset upload is needed.
"""
import os, importlib
import bpy
import motion
importlib.reload(motion)

HERE = os.path.dirname(os.path.abspath(__file__))

# Cloud shapes as ball clusters (x, y, radius), same as the Blender metaballs.
CLOUD_SHAPES = [
    [(-1.6, 0, 1.0), (-0.5, 0.45, 1.35), (0.7, 0.35, 1.2), (1.7, -0.05, 0.9), (0.1, -0.25, 1.1)],
    [(-1.0, 0, 0.85), (0, 0.4, 1.1), (1.0, 0.05, 0.8)],
    [(-2.2, -0.1, 0.8), (-1.2, 0.35, 1.05), (0, 0.6, 1.3), (1.2, 0.3, 1.0), (2.2, -0.1, 0.75), (0, -0.25, 1.0)],
    [(-0.7, 0, 0.75), (0.4, 0.3, 0.95), (1.2, -0.05, 0.6)],
]


def gen():
    me = bpy.data.scenes["PaperPlaneLoading"].objects["PaperPlane"].data
    tris = []
    for p in me.polygons:
        assert len(p.vertices) == 3
        tris.append("{" + ",".join("Vector3.new(%.4f,%.4f,%.4f)" % tuple(me.vertices[v].co) for v in p.vertices) + "}")

    def clip_rows(clip, n):
        rows = []
        for i in range(n):
            x, y, s, q = motion.frame_state(clip, i)
            rows.append("{%.3f,%.3f,%.3f,%.4f,%.4f,%.4f,%.4f}" % (x, y, s, q.x, q.y, q.z, q.w))
        return "{" + ",".join(rows) + "}"

    shapes = ",".join("{" + ",".join("{%.2f,%.2f,%.2f}" % b for b in shape) + "}" for shape in CLOUD_SHAPES)
    clouds = ",".join("{%d,%.2f,%.2f,%.2f,%.2f}" % (c[0] + 1, c[1], c[2], c[3], c[4]) for c in motion.CLOUDS)

    src = f"""--!strict
--[[
	@module LoadingAnimData
	@description GENERATED from the Blender scene "PaperPlaneLoading" (loading_anim/gen_luau3d.py)
	-- do not hand-edit. Paper plane loading-screen animation baked to 30 fps.

	Space is Blender's camera view: 16 x 9 units visible at depth 0, origin at
	centre, +x right, +y up, +z toward the viewer. Plane mesh: nose +y, span x.
	Frame row: {{x, y, scale, qx, qy, qz, qw}} (rotation quaternion).
	Triangle: three local-space corners. Cloud shape: {{x, y, radius}} balls.
	Cloud row: {{shape, x, y, scale, driftUnitsPerSecond}}.
]]

return {{
	FPS = {motion.FPS},
	SCREEN_W = 16,
	SCREEN_H = 9,
	CLOUD_WRAP = {motion.CLOUD_WRAP},
	Triangles = {{{",".join(tris)}}},
	CloudShapes = {{{shapes}}},
	Clouds = {{{clouds}}},
	Intro = {clip_rows("intro", motion.INTRO)},
	Loop = {clip_rows("loop", motion.LOOP)},
	Finale = {clip_rows("finale", motion.FINALE)},
}}
"""
    path = os.path.join(HERE, "..", "..", "src", "StarterPlayerScripts", "Bootstrapper", "Libraries",
                        "PaperPlaneLoadingScreen", "LoadingAnimData.lua")
    open(path, "w").write(src)
    return path, len(src)
