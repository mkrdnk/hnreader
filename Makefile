PREFIX ?= $(HOME)/.local
export CRYSTAL_CACHE_DIR ?= /tmp/hnreader-crystal-cache
export LIBRARY_PATH := $(CURDIR)/.build/lib$(if $(LIBRARY_PATH),:$(LIBRARY_PATH))
CRYSTAL_SOURCES := src spec scripts/gui_smoke.cr

.PHONY: setup bindings build run test format check smoke install clean link-libraries resources
link-libraries:
	@./scripts/link-libraries.sh

setup: link-libraries resources
	shards install
	$(MAKE) bindings

bindings: link-libraries
	./bin/gi-crystal

resources:
	mkdir -p .build
	glib-compile-resources --sourcedir=data --target=.build/hnreader.gresource data/hnreader.gresource.xml

build: link-libraries resources
	shards build hnreader
	cd bin && sha256sum hnreader > hnreader.sha256
	bash scripts/package-release.sh

clean:
	rm -rf dist/

run: build
	./bin/hnreader

test:
	crystal spec

format:
	crystal tool format $(CRYSTAL_SOURCES)

check:
	crystal tool format --check $(CRYSTAL_SOURCES)
	crystal spec

smoke: link-libraries resources
	./scripts/gui-smoke.sh

install: build
	install -Dm755 bin/hnreader $(DESTDIR)$(PREFIX)/bin/hnreader
	install -Dm644 data/hnreader.makridenko.com.desktop $(DESTDIR)$(PREFIX)/share/applications/hnreader.makridenko.com.desktop
	install -Dm644 data/hnreader.makridenko.com.svg $(DESTDIR)$(PREFIX)/share/icons/hicolor/scalable/apps/hnreader.makridenko.com.svg
	gtk-update-icon-cache --force --ignore-theme-index "$(DESTDIR)$(PREFIX)/share/icons/hicolor"
