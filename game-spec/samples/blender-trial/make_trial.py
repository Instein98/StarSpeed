# 一次性试做脚本，不是最终素材。用法：blender --background --python make_trial.py
import bpy, bmesh, math, os
import numpy as np
from mathutils import Vector

OUT = os.path.dirname(os.path.abspath(__file__))
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene


def lin(hexstr):
    h = hexstr.lstrip('#')
    out = []
    for i in (0, 2, 4):
        c = int(h[i:i + 2], 16) / 255.0
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return out


MATS = {}


def mat(hexstr):
    if hexstr not in MATS:
        m = bpy.data.materials.new(hexstr)
        m.diffuse_color = (*lin(hexstr), 1.0)
        m.roughness = 1.0
        MATS[hexstr] = m
    return MATS[hexstr]


INK, RED, YEL, SKY, GRN, GRN_D, GRASS, WHT, FACE, GREY, TRUNK = (
    '#1b2233', '#ef4a2f', '#ffc93c', '#4fb8e6', '#2f9e6a', '#23805a', '#58b97a', '#f7ecd4', '#111827', '#2a3246', '#5a4636')


def box(sx, sy, sz):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=(sx, sy, sz), verts=bm.verts)
    return bm


def cone(segs, r1, r2, d):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segs, radius1=r1, radius2=r2, depth=d)
    return bm


def ring(segs, rin, rout, depth, a0=0.0, a1=2 * math.pi):
    """绕 Y 轴的环（矩形截面），正面朝 -Y。"""
    bm = bmesh.new()
    rows = []
    for i in range(segs + 1):
        a = a0 + (a1 - a0) * i / segs
        c, s = math.cos(a), math.sin(a)
        rows.append([bm.verts.new((rin * c, -depth / 2, rin * s)), bm.verts.new((rout * c, -depth / 2, rout * s)),
                     bm.verts.new((rout * c, depth / 2, rout * s)), bm.verts.new((rin * c, depth / 2, rin * s))])
    for i in range(segs):
        p, q = rows[i], rows[i + 1]
        for k in range(4):
            bm.faces.new((p[k], p[(k + 1) % 4], q[(k + 1) % 4], q[k]))
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def add(col, name, bm, color, loc=(0, 0, 0), rot=(0, 0, 0)):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat(color))
    o = bpy.data.objects.new(name, me)
    o.location, o.rotation_euler = loc, rot
    col.objects.link(o)
    return o


def text(col, name, body, size, color, loc):
    cu = bpy.data.curves.new(name, 'FONT')
    cu.body, cu.size, cu.extrude = body, size, 0.006
    cu.align_x, cu.align_y = 'CENTER', 'CENTER'
    cu.materials.append(mat(color))
    o = bpy.data.objects.new(name, cu)
    o.location, o.rotation_euler = loc, (math.pi / 2, 0, 0)
    col.objects.link(o)
    return o


def collection(name):
    c = bpy.data.collections.new(name)
    scene.collection.children.link(c)
    return c


# ---------- 1. 松树（森林区段的环境物） ----------
tree = collection('tree')
add(tree, 'ground', cone(8, 2.2, 2.2, 0.08), GRASS, (0, 0, -0.04))
add(tree, 'trunk', cone(6, 0.26, 0.2, 1.0), TRUNK, (0, 0, 0.5))
for i, (r, d, z) in enumerate([(1.5, 1.8, 1.7), (1.15, 1.6, 2.65), (0.75, 1.5, 3.55)]):
    add(tree, f'leaf{i}', cone(7, r, 0.0, d), GRN_D if i % 2 == 0 else GRN, (0.04 * (i - 1), 0.03 * i, z), (0.03 * (i - 1), 0.04, 0.5 * i))

# ---------- 2. 转速表（大圆指针表，档位在下方缺口） ----------
tach = collection('tach')
add(tach, 'bezel', ring(48, 1.0, 1.14, 0.22), INK, (0, -0.06, 0))
add(tach, 'bezel_lip', ring(48, 1.14, 1.19, 0.08), GREY, (0, -0.02, 0))
add(tach, 'accent', ring(48, 0.955, 1.0, 0.05), RED, (0, -0.115, 0))
add(tach, 'face', cone(48, 1.0, 1.0, 0.04), FACE, (0, -0.08, 0), (math.pi / 2, 0, 0))
A0, SWEEP = math.radians(225), math.radians(270)
ang = lambda rpm: A0 - SWEEP * rpm / 9.0
for i in range(46):
    rpm = i / 5.0
    major = i % 5 == 0
    a = ang(rpm)
    R, ln, w = (0.84, 0.16, 0.036) if major else (0.875, 0.09, 0.016)
    add(tach, f'tick{i}', box(w, 0.02, ln), RED if rpm >= 8 else WHT, (R * math.cos(a), -0.11, R * math.sin(a)), (0, math.pi / 2 - a, 0))
add(tach, 'redzone', ring(10, 0.925, 0.955, 0.02, ang(9), ang(8)), RED, (0, -0.11, 0))
for n in range(10):
    a = ang(n)
    text(tach, f'num{n}', str(n), 0.17, RED if n >= 8 else WHT, (0.63 * math.cos(a), -0.106, 0.63 * math.sin(a)))
text(tach, 'unit', 'x1000 r/min', 0.065, WHT, (0, -0.106, 0.3))
add(tach, 'gear_frame', box(0.44, 0.03, 0.4), YEL, (0, -0.105, -0.66))
add(tach, 'gear_bg', box(0.38, 0.03, 0.34), INK, (0, -0.112, -0.66))
text(tach, 'gear', '5', 0.34, YEL, (0, -0.128, -0.66))
a = ang(7.4)
add(tach, 'needle', box(0.045, 0.02, 0.86), RED, (0.34 * math.cos(a), -0.145, 0.34 * math.sin(a)), (0, math.pi / 2 - a, 0))
add(tach, 'hub', cone(16, 0.13, 0.11, 0.06), INK, (0, -0.15, 0), (math.pi / 2, 0, 0))
add(tach, 'hub_cap', cone(16, 0.06, 0.05, 0.03), RED, (0, -0.185, 0), (math.pi / 2, 0, 0))

# ---------- 3. 戴手套的右手握着一段方向盘（最难的有机形体） ----------
hand = collection('hand')
add(hand, 'rim', cone(10, 0.017, 0.017, 0.32), GREY, (0, 0, 0), (0, math.pi / 2, 0))
add(hand, 'paddle', box(0.05, 0.006, 0.075), RED, (0.03, 0.05, -0.012), (0.15, 0, 0))
RR = 0.034
for fi, x in enumerate([-0.033, -0.011, 0.011, 0.033]):
    s = [0.92, 1.0, 0.97, 0.82][fi]
    for si, th in enumerate([145, 90, 35]):
        t = math.radians(th + (1 - s) * 60 * si)
        w = [0.0195, 0.0185, 0.0165][si]
        add(hand, f'f{fi}_{si}', box(w, 0.031 * s, 0.017 - 0.001 * si), RED, (x, RR * math.cos(t), RR * math.sin(t)), (t + math.pi / 2, 0, 0))
        if si == 0:
            add(hand, f'pad{fi}', box(0.014, 0.017, 0.006), INK, (x, (RR + 0.011) * math.cos(t), (RR + 0.011) * math.sin(t)), (t + math.pi / 2, 0, 0))
add(hand, 'palm', box(0.092, 0.03, 0.085), RED, (0.0, -0.042, -0.032), (-0.35, 0, 0))
add(hand, 'palm_pad', box(0.06, 0.008, 0.045), INK, (0.004, -0.06, -0.03), (-0.35, 0, 0))
for si, th in enumerate([200, 250, 300]):
    t = math.radians(th)
    add(hand, f'thumb{si}', box(0.022 - 0.002 * si, 0.031, 0.019 - 0.002 * si), RED, (-0.056 + 0.006 * si, RR * math.cos(t), RR * math.sin(t)), (t + math.pi / 2, 0, 0.25))
add(hand, 'cuff', box(0.082, 0.042, 0.03), INK, (0.004, -0.066, -0.088), (-0.5, 0, 0))
add(hand, 'sleeve', box(0.07, 0.04, 0.14), GREY, (0.008, -0.108, -0.165), (-0.5, 0, 0))

# ---------- 渲染设置：纯色材质 + 切面明暗 + 深蓝黑描边 ----------
world = bpy.data.worlds.new('w')
world.color = lin(WHT)
scene.world = world
scene.render.engine = 'BLENDER_WORKBENCH'
scene.view_settings.view_transform = 'Standard'
sh = scene.display.shading
sh.light, sh.color_type = 'STUDIO', 'MATERIAL'
sh.show_object_outline, sh.object_outline_color = True, lin(INK)
sh.show_shadows, sh.shadow_intensity = True, 0.3
sh.show_cavity, sh.cavity_type = True, 'WORLD'
sh.show_specular_highlight = False
scene.render.image_settings.file_format = 'PNG'
cam = bpy.data.objects.new('cam', bpy.data.cameras.new('cam'))
cam.data.clip_start = 0.01
scene.collection.objects.link(cam)
scene.camera = cam
MODELS = {'tree': (tree, (7.5, -7.5, 4.2), (0, 0, 1.95), 50), 'tach': (tach, (0.7, -4.6, 0.35), (0, 0, -0.05), 50), 'hand': (hand, (-0.12, -0.42, 0.2), (0.0, -0.03, -0.06), 50)}


def load_px(path):
    im = bpy.data.images.load(path)
    w, h = im.size
    a = np.empty(w * h * 4, dtype=np.float32)
    im.pixels.foreach_get(a)
    bpy.data.images.remove(im)
    return a.reshape(h, w, 4)


def save_px(arr, path):
    h, w, _ = arr.shape
    im = bpy.data.images.new('out', w, h, alpha=True)
    im.pixels.foreach_set(np.ascontiguousarray(arr, dtype=np.float32).ravel())
    im.filepath_raw, im.file_format = path, 'PNG'
    im.save()
    bpy.data.images.remove(im)


def render(name, size, aa, path):
    col, loc, tgt, lens = MODELS[name]
    for c, *_ in MODELS.values():
        for o in c.objects:
            o.hide_render = c is not col
    cam.location, cam.data.lens = loc, lens
    cam.rotation_euler = (Vector(tgt) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
    scene.render.resolution_x = scene.render.resolution_y = size
    scene.display.render_aa = aa
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


top, bottom = [], []
for name in MODELS:
    p1, p2, tmp = (os.path.join(OUT, f'{name}_{k}.png') for k in ('shaded', 'pixel', 'tmp'))
    render(name, 640, '8', p1)
    render(name, 320, 'OFF', tmp)          # 低分辨率、关闭抗锯齿
    small = load_px(tmp)
    save_px(np.repeat(np.repeat(small, 2, axis=0), 2, axis=1), p2)   # 最近邻放大 2 倍
    os.remove(tmp)
    top.append(load_px(p1))
    bottom.append(load_px(p2))
# 图像数组第 0 行是底部，所以像素化的一排放在前面（显示在下方）
save_px(np.concatenate([np.concatenate(bottom, axis=1), np.concatenate(top, axis=1)], axis=0), os.path.join(OUT, 'trial_sheet.png'))

for name, (col, *_) in MODELS.items():
    try:
        for o in scene.objects:
            o.select_set(o.name in col.objects)
        bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, f'{name}.glb'), use_selection=True)
    except Exception as e:
        print('GLB export failed for', name, e)
print('TRIAL DONE')
