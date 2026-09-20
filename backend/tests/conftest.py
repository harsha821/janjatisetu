"""Pytest configuration and test environment initialization."""
import os
import sys
import tempfile
from pathlib import Path

# Ensure backend root is in sys.path
backend_dir = str(Path(__file__).resolve().parent.parent)
if backend_dir not in sys.path:
    sys.path.insert(0, backend_dir)

_tmp = tempfile.mkdtemp()
os.environ["DATABASE_URL"] = f"sqlite:///{_tmp}/test.db"
os.environ["UPLOAD_DIR"] = f"{_tmp}/uploads"
os.environ["SEED_DEMO"] = "true"
os.environ["SECRET_KEY"] = "test-secret-key-at-least-32-bytes-long-for-hmac-sha256"
