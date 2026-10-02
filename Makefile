.PHONY: help deps install run test lint format clean build \
        flatpak-build flatpak-install snap-build release

# Default target
help:
	@echo "Available targets:"
	@echo "  deps             Install Debian system dependencies (requires sudo)"
	@echo "  install          Install Python dependencies with Poetry"
	@echo "  run              Run the application"
	@echo "  test             Run the test suite"
	@echo "  lint             Run static checks"
	@echo "  format           Format the code"
	@echo "  build            Build the Python package"
	@echo "  flatpak-build    Build the Flatpak bundle"
	@echo "  flatpak-install  Build and install the Flatpak for the current user"
	@echo "  snap-build       Build the Snap package"
	@echo "  release          Tag a release (VERSION=x.y.z) and push it"
	@echo "  clean            Remove build artifacts and caches"

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
