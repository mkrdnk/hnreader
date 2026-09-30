PREFIX ?= $(HOME)/.local
export CRYSTAL_CACHE_DIR ?= /tmp/hnreader-crystal-cache
export LIBRARY_PATH := $(CURDIR)/.build/lib$(if $(LIBRARY_PATH),:$(LIBRARY_PATH))
CRYSTAL_SOURCES := src spec

.PHONY: setup bindings build run test format check install link-libraries
link-libraries:
	@./scripts/link-libraries.sh

setup: link-libraries
	shards install
	$(MAKE) bindings

bindings: link-libraries
	./bin/gi-crystal

build: link-libraries
	shards build hnreader

run: build
	./bin/hnreader

test:
	crystal spec

format:
	crystal tool format $(CRYSTAL_SOURCES)

check:
	crystal tool format --check $(CRYSTAL_SOURCES)
	crystal spec

install: build
	install -Dm755 bin/hnreader $(DESTDIR)$(PREFIX)/bin/hnreader
	install -Dm644 data/hnreader.makridenko.com.desktop $(DESTDIR)$(PREFIX)/share/applications/hnreader.makridenko.com.desktop
	install -Dm644 data/hnreader.makridenko.com.svg $(DESTDIR)$(PREFIX)/share/icons/hicolor/scalable/apps/hnreader.makridenko.com.svg
