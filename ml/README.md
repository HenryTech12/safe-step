# SafeStep hazard model

Phase 3 work. The app will run YOLOv8n as TFLite on the phone, offline.

- Placeholder: stock COCO `yolov8n.tflite` (exported with `ultralytics`, not committed; see `scripts/`).
- Target: fine-tuned model with the classes in `classes.yaml`.
- Large weights live in `ml/weights/` (gitignored).
