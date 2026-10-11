"""Configuración común de los tests.

Los tests crean una ``Gtk.Window`` real, por lo que necesitan un display.
En CI/local se ejecutan bajo ``xvfb-run``; si no hay display, se saltan.
"""

import gi
import pytest

gi.require_version("Gtk", "3.0")
from gi.repository import Gtk  # noqa: E402


@pytest.fixture(scope="session", autouse=True)
def _require_display():
    """Salta toda la suite si no hay un display utilizable."""
    try:
        ok = Gtk.init_check([])[0]
    except Exception:
        ok = False
    if not ok:
        pytest.skip("No hay display (ejecuta los tests con 'xvfb-run -a pytest')")
