# SafeStep hazard model

Phase 3 work. The app will run YOLOv8n as TFLite on the phone, offline.

- Placeholder (committed): `app/assets/models/yolov8n.tflite`, stock COCO YOLOv8n converted from BlindSpot's `yolov8n.onnx` with onnx2tf (float16, 6.4 MB). Checked against ONNX Runtime on the same input: max score difference 0.0004, box difference under 2 px at 640. See `scripts/export_tflite.py`.
- COCO to SafeStep class mapping for the placeholder is in `app/lib/hazard/hazard_classes.dart`. It cannot see gutters, manholes, potholes or kerbs; only the fine-tuned model can.
- Target: fine-tuned model with the classes in `classes.yaml`.
- Large weights live in `ml/weights/` (gitignored).
