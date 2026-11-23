"""Turn a recorded street video into demo-mode frames for the app.

    pip install opencv-python-headless
    python ml/scripts/video_to_frames.py walk.mp4 --out demo_frames --fps 5
    adb push demo_frames/. /sdcard/Android/data/ng.safestep.app/files/demo/

Record with the phone held at chest height, back camera forward, in portrait. Frames are
resized to at most 640 px on the long side (the detector input size).
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path


def main() -> None:
    import cv2

    ap = argparse.ArgumentParser()
    ap.add_argument("video", type=Path)
    ap.add_argument("--out", type=Path, default=Path("demo_frames"))
    ap.add_argument("--fps", type=float, default=5.0)
    ap.add_argument("--max-side", type=int, default=640)
    args = ap.parse_args()

    cap = cv2.VideoCapture(str(args.video))
    if not cap.isOpened():
        raise SystemExit(f"cannot open {args.video}")
    src_fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    step = max(1, round(src_fps / args.fps))
    args.out.mkdir(parents=True, exist_ok=True)

    frames: list[str] = []
    i = 0
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        if i % step == 0:
            h, w = frame.shape[:2]
            scale = args.max_side / max(h, w)
            if scale < 1:
                frame = cv2.resize(frame, (round(w * scale), round(h * scale)), interpolation=cv2.INTER_AREA)
            name = f"{len(frames) + 1:06d}.jpg"
            cv2.imwrite(str(args.out / name), frame, [cv2.IMWRITE_JPEG_QUALITY, 85])
            frames.append(name)
        i += 1
    cap.release()
    (args.out / "manifest.json").write_text(json.dumps({"fps": src_fps / step, "frames": frames}))
    print(f"wrote {len(frames)} frames at {src_fps / step:.1f} fps to {args.out}")


if __name__ == "__main__":
    main()
