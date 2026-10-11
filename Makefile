.PHONY: help deps deps-packaging install run test lint format clean build \
	packages flatpak-build flatpak-install flatpak-bundle snap-build snap-lint deb-build appimage-build \
        release release-local release-push \
        drone-cli-install drone-local

VERSION ?= $(shell poetry version --short 2>/dev/null || echo "0.0.0")
APP_ID  := io.github.javi_jimenez.DesktopLauncherCreator
FLATHUB := https://flathub.org/repo/flathub.flatpakrepo

# Default target
help:
	@echo "Available targets:"
	@echo "  deps              Install Debian system dependencies (requires sudo)"
	@echo "  deps-packaging    Install flatpak-builder and snapcraft (requires sudo)"
	@echo "  install           Install Python dependencies with Poetry"
	@echo "  run               Run the application"
	@echo "  test              Run the test suite"
	@echo "  lint              Run static checks"
	@echo "  format            Format the code"
	@echo "  build             Build the Python package (wheel + sdist)"
	@echo "  packages          Build Snap AND Flatpak into dist/ (one command)"
	@echo "  flatpak-build     Build the Flatpak (into build-dir)"
	@echo "  flatpak-bundle    Build and export the .flatpak bundle"
	@echo "  flatpak-install   Build and install the Flatpak for the current user"
	@echo "  snap-build        Build the Snap package"
	@echo "  snap-lint         Lint the snapcraft.yaml"
	@echo "  deb-build         Build the Debian package into dist/"
	@echo "  appimage-build    Build the AppImage (requires appimage-builder)"
	@echo "  release-local     Build all artifacts into dist/ (no push)"
	@echo "  release-push      Tag v\$$(VERSION) and push to gitea"
	@echo "  release           release-local + release-push"
	@echo "  drone-cli-install Install the Drone CLI into ~/.local/bin"
	@echo "  drone-local       Run the Drone pipeline locally with 'drone exec'"
	@echo "  clean             Remove build artifacts and caches"

# Debian system dependencies (build + runtime para la app)
deps:
	sudo apt update
	sudo apt install -y libgirepository-2.0-dev libgirepository1.0-dev gir1.2-gtk-3.0 libcairo2-dev

# Herramientas de empaquetado (Flatpak + Snap)
deps-packaging:
	sudo apt update
	sudo apt install -y flatpak flatpak-builder squashfs-tools
	@if ! command -v snapcraft >/dev/null 2>&1; then \
		echo "==> Instalando snapcraft vía snap..."; \
		sudo snap install snapcraft --classic; \
	fi
	@echo "==> Añadiendo el remoto Flathub (usuario)..."
	-flatpak remote-add --if-not-exists --user flathub $(FLATHUB)

# Python dependencies
install:
	poetry install

# Run the application
run:
	poetry run python -m desktop_launcher_creator.main

# Run tests
# pytest NO va en las deps de Poetry (resolver el lock con pygobject se cuelga);
# se instala en el venv de Poetry si falta.
test:
	@poetry run python -c "import pytest" 2>/dev/null || poetry run python -m pip install -q pytest
	poetry run pytest

# Static checks
lint:
	poetry run python -m compileall desktop_launcher_creator

# Format the code
format:
	poetry run python -m black desktop_launcher_creator tests

# Build the package
build:
	poetry build

# Construye AMBOS paquetes (Snap y Flatpak) en dist/ con un solo comando.
# Instala previamente las herramientas si faltan (requiere sudo).
packages: deps-packaging
	@mkdir -p dist
	@echo "==> Construyendo Snap..."
	cd packaging/snap && snapcraft --destructive-mode
	cp packaging/snap/*.snap dist/
	@echo "==> Construyendo Flatpak..."
	flatpak install --user -y flathub org.gnome.Platform//47 org.gnome.Sdk//47 || true
	flatpak-builder --force-clean --repo=repo build-dir \
		packaging/flatpak/$(APP_ID).yml
	flatpak build-bundle repo dist/desktop-launcher-creator-$(VERSION).flatpak $(APP_ID)
	@echo "==> Artefactos en dist/:"
	@ls -lh dist/

# Build the Flatpak (into build-dir, no bundle)
flatpak-build:
	flatpak-builder --force-clean --repo=repo build-dir \
		packaging/flatpak/$(APP_ID).yml

# Build and export the .flatpak bundle into dist/
flatpak-bundle: build
	@mkdir -p dist
	flatpak-builder --force-clean --repo=repo build-dir \
		packaging/flatpak/$(APP_ID).yml
	flatpak build-bundle repo dist/desktop-launcher-creator-$(VERSION).flatpak $(APP_ID)

# Build and install the Flatpak for the current user
flatpak-install:
	flatpak-builder --user --install --force-clean build-dir \
		packaging/flatpak/$(APP_ID).yml

# Build the Snap package
snap-build:
	cd packaging/snap && snapcraft

# Lint the snapcraft.yaml
snap-lint:
	cd packaging/snap && snapcraft lint

# Build the Debian package into dist/
deb-build:
	bash packaging/deb/build.sh $(VERSION)

# Build the AppImage (the official appimage-builder container works locally too)
appimage-build:
	PROJECT_DIR=$(CURDIR) VERSION=$(VERSION) appimage-builder --recipe packaging/appimage/AppImageBuilder.yml --skip-test
	mv desktop-launcher-creator-$(VERSION)-x86_64.AppImage dist/

# Build every release artifact into dist/ (no push)
release-local: build
	@mkdir -p dist
	@echo "==> Construyendo paquete Debian..."
	@$(MAKE) deb-build
	@echo "==> Artefactos Python en dist/"
	@ls -lh dist/
	@if command -v appimage-builder >/dev/null 2>&1; then \
		echo "==> Construyendo AppImage..."; \
		$(MAKE) appimage-build; \
	else \
		echo "!! appimage-builder no instalado; se omite el AppImage"; \
	fi
	@if command -v flatpak-builder >/dev/null 2>&1; then \
		echo "==> Construyendo Flatpak..."; \
		$(MAKE) flatpak-bundle; \
	else \
		echo "!! flatpak-builder no instalado; se omite el Flatpak"; \
	fi
	@if command -v snapcraft >/dev/null 2>&1; then \
		echo "==> Construyendo Snap..."; \
		cd packaging/snap && snapcraft --destructive-mode; \
		cp packaging/snap/*.snap dist/ 2>/dev/null || true; \
	else \
		echo "!! snapcraft no instalado; se omite el Snap"; \
	fi
	@echo "==> Contenido final de dist/"; ls -lh dist/

# Tag the current VERSION and push it to gitea
release-push:
	@test -n "$(VERSION)" || (echo "Uso: make release VERSION=x.y.z" && exit 1)
	@git diff --quiet || (echo "Hay cambios sin commitear; haz commit antes de release." && exit 1)
	git tag -a v$(VERSION) -m "Release v$(VERSION)"
	git push gitea v$(VERSION)

# Full release: build artifacts locally, then tag and push
release: release-local release-push

# Install the Drone CLI into ~/.local/bin (no sudo needed)
DRONE_VERSION ?= 1.9.0
DRONE_BIN := $(HOME)/.local/bin/drone
drone-cli-install:
	@mkdir -p $(HOME)/.local/bin
	@if [ -x "$(DRONE_BIN)" ]; then \
		echo "Drone CLI ya instalada: $$($(DRONE_BIN) --version)"; \
	else \
		echo "Instalando Drone CLI $(DRONE_VERSION)..."; \
		curl -sSL -o /tmp/drone.tar.gz \
			https://github.com/harness/drone-cli/releases/download/v$(DRONE_VERSION)/drone_linux_amd64.tar.gz; \
		tar -xzf /tmp/drone.tar.gz -C /tmp drone; \
		mv /tmp/drone $(DRONE_BIN); \
		chmod +x $(DRONE_BIN); \
		rm -f /tmp/drone.tar.gz; \
		echo "Instalada: $$($(DRONE_BIN) --version)"; \
	fi

# Run the Drone pipeline locally (no server needed).
# Uses the default 'bridge' Docker network on purpose: custom subnets break DNS.
# Excludes the 'release' step, which requires the Drone server.
# --event push is required so steps gated with `when: event: [tag, push]`
# (the 'build' step) are actually executed by `drone exec`.
drone-local: drone-cli-install
	$(DRONE_BIN) exec --pipeline default --exclude release \
		--branch main --event push

# Clean build artifacts and caches
clean:
	rm -rf dist build repo build-dir desktop-launcher-creator.flatpak
	rm -f packaging/snap/*.snap
	find . -type d -name "__pycache__" -exec rm -rf {} +
	find . -type d -name "*.egg-info" -exec rm -rf {} +
	find . -type d -name ".pytest_cache" -exec rm -rf {} +
