#!/usr/bin/env python3
"""Record the demo tapes with VHS, then add smooth zooms with ffmpeg.

Usage, from the repo root:  python3 docs/demo/render.py [--no-record] [name ...]

Each docs/demo/<name>.tape records docs/demo/build/<name>.mp4. If
docs/demo/<name>.zoom.json exists, its keyframes drive the camera:

    {"keys": [[seconds, zoom, center_x, center_y], ...]}

zoom 1 shows the whole terminal; center_x/center_y are fractions of the frame.
Between keyframes the camera eases in and out. The result is docs/demo/<name>.gif.
"""
import json
import pathlib
import subprocess
import sys

DEMO = pathlib.Path(__file__).resolve().parent
OUT_W, OUT_H, FPS = 960, 540, 12


def eased(keys, index):
    """ffmpeg expression for one keyframe column, eased between keyframes."""
    expr = str(keys[-1][index])
    for (t0, *a), (t1, *b) in reversed(list(zip(keys, keys[1:]))):
        v0, v1 = a[index - 1], b[index - 1]
        p = f"clip((it-{t0})/{t1 - t0},0,1)"
        step = f"({v0}+({v1 - v0})*{p}*{p}*(3-2*{p}))"
        expr = f"if(lt(it,{t1}),{step},{expr})"
    return f"if(lt(it,{keys[0][0]}),{keys[0][index]},{expr})"


def camera(name):
    path = DEMO / f"{name}.zoom.json"
    keys = json.loads(path.read_text())["keys"] if path.exists() else [[0, 1, 0.5, 0.5]]
    z, cx, cy = eased(keys, 1), eased(keys, 2), eased(keys, 3)
    x = f"clip(({cx})*iw-iw/zoom/2,0,iw-iw/zoom)"
    y = f"clip(({cy})*ih-ih/zoom/2,0,ih-ih/zoom)"
    # Upscale first so the moving crop lands on whole pixels without jitter.
    return (f"scale=iw*2:ih*2:flags=bicubic,"
            f"zoompan=z='{z}':x='{x}':y='{y}':d=1:s={OUT_W}x{OUT_H}:fps=30,fps={FPS}")


def render(name, record=True):
    root = DEMO.parent.parent
    if record:
        subprocess.run(["vhs", f"docs/demo/{name}.tape"], cwd=root, check=True)
    ffmpeg = ["ffmpeg", "-loglevel", "error", "-y"]
    zoomed, palette = f"docs/demo/build/{name}-zoomed.mkv", f"docs/demo/build/{name}-palette.png"
    # Three passes keep memory low: zoom, build a palette, then encode the GIF.
    subprocess.run(ffmpeg + ["-i", f"docs/demo/build/{name}.mp4", "-vf", camera(name),
                             "-c:v", "ffv1", zoomed], cwd=root, check=True)
    subprocess.run(ffmpeg + ["-i", zoomed, "-vf", "palettegen=max_colors=96:stats_mode=diff", palette],
                   cwd=root, check=True)
    subprocess.run(ffmpeg + ["-i", zoomed, "-i", palette, "-lavfi",
                             "paletteuse=dither=none:diff_mode=rectangle",
                             f"docs/demo/{name}.gif"], cwd=root, check=True)
    print(f"docs/demo/{name}.gif")


if __name__ == "__main__":
    args = sys.argv[1:]
    record = "--no-record" not in args  # reuse build/<name>.mp4 to tune zooms
    names = [a for a in args if a != "--no-record"] or sorted(p.stem for p in DEMO.glob("*.tape"))
    for demo in names:
        render(demo, record)
