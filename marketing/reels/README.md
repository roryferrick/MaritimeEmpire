# Reels

The scripts are in [SCRIPTS.md](SCRIPTS.md). The finished videos are the `.mp4` files in this folder: 1080×1920, 30 fps, H.264, a silent audio track, ready for Instagram Reels.

## How they're made

1. **[tools/reels/reels.json](../../tools/reels/reels.json)** lists each reel's beats: the times, the pop-up caption and the shots that fill each beat. Each shot has a length in seconds. A shot can also have `"speed": 2` (played at double speed) or `"from": 1.5` (start 1.5 s into the recording).
2. **[tools/reels/reel_director.gd](../../tools/reels/reel_director.gd)** plays the game off screen and records every shot as 1080×1920 frames into `build/shots/<shot>/`. It also writes the caption cards and the end card into `build/<reel>/cards/`. It works on a copy of a save in slot 8 and deletes the copy afterwards. It also backs up the player stats, settings and cosmetics files, and puts them back when it finishes.
3. **[tools/reels/build_reels.py](../../tools/reels/build_reels.py)** cuts the shots together, adds the captions and the end card, and writes the MP4s here.

Record (a reel, several, or only some shots):

```bash
Godot --path . --fixed-fps 30 --audio-driver Dummy --windowed --resolution 360x640 --position 3540,400 res://tools/reels/reel_director.tscn -- --reel A,B,1 [--shot name,name] [--missing]
```

Keep the small Godot window visible while it records (it's parked on the right of the second screen). Minimized, Godot stops drawing and the recording stalls. `--missing` records only the shots that don't have enough frames yet.

Build the videos:

```bash
python tools/reels/build_reels.py A B 1 2
```

## Timing to your voiceover

Captions change on the beat times in `reels.json`. After you record a voiceover, give me the audio file or the times you hit each line. I'll move the beats and shot lengths to match. Then I'll re-record any shot that needs to run longer and rebuild the reel with your audio on it. Shots are recorded 0.4 s longer than they're used, so small shifts don't need a re-record.
