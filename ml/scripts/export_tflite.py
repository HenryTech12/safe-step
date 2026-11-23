"""Export a YOLOv8 model to the TFLite file the app loads (app/assets/models/yolov8n.tflite).

Two routes:

1) From Ultralytics weights (use this for the fine-tuned SafeStep model):
       pip install ultralytics
       python ml/scripts/export_tflite.py --weights ml/weights/safestep_yolov8n.pt
   -> uses `YOLO(weights).export(format="tflite", imgsz=640, half=True)`

2) From an ONNX file (how the placeholder was made, offline, from BlindSpot's stock COCO
   yolov8n.onnx):
       pip install "tensorflow==2.19.*" "onnx==1.17.*" onnx2tf onnx_graphsurgeon sng4onnx tf_keras
       python ml/scripts/export_tflite.py --onnx yolov8n.onnx
   onnx2tf wants a calibration .npy it normally downloads; we write a random one so it works
   offline (it is only used for its accuracy self-check, not for float16 conversion).

The app expects: input [1, 640, 640, 3] float32 in 0..1 (NHWC), output [1, 4 + C, 8400] with
boxes as cx, cy, w, h in input pixels. Also update app/assets/models/labels.txt.
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "app" / "assets" / "models" / "yolov8n.tflite"


def from_weights(weights: Path) -> Path:
    from ultralytics import YOLO

    return Path(YOLO(str(weights)).export(format="tflite", imgsz=640, half=True))


def from_onnx(onnx: Path) -> Path:
    import numpy as np

    work = onnx.parent
    np.save(work / "calibration_image_sample_data_20x128x128x3_float32.npy",
            np.random.rand(20, 128, 128, 3).astype("float32"))
    subprocess.run(["onnx2tf", "-i", str(onnx), "-o", "tflite_out", "-osd", "-n"], cwd=work, check=True)
    return work / "tflite_out" / f"{onnx.stem}_float16.tflite"


def main() -> None:
    ap = argparse.ArgumentParser()
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--weights", type=Path)
    g.add_argument("--onnx", type=Path)
    args = ap.parse_args()
    src = from_weights(args.weights) if args.weights else from_onnx(args.onnx.resolve())
    shutil.copy(src, OUT)
    print(f"wrote {OUT} ({OUT.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    main()
