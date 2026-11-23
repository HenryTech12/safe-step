"""Guards for the security requirements: no secrets or signing in the app, no stray platforms."""

import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / "app"


def test_no_livekit_secret_or_jwt_signing_in_app():
    for f in list((APP / "lib").rglob("*.dart")) + [APP / "pubspec.yaml"]:
        text = f.read_text(encoding="utf-8")
        assert "API_SECRET" not in text.upper().replace("LIVEKIT_API_SECRET lives only", ""), f
        assert "dart_jsonwebtoken" not in text, f
        assert not re.search(r"\bJWT\(", text), f


def test_android_only():
    for platform in ["ios", "macos", "windows", "linux", "web"]:
        assert not (APP / platform).exists(), platform


def _tracked() -> list[str]:
    out = subprocess.run(["git", "ls-files"], cwd=ROOT, capture_output=True, text=True, check=True)
    return out.stdout.splitlines()


def test_no_committed_secrets_files():
    for path in _tracked():
        name = Path(path).name
        assert name != ".backboard.json", path
        assert not (name == ".env" or (name.startswith(".env.") and name != ".env.example")), path


def test_no_server_side_obstacle_detection():
    assert not (ROOT / "agent" / "safestep_agent" / "obstacle.py").exists()
