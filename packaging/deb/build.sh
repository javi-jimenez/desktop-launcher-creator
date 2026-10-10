#!/usr/bin/env bash
set -euo pipefail

version="${1:?Usage: build.sh VERSION}"
package_root="$(mktemp -d)"
trap 'rm -rf "$package_root"' EXIT

chmod 0755 "$package_root"
install -d -m0755 "$package_root/DEBIAN"
install -d -m0755 "$package_root/usr/lib/python3/dist-packages"
cp -r desktop_launcher_creator "$package_root/usr/lib/python3/dist-packages/"
find "$package_root/usr/lib/python3/dist-packages" -type d -name __pycache__ -prune -exec rm -rf {} +
chmod -R go-w "$package_root/usr/lib/python3/dist-packages"

install -d "$package_root/usr/bin"
cat > "$package_root/usr/bin/desktop-launcher-creator" <<'EOF'
#!/usr/bin/python3
from desktop_launcher_creator.main import main

main()
EOF
chmod 0755 "$package_root/usr/bin/desktop-launcher-creator"

install -Dm644 packaging/common/io.github.javi_jimenez.DesktopLauncherCreator.desktop \
  "$package_root/usr/share/applications/io.github.javi_jimenez.DesktopLauncherCreator.desktop"
install -Dm644 packaging/common/io.github.javi_jimenez.DesktopLauncherCreator.metainfo.xml \
  "$package_root/usr/share/metainfo/io.github.javi_jimenez.DesktopLauncherCreator.metainfo.xml"
install -Dm644 packaging/common/io.github.javi_jimenez.DesktopLauncherCreator.svg \
  "$package_root/usr/share/icons/hicolor/scalable/apps/io.github.javi_jimenez.DesktopLauncherCreator.svg"
install -Dm644 LICENSE "$package_root/usr/share/doc/desktop-launcher-creator/copyright"

cat > "$package_root/DEBIAN/control" <<EOF
Package: desktop-launcher-creator
Version: $version
Section: utils
Priority: optional
Architecture: all
Depends: python3 (>= 3.12), python3-gi, python3-cairo, gir1.2-gtk-3.0, libgtk-3-0 | libgtk-3-0t64
Maintainer: Javier Jimenez <javi-jimenez@users.noreply.github.com>
Description: Create desktop launchers from installed applications
 Desktop Launcher Creator detects installed Debian, Snap and Flatpak
 applications and creates desktop launcher files for them.
EOF

mkdir -p dist
dpkg-deb --root-owner-group --build "$package_root" \
  "dist/desktop-launcher-creator_${version}_all.deb"