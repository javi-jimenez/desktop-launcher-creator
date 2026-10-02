#!/usr/bin/env python3
# Desktop Launcher Creator
# Copyright (C) 2026 Javier Jiménez
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.
import os
import shutil
import stat
import sys
import gi

gi.require_version('Gtk', '3.0')
from gi.repository import Gtk, GdkPixbuf, Gio, GLib

ICON_SIZE = 32


class LauncherCopier(Gtk.Window):
    def __init__(self):
        super().__init__(title="Crear Lanzador de Aplicación")
        self.set_default_size(600, 650)
        self.set_position(Gtk.WindowPosition.CENTER)
        self.set_border_width(12)

        # Ruta destino por defecto (~/Aplicaciones)
        self.target_dir = os.path.expanduser("~/Aplicaciones")
        os.makedirs(self.target_dir, exist_ok=True)

        # Icono por defecto para aplicaciones sin icono
        self.icon_theme = Gtk.IconTheme.get_default()
        self.default_pixbuf = self._load_theme_icon("application-x-executable")

        # Layout principal
        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        self.add(vbox)

        # Barra de búsqueda
        self.search_entry = Gtk.SearchEntry()
        self.search_entry.set_placeholder_text("Buscar aplicación (ej. Firefox, VS Code)...")
        self.search_entry.connect("search-changed", self.on_search_changed)
        vbox.pack_start(self.search_entry, False, False, 0)

        # Barra de controles: checkbox de iconos + selector lista/cuadrícula
        controls = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)

        self.chk_icons = Gtk.CheckButton(label="Cargar iconos")
        self.chk_icons.set_active(True)
        self.chk_icons.connect("toggled", self.on_icons_toggled)
        controls.pack_start(self.chk_icons, False, False, 0)

        # Espaciador para empujar el selector a la derecha
        controls.pack_start(Gtk.Box(), True, True, 0)

        # Selector de vista: lista o cuadrícula (iconos preexistentes del tema)
        self.btn_view_list = Gtk.RadioButton()
        self.btn_view_list.set_tooltip_text("Ver como lista (líneas horizontales)")
        self.btn_view_list.set_relief(Gtk.ReliefStyle.NONE)
        self._set_button_icon(self.btn_view_list, "view-list-symbolic")
        self.btn_view_list.connect("toggled", self.on_view_toggled)

        self.btn_view_grid = Gtk.RadioButton.new_from_widget(self.btn_view_list)
        self.btn_view_grid.set_tooltip_text("Ver como cuadrícula (cajita con 4 cuadrados)")
        self.btn_view_grid.set_relief(Gtk.ReliefStyle.NONE)
        self._set_button_icon(self.btn_view_grid, "view-grid-symbolic")
        self.btn_view_grid.connect("toggled", self.on_view_toggled)

        controls.pack_start(self.btn_view_list, False, False, 0)
        controls.pack_start(self.btn_view_grid, False, False, 0)
        vbox.pack_start(controls, False, False, 0)

        # Barra de fuentes: Debian, Snap y Flatpak (todas activadas por defecto)
        sources = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        label_src = Gtk.Label(label="Fuentes:")
        label_src.set_xalign(0)
        sources.pack_start(label_src, False, False, 0)

        self.chk_deb = Gtk.CheckButton(label="Debian")
        self.chk_deb.set_active(True)
        self.chk_deb.connect("toggled", self.on_sources_toggled)
        sources.pack_start(self.chk_deb, False, False, 0)

        self.chk_snap = Gtk.CheckButton(label="Snap")
        self.chk_snap.set_active(True)
        self.chk_snap.connect("toggled", self.on_sources_toggled)
        sources.pack_start(self.chk_snap, False, False, 0)

        self.chk_flatpak = Gtk.CheckButton(label="Flatpak")
        self.chk_flatpak.set_active(True)
        self.chk_flatpak.connect("toggled", self.on_sources_toggled)
        sources.pack_start(self.chk_flatpak, False, False, 0)

        vbox.pack_start(sources, False, False, 0)

        # Modelo y Filtro
        self.store = Gtk.ListStore(GdkPixbuf.Pixbuf, str, str)
        self.filter = self.store.filter_new()
        self.filter.set_visible_func(self.filter_func)

        # --- Vista de LISTA (TreeView) ---
        self.treeview = Gtk.TreeView(model=self.filter)
        self.treeview.set_headers_visible(False)
        self.treeview.connect("row-activated", self.on_row_activated)

        # Columna: Icono + Nombre
        column = Gtk.TreeViewColumn("Aplicación")
        self.renderer_pixbuf = Gtk.CellRendererPixbuf()
        renderer_text = Gtk.CellRendererText()

        column.pack_start(self.renderer_pixbuf, False)
        column.pack_start(renderer_text, True)
        column.add_attribute(self.renderer_pixbuf, "pixbuf", 0)
        column.add_attribute(renderer_text, "text", 1)
        self.treeview.append_column(column)

        # --- Vista de CUADRÍCULA (IconView) ---
        self.iconview = Gtk.IconView(model=self.filter)
        self.iconview.set_pixbuf_column(0)
        self.iconview.set_text_column(1)
        self.iconview.set_item_width(96)
        self.iconview.set_columns(-1)
        self.iconview.set_spacing(6)
        self.iconview.set_margin(6)
        self.iconview.connect("item-activated", self.on_item_activated)

        # Contenedor con Stack para alternar entre lista y cuadrícula
        self.stack = Gtk.Stack()
        self.stack.set_transition_type(Gtk.StackTransitionType.CROSSFADE)
        self.stack.add_named(self.treeview, "list")
        self.stack.add_named(self.iconview, "grid")

        # Area de Scroll
        scrolled = Gtk.ScrolledWindow()
        scrolled.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scrolled.add(self.stack)
        vbox.pack_start(scrolled, True, True, 0)

        # Selector de Carpeta Destino
        hbox_folder = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        label_dir = Gtk.Label(label="Guardar en:")
        self.btn_folder = Gtk.FileChooserButton(
            title="Seleccionar carpeta de destino",
            action=Gtk.FileChooserAction.SELECT_FOLDER
        )
        self.btn_folder.set_filename(self.target_dir)
        hbox_folder.pack_start(label_dir, False, False, 0)
        hbox_folder.pack_start(self.btn_folder, True, True, 0)
        vbox.pack_start(hbox_folder, False, False, 0)

        # Botón Acción
        self.btn_create = Gtk.Button(label="Crear Lanzador")
        self.btn_create.get_style_context().add_class("suggested-action")
        self.btn_create.connect("clicked", self.on_create_clicked)
        vbox.pack_start(self.btn_create, False, False, 0)

        # Estado inicial: vista de lista
        self.stack.set_visible_child_name("list")

        self.load_applications()

    # ------------------------------------------------------------------
    # Utilidades de iconos
    # ------------------------------------------------------------------
    def _set_button_icon(self, button, icon_name):
        """Coloca un icono del tema dentro de un botón (si existe)."""
        if self.icon_theme.has_icon(icon_name):
            image = Gtk.Image.new_from_icon_name(icon_name, Gtk.IconSize.BUTTON)
        else:
            # Alternativas por si el tema no trae el icono simbólico
            fallback = "view-list" if "list" in icon_name else "view-grid"
            image = Gtk.Image.new_from_icon_name(fallback, Gtk.IconSize.BUTTON)
        button.add(image)
        button.show_all()

    def _load_theme_icon(self, icon_name, size=ICON_SIZE):
        """Carga un icono del tema devolviendo None si falla."""
        try:
            return self.icon_theme.load_icon(icon_name, size, Gtk.IconLookupFlags.FORCE_SIZE)
        except Exception:
            return None

    def get_icon_pixbuf(self, icon_name):
        try:
            if os.path.isabs(icon_name) and os.path.exists(icon_name):
                return GdkPixbuf.Pixbuf.new_from_file_at_size(icon_name, ICON_SIZE, ICON_SIZE)
            pixbuf = self._load_theme_icon(icon_name)
            return pixbuf if pixbuf is not None else self.default_pixbuf
        except Exception:
            return self.default_pixbuf

    # ------------------------------------------------------------------
    # Filtro / búsqueda
    # ------------------------------------------------------------------
    def filter_func(self, model, iter, data):
        query = self.search_entry.get_text().lower()
        if not query:
            return True
        name = model[iter][1].lower()
        return query in name

    def on_search_changed(self, widget):
        self.filter.refilter()

    # ------------------------------------------------------------------
    # Carga de aplicaciones
    # ------------------------------------------------------------------
    def _desktop_sources(self):
        """Devuelve la lista de (carpeta, checkbox) según las fuentes activas.

        Debian: rutas estándar del sistema y del usuario.
        Snap:   exportaciones de snapd.
        Flatpak: exportaciones de flatpak (sistema y usuario).
        """
        sources = []

        if self.chk_deb.get_active():
            sources += [
                os.path.expanduser("~/.local/share/applications"),
                "/usr/share/applications",
                "/usr/local/share/applications",
            ]

        if self.chk_snap.get_active():
            sources += [
                "/var/lib/snapd/desktop/applications",
                os.path.expanduser("~/.local/share/snapd/desktop/applications"),
            ]

        if self.chk_flatpak.get_active():
            sources += [
                "/var/lib/flatpak/exports/share/applications",
                os.path.expanduser("~/.local/share/flatpak/exports/share/applications"),
            ]

        return sources

    def _keyfile_keys(self, keyfile, group):
        """Devuelve las claves de un grupo como lista de strings.

        En PyGObject, GLib.KeyFile.get_keys() devuelve una tupla
        (lista_de_claves, longitud); hay que tomar el primer elemento.
        """
        try:
            keys = keyfile.get_keys(group)
        except Exception:
            return []
        if isinstance(keys, tuple):
            keys = keys[0]
        return list(keys) if keys else []

    def load_applications(self):
        # Limpiamos el modelo antes de recargar (por cambios de fuente)
        self.store.clear()

        seen_files = set()

        for d in self._desktop_sources():
            if not os.path.exists(d):
                continue
            for f in sorted(os.listdir(d)):
                if not f.endswith(".desktop") or f in seen_files:
                    continue
                path = os.path.join(d, f)
                seen_files.add(f)

                keyfile = GLib.KeyFile()
                try:
                    keyfile.load_from_file(path, GLib.KeyFileFlags.NONE)
                    keys = self._keyfile_keys(keyfile, "Desktop Entry")
                    if "NoDisplay" in keys and keyfile.get_boolean("Desktop Entry", "NoDisplay"):
                        continue

                    name = keyfile.get_locale_string("Desktop Entry", "Name")
                    icon_name = keyfile.get_string("Desktop Entry", "Icon") if "Icon" in keys else "application-x-executable"
                except Exception:
                    continue

                pixbuf = self.get_icon_pixbuf(icon_name) if self.chk_icons.get_active() else None
                self.store.append([pixbuf, name, path])

    def refresh_icons(self):
        """Recarga (o quita) los iconos de todas las filas según el checkbox."""
        load_icons = self.chk_icons.get_active()
        for row in self.store:
            if not load_icons:
                row[0] = None
            else:
                # Reconstruimos el icono a partir del archivo .desktop
                path = row[2]
                icon_name = self._icon_name_from_desktop(path)
                row[0] = self.get_icon_pixbuf(icon_name)

    def _icon_name_from_desktop(self, path):
        keyfile = GLib.KeyFile()
        try:
            keyfile.load_from_file(path, GLib.KeyFileFlags.NONE)
            keys = self._keyfile_keys(keyfile, "Desktop Entry")
            if "Icon" in keys:
                return keyfile.get_string("Desktop Entry", "Icon")
        except Exception:
            pass
        return "application-x-executable"

    # ------------------------------------------------------------------
    # Callbacks de la interfaz
    # ------------------------------------------------------------------
    def on_icons_toggled(self, widget):
        self.refresh_icons()

    def on_sources_toggled(self, widget):
        self.load_applications()

    def on_view_toggled(self, widget):
        if not widget.get_active():
            return
        if widget is self.btn_view_grid:
            self.stack.set_visible_child_name("grid")
        else:
            self.stack.set_visible_child_name("list")

    # ------------------------------------------------------------------
    # Acciones
    # ------------------------------------------------------------------
    def copy_desktop_file(self, source_path):
        target_folder = self.btn_folder.get_filename() or self.target_dir
        os.makedirs(target_folder, exist_ok=True)
        
        filename = os.path.basename(source_path)
        dest_path = os.path.join(target_folder, filename)

        shutil.copy2(source_path, dest_path)

        # Otorgar permisos de ejecución
        st = os.stat(dest_path)
        os.chmod(dest_path, st.st_mode | stat.S_IEXEC | stat.S_IXGRP | stat.S_IXOTH)

        dialog = Gtk.MessageDialog(
            transient_for=self,
            flags=0,
            message_type=Gtk.MessageType.INFO,
            buttons=Gtk.ButtonsType.OK,
            text="¡Lanzador Creado!"
        )
        dialog.format_secondary_text(f"Se ha guardado en:\n{dest_path}")
        dialog.run()
        dialog.destroy()

    def _selected_path(self):
        """Devuelve la ruta .desktop seleccionada en la vista activa."""
        if self.stack.get_visible_child_name() == "grid":
            paths = self.iconview.get_selected_items()
            if not paths:
                return None
            iter = self.filter.get_iter(paths[0])
            return self.filter[iter][2]
        else:
            model, iter = self.treeview.get_selection().get_selected()
            if iter:
                return model[iter][2]
            return None

    def on_create_clicked(self, widget):
        source_path = self._selected_path()
        if source_path:
            self.copy_desktop_file(source_path)

    def on_row_activated(self, treeview, path, column):
        iter = self.filter.get_iter(path)
        source_path = self.filter[iter][2]
        self.copy_desktop_file(source_path)

    def on_item_activated(self, iconview, path):
        iter = self.filter.get_iter(path)
        source_path = self.filter[iter][2]
        self.copy_desktop_file(source_path)


def main():
    app = LauncherCopier()
    app.connect("destroy", Gtk.main_quit)
    app.show_all()
    Gtk.main()


if __name__ == "__main__":
    main()

