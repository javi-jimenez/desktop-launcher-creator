.PHONY: help deps install run test lint format clean build \
        flatpak-build flatpak-install snap-build release \
        drone-cli-install drone-local

# Default target
help:
	@echo "Available targets:"
	@echo "  deps              Install Debian system dependencies (requires sudo)"
	@echo "  install           Install Python dependencies with Poetry"
	@echo "  run               Run the application"
	@echo "  test              Run the test suite"
	@echo "  lint              Run static checks"
	@echo "  format            Format the code"
	@echo "  build             Build the Python package"
	@echo "  flatpak-build     Build the Flatpak bundle"
	@echo "  flatpak-install   Build and install the Flatpak for the current user"
	@echo "  snap-build        Build the Snap package"
	@echo "  drone-cli-install Install the Drone CLI into ~/.local/bin"
	@echo "  drone-local       Run the Drone pipeline locally with 'drone exec'"
	@echo "  release           Tag a release (VERSION=x.y.z) and push it"
	@echo "  clean             Remove build artifacts and caches"

# Debian system dependencies
deps:
	sudo apt update
	sudo apt install -y libgirepository-2.0-dev libgirepository1.0-dev gir1.2-gtk-3.0 libcairo2-dev

# Python dependencies
install:
	poetry install

# Run the application
run:
	poetry run python -m desktop_launcher_creator.main

# Run tests
test:
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

# Build the Flatpak bundle
flatpak-build:
	flatpak-builder --force-clean --repo=repo build-dir \
		packaging/flatpak/io.github.javi_jimenez.DesktopLauncherCreator.yml
	flatpak build-bundle repo desktop-launcher-creator.flatpak \
		io.github.javi_jimenez.DesktopLauncherCreator

# Build and install the Flatpak for the current user
flatpak-install:
	flatpak-builder --user --install --force-clean build-dir \
		packaging/flatpak/io.github.javi_jimenez.DesktopLauncherCreator.yml

# Build the Snap package
snap-build:
	cd packaging/snap && snapcraft

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
drone-local: drone-cli-install
	$(DRONE_BIN) exec --pipeline default --exclude release --branch main

# Tag a release and push it (usage: make release VERSION=0.2.0)
release:
	@test -n "$(VERSION)" || (echo "Uso: make release VERSION=x.y.z" && exit 1)
	git tag -a v$(VERSION) -m "Release v$(VERSION)"
	git push origin v$(VERSION)

# Clean build artifacts and caches
clean:
	rm -rf dist build repo build-dir desktop-launcher-creator.flatpak
	find . -type d -name "__pycache__" -exec rm -rf {} +
	find . -type d -name "*.egg-info" -exec rm -rf {} +
	find . -type d -name ".pytest_cache" -exec rm -rf {} +
