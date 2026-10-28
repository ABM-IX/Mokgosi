import os

import pytest

os.environ.setdefault("ED25519_PRIVATE_KEY_SEED", "11" * 32)
os.environ.setdefault("DEVICE_API_KEYS", "test-device-key")
os.environ.setdefault("DEMO_MODE", "true")


@pytest.fixture(autouse=True)
def _fresh_rate_limits():
    import main
    main._rate_windows.clear()
    yield
