"""Paper plane flight path for the loading screen.

Screen space: ortho camera looking down -Z, 16 x 9 units visible (x in [-8, 8],
y in [-4.5, 4.5]); +Z points at the viewer. Plane mesh: nose +Y, span X, top +Z.

Three clips, all at 30 fps:
  intro  (45 f)  - swoops in from off-screen left, hands over to the loop
  loop   (120 f) - horizontal figure-8 with two barrel rolls; seamless
  finale (69 f)  - sharp left-up exit, off-screen beat, straight dive down the
                   middle that rushes into the camera
"""
import math
from mathutils import Vector, Matrix, Quaternion

FPS = 30
INTRO, LOOP = 45, 120
F1, PAUSE, DESC, RUSH = 21, 9, 24, 15
FINALE = F1 + PAUSE + DESC + RUSH

AX, AY, Y0 = 5.6, 1.7, 0.2          # figure-8 half-width, half-height, centre
LOOP_T = LOOP / FPS
UP_REF = Vector((0.0, 1.0, 0.8)).normalized()   # 3/4 view: wing tops lean at us


def smooth(x):
    x = min(max(x, 0.0), 1.0)
    return x * x * (3 - 2 * x)


def hermite(p0, p1, v0, v1, dur, s):
    """Cubic Hermite position + velocity (units/s) at s in [0,1]."""
    m0, m1 = v0 * dur, v1 * dur
    s2, s3 = s * s, s * s * s
    p = (2*s3 - 3*s2 + 1) * p0 + (s3 - 2*s2 + s) * m0 + (-2*s3 + 3*s2) * p1 + (s3 - s2) * m1
    dp = (6*s2 - 6*s) * p0 + (3*s2 - 4*s + 1) * m0 + (-6*s2 + 6*s) * p1 + (3*s2 - 2*s) * m1
    return p, dp / dur


def loop_state(t):
    """t in [0,1) of the loop. Returns pos, vel, acc (2D, per second)."""
    w = 2 * math.pi / LOOP_T
    th = 2 * math.pi * t
    pos = Vector((AX * math.sin(th), AY * math.sin(2 * th) + Y0))
    vel = Vector((AX * w * math.cos(th), 2 * AY * w * math.cos(2 * th)))
    acc = Vector((-AX * w * w * math.sin(th), -4 * AY * w * w * math.sin(2 * th)))
    return pos, vel, acc


LOOP_P0, LOOP_V0, _ = loop_state(0.0)


def roll_window(t, start, width):
    return 2 * math.pi * smooth((t - start) / width)


def bank_from(vel, acc, k=0.55, lim=1.0):
    sp = vel.length
    if sp < 1e-4:
        return 0.0
    kappa = (vel.x * acc.y - vel.y * acc.x) / sp ** 3
    return max(-lim, min(lim, -k * kappa * 4.0))


def orient(fwd, roll):
    f = fwd.normalized()
    r = f.cross(UP_REF).normalized()
    u = r.cross(f)
    q = Matrix((r, f, u)).transposed().to_quaternion()
    return q @ Quaternion((0, 1, 0), roll)          # roll about local nose axis


def frame_state(clip, i):
    """Returns (x, y, scale, quaternion) for frame i of clip."""
    if clip == "intro":
        s = i / INTRO
        p0, v0 = Vector((-10.5, -1.6)), Vector((10.0, 4.5))
        pos, vel = hermite(p0, LOOP_P0, v0, LOOP_V0, INTRO / FPS, s)
        _, vel2 = hermite(p0, LOOP_P0, v0, LOOP_V0, INTRO / FPS, min(s + 0.01, 1))
        acc = (vel2 - vel) / (0.01 * INTRO / FPS)
        wobble = 0.25 * math.sin(s * math.pi * 2.0) * (1 - s)
        fwd = Vector((vel.x, vel.y, 0.0))
        return pos.x, pos.y, 1.0, orient(fwd, bank_from(vel, acc) + wobble)

    if clip == "loop":
        t = i / LOOP
        pos, vel, acc = loop_state(t)
        th = 2 * math.pi * t
        # at the figure-8 ends the nose swings toward the viewer: reads as turning around
        tz = 0.55 * vel.length * math.sin(th) ** 4
        fwd = Vector((vel.x, vel.y, tz))
        roll = bank_from(vel, acc) + roll_window(t, 0.05, 0.16) + roll_window(t, 0.55, 0.16)
        return pos.x, pos.y, 1.0, orient(fwd, roll)

    # ---------------- finale ----------------
    if i < F1:                                   # sharp turn left-up, off the top
        s = i / F1
        p1, v1 = Vector((-3.6, 6.4)), Vector((-6.0, 15.0))
        pos, vel = hermite(LOOP_P0, p1, LOOP_V0, v1, F1 / FPS, s)
        _, vel2 = hermite(LOOP_P0, p1, LOOP_V0, v1, F1 / FPS, min(s + 0.01, 1))
        acc = (vel2 - vel) / (0.01 * F1 / FPS)
        roll = bank_from(vel, acc, k=0.9, lim=1.3) - 2 * math.pi * smooth((s - 0.25) / 0.6)
        return pos.x, pos.y, 1.0, orient(Vector((vel.x, vel.y, 0.0)), roll)
    i -= F1
    if i < PAUSE:                                # empty sky beat (plane parked off-screen)
        return 0.0, 9.0, 0.7, orient(Vector((0, -1, 0.35)), 0.0)
    i -= PAUSE
    if i < DESC:                                 # straight down the middle, closing in
        s = i / DESC
        e = 1 - (1 - s) ** 2                     # ease-out: fast entry, settles centre
        y = 6.0 + (0.4 - 6.0) * e
        sc = 0.7 + 0.7 * s * s
        fwd = Vector((0, -1, 0.35)).lerp(Vector((0, -0.45, 1)), smooth(s))
        return 0.0, y, sc, orient(fwd, 0.15 * math.sin(s * math.pi * 2))
    i -= DESC
    s = i / (RUSH - 1)                           # rush through the camera
    y = 0.4 - 1.0 * s * s
    sc = 1.4 * math.exp(math.log(18 / 1.4) * s ** 1.6)
    fwd = Vector((0, -0.45, 1)).lerp(Vector((0, -0.12, 1)), s)
    return 0.0, y, sc, orient(fwd, 0.0)


def timeline(loops=1):
    """[(clip, i)] for intro, `loops` x loop, finale."""
    seq = [("intro", i) for i in range(INTRO)]
    for _ in range(loops):
        seq += [("loop", i) for i in range(LOOP)]
    seq += [("finale", i) for i in range(FINALE)]
    return seq


# Background clouds: (shape index, x, y, scale, drift speed left in units/s).
# Wrap horizontally over [-CLOUD_WRAP, CLOUD_WRAP].
CLOUD_WRAP = 11.5
CLOUDS = [
    (2, -5.0, 2.9, 1.00, 0.35),
    (0, 3.6, 3.4, 0.80, 0.30),
    (1, 6.8, -0.7, 0.70, 0.22),
    (3, -2.4, -3.2, 0.90, 0.40),
    (1, -7.6, 0.8, 0.55, 0.18),
    (0, 1.4, -1.9, 0.60, 0.25),
]


def cloud_x(x0, speed, t):
    span = 2 * CLOUD_WRAP
    return ((x0 - speed * t + CLOUD_WRAP) % span) - CLOUD_WRAP
