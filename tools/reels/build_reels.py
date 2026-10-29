# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
"""Puts the reels together from the footage tools/reels/reel_director.gd recorded.

    python tools/reels/build_reels.py A [B 1 2 ...]

For each reel in tools/reels/reels.json: the beats' shots cut in order (each
shot's frames from its "from" second, every "speed"th frame, for "len"
seconds), each beat's caption popping in near the top, the end card over the
last beat, and the reel's "audio" (the voiceover) and/or "music" ({"file",
"gain_db"}: faded out at the end, held under the voiceover), else a silent
track (Instagram is happier with one). Writes
marketing/reels/<file>.mp4 (1080x1920, 30 fps, H.264).
"""
import json
import os
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
BUILD = os.path.join(ROOT, "marketing", "reels", "build")
OUT = os.path.join(ROOT, "marketing", "reels")
FPS = 30
CAPTION_Y = 250  # Top of the caption card's 360 px box (clear of Instagram's top bar).
POP = 0.18  # Seconds a caption takes to pop in.


def ffmpeg() -> str:
    found = shutil.which("ffmpeg")
    if found:
        return found
    base = os.path.expandvars(r"%LOCALAPPDATA%\Microsoft\WinGet\Packages")
    for name in os.listdir(base):
        if name.startswith("Gyan.FFmpeg"):
            for sub in os.listdir(os.path.join(base, name)):
                exe = os.path.join(base, name, sub, "bin", "ffmpeg.exe")
                if os.path.exists(exe):
                    return exe
    sys.exit("ffmpeg not found")


def build(reel_id: str, reel: dict) -> None:
    frames_dir = os.path.join(BUILD, reel_id, "frames")
    shutil.rmtree(frames_dir, ignore_errors=True)
    os.makedirs(frames_dir)
    n = 0
    for beat in reel["beats"]:
        for shot in beat["shots"]:
            src = os.path.join(BUILD, "shots", shot["shot"])
            have = sorted(f for f in os.listdir(src) if f.endswith(".jpg"))
            if not have:
                sys.exit("no frames for " + shot["shot"])
            speed = float(shot.get("speed", 1.0))
            start = round(float(shot.get("from", 0.0)) * FPS)
            for i in range(round(float(shot["len"]) * FPS)):
                pick = min(start + round(i * speed), len(have) - 1)
                os.link(os.path.join(src, have[pick]), os.path.join(frames_dir, "%05d.jpg" % n))
                n += 1
    length = n / FPS
    cards = os.path.join(BUILD, reel_id, "cards")
    # (-nostdin: run after Godot in one shell, ffmpeg otherwise hung waiting on the console.)
    args = [ffmpeg(), "-y", "-nostdin", "-loglevel", "error", "-framerate", str(FPS), "-i", os.path.join(frames_dir, "%05d.jpg")]
    filters = []
    last = "0:v"
    inputs = 1
    for i, beat in enumerate(reel["beats"]):
        t0, t1 = float(beat["t"][0]), float(beat["t"][1])
        if beat.get("caption"):
            args += ["-loop", "1", "-framerate", str(FPS), "-i", os.path.join(cards, "caption_%02d.png" % i)]
            # Fades in and rises 40 px as it pops, fades out just before the beat ends.
            filters.append(
                f"[{inputs}:v]format=rgba,fade=t=in:st={t0}:d={POP}:alpha=1,fade=t=out:st={t1 - 0.12}:d=0.12:alpha=1[c{i}]")
            filters.append(
                f"[{last}][c{i}]overlay=x=0:y='{CAPTION_Y}+40*max(0\\,1-(t-{t0})/{POP})':enable='between(t,{t0},{t1})'[v{i}]")
            last = f"v{i}"
            inputs += 1
        if beat.get("introcard"):  # (A feature reel's opening slide, fading out as the beat ends.)
            args += ["-loop", "1", "-framerate", str(FPS), "-i", os.path.join(cards, "introcard.png")]
            filters.append(f"[{inputs}:v]format=rgba,fade=t=out:st={t1 - 0.4}:d=0.4:alpha=1[s{i}]")
            filters.append(f"[{last}][s{i}]overlay=0:0:enable='between(t,{t0},{t1})'[v{i}]")
            last = f"v{i}"
            inputs += 1
        if beat.get("endcard"):
            args += ["-loop", "1", "-framerate", str(FPS), "-i", os.path.join(cards, "endcard.png")]
            filters.append(f"[{inputs}:v]format=rgba,fade=t=in:st={t0}:d=0.4:alpha=1[e{i}]")
            filters.append(f"[{last}][e{i}]overlay=0:0:enable='gte(t,{t0})'[v{i}]")
            last = f"v{i}"
            inputs += 1
    filters.append(f"[{last}]format=yuv420p[out]")
    # The sound: the voiceover ("audio", a path under marketing/reels) and/or the
    # music ("music": {"file", "gain_db"}, a path under marketing/reels, faded out
    # over the last two seconds and held under the voiceover), else silence.
    voice = reel.get("audio")
    music = reel.get("music")
    sound_map = None
    if music:  # (Mixed in the filter graph; without music the one track maps straight through.)
        sounds = []
        if voice:
            args += ["-i", os.path.join(OUT, voice)]
            sounds.append(f"[{inputs}:a]aformat=sample_rates=48000:channel_layouts=stereo[vo]")
            inputs += 1
        args += ["-i", os.path.join(OUT, music["file"])]
        gain = float(music.get("gain_db", -14.0 if voice else -6.0))
        sounds.append(f"[{inputs}:a]aformat=sample_rates=48000:channel_layouts=stereo,volume={gain}dB,afade=t=in:st=0:d=0.8,afade=t=out:st={length - 2.0:.3f}:d=2.0[mu]")
        inputs += 1
        cut = f"atrim=duration={length:.3f}[aout]"
        sounds.append(f"[vo][mu]amix=inputs=2:duration=first:normalize=0,{cut}" if voice else f"[mu]{cut}")
        filters += sounds
        sound_map = "[aout]"
    elif voice:
        args += ["-i", os.path.join(OUT, voice)]
        sound_map = f"{inputs}:a"
    else:
        args += ["-f", "lavfi", "-i", "anullsrc=r=48000:cl=stereo"]
        sound_map = f"{inputs}:a"
    args += ["-filter_complex", ";".join(filters), "-map", "[out]", "-map", sound_map,
             "-t", f"{length:.3f}", "-r", str(FPS), "-c:v", "libx264", "-preset", "slow", "-crf", "17",
             "-profile:v", "high", "-c:a", "aac", "-b:a", "128k", "-movflags", "+faststart",
             os.path.join(OUT, reel["file"] + ".mp4")]
    # (ffmpeg has hung for good now and then on this machine, mid-encode and silent:
    # a bounded run, killed and tried once more.)
    for attempt in range(3):
        try:
            # (Nothing to the console: a console write can block a process on Windows.)
            subprocess.run(args, check=True, timeout=180, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            break
        except subprocess.TimeoutExpired:
            print("ffmpeg hung on", reel["file"], "- trying again" if attempt < 2 else "- giving up", flush=True)
            if attempt == 2:
                raise
    print("wrote", reel["file"] + ".mp4", f"({length:.1f} s)")


def main() -> None:
    plan = json.load(open(os.path.join(ROOT, "tools", "reels", "reels.json"), encoding="utf-8"))
    for reel_id in sys.argv[1:] or [k for k in plan if k != "P"]:
        build(reel_id, plan[reel_id])


if __name__ == "__main__":
    main()
