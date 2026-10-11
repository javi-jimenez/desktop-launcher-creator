"""Tests para Desktop Launcher Creator.

Incluye un test *funcional*: simula la pulsación de una aplicación en la lista
y comprueba que se crea el fichero ``.desktop`` en la carpeta de destino (con
permisos de ejecución), que es justo lo que hace el botón "Crear Lanzador".
"""

import os
import stat

import gi
import pytest

gi.require_version("Gtk", "3.0")
from gi.repository import Gtk  # noqa: E402

from desktop_launcher_creator.main import LauncherCopier  # noqa: E402


DESKTOP_OK = """[Desktop Entry]
Type=Application
Name=Editor de prueba
Comment=Aplicación de prueba
Exec=/usr/bin/true
Icon=application-x-executable
Categories=Utility;
"""

DESKTOP_HIDDEN = """[Desktop Entry]
Type=Application
Name=Oculta
NoDisplay=true
Exec=/usr/bin/true
"""


class FakeMessageDialog:
    """Sustituto de ``Gtk.MessageDialog`` para que ``run()`` no bloquee."""

    def __init__(self, *args, **kwargs):
        self.secondary_text = None

    def format_secondary_text(self, text):
        self.secondary_text = text

    def run(self):
        return Gtk.ResponseType.OK

    def destroy(self):
        pass


@pytest.fixture
def launcher(tmp_path, monkeypatch):
    """Una instancia de la ventana con HOME aislado y sin diálogo modal."""
    monkeypatch.setenv("HOME", str(tmp_path))
    monkeypatch.setattr(Gtk, "MessageDialog", FakeMessageDialog)
    app = LauncherCopier()
    app.show_all()  # realiza los widgets (como hace main())
    _pump()
    yield app
    app.destroy()


@pytest.fixture
def source_dir(tmp_path):
    """Directorio con dos .desktop: uno visible y otro NoDisplay."""
    d = tmp_path / "origen"
    d.mkdir()
    (d / "editor.desktop").write_text(DESKTOP_OK)
    (d / "oculta.desktop").write_text(DESKTOP_HIDDEN)
    return d


def _load_only(launcher, source_dir, monkeypatch):
    """Hace que la app lea solo el directorio de prueba."""
    monkeypatch.setattr(launcher, "_desktop_sources", lambda: [str(source_dir)])
    launcher.load_applications()


def _pump():
    """Procesa los eventos GTK pendientes (sin entrar en el bucle principal)."""
    while Gtk.events_pending():
        Gtk.main_iteration_do(False)


def test_detecta_aplicaciones_y_omite_nodisplay(launcher, source_dir, monkeypatch):
    _load_only(launcher, source_dir, monkeypatch)
    nombres = [row[1] for row in launcher.store]
    assert "Editor de prueba" in nombres
    assert "Oculta" not in nombres  # NoDisplay se ignora
    assert len(launcher.store) == 1


def test_busqueda_filtra_la_lista(launcher, source_dir, monkeypatch):
    _load_only(launcher, source_dir, monkeypatch)
    launcher.search_entry.set_text("editor")
    launcher.on_search_changed(launcher.search_entry)
    visibles = [row[1] for row in launcher.filter]
    assert visibles == ["Editor de prueba"]

    launcher.search_entry.set_text("no-existe")
    launcher.on_search_changed(launcher.search_entry)
    assert [row[1] for row in launcher.filter] == []


def test_seleccionar_fuentes(launcher):
    launcher.chk_deb.set_active(False)
    launcher.chk_snap.set_active(False)
    launcher.chk_flatpak.set_active(False)
    assert launcher._desktop_sources() == []


def test_click_crea_el_lanzador(launcher, source_dir, tmp_path, monkeypatch):
    """Funcional: seleccionar una app y pulsar 'Crear Lanzador' crea el .desktop."""
    _load_only(launcher, source_dir, monkeypatch)

    # Equivale a hacer clic en la primera aplicación de la lista
    launcher.treeview.get_selection().select_path(Gtk.TreePath.new_first())

    destino = tmp_path / "lanzadores"
    launcher.btn_folder.set_filename(str(destino))

    # "Pulsar" el botón Crear Lanzador
    launcher.on_create_clicked(launcher.btn_create)

    creado = destino / "editor.desktop"
    assert creado.exists(), "No se creó el lanzador .desktop"

    contenido = creado.read_text()
    assert "[Desktop Entry]" in contenido
    assert "Name=Editor de prueba" in contenido

    # El lanzador debe ser ejecutable (u+x, g+x, o+x)
    modo = os.stat(creado).st_mode
    assert modo & stat.S_IXUSR
    assert modo & stat.S_IXGRP
    assert modo & stat.S_IXOTH


def test_click_en_cuadricula_crea_el_lanzador(launcher, source_dir, tmp_path, monkeypatch):
    """Funcional: lo mismo pero desde la vista de cuadrícula (IconView)."""
    _load_only(launcher, source_dir, monkeypatch)

    launcher.stack.set_visible_child_name("grid")
    _pump()
    launcher.iconview.select_path(Gtk.TreePath.new_first())
    _pump()

    destino = tmp_path / "lanzadores-grid"
    launcher.btn_folder.set_filename(str(destino))

    launcher.on_create_clicked(launcher.btn_create)

    assert (destino / "editor.desktop").exists()
