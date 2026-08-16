APP      := EVE-APM Mac
# The release build signs differently, so it is kept apart: overwriting the
# local app would change its signature and cost it the privacy grants.
BUNDLE_DIR ?= build
BUNDLE   := $(BUNDLE_DIR)/$(APP).app
BINARY   := EVEAPMMac
CONFIG   ?= release
ARCHS    ?=
VERSION  := $(shell /usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
ARCHIVE  := build/EVE-APM-Mac-$(VERSION)-universal.zip
# A stable signature keeps the Screen Recording and Accessibility grants across
# rebuilds; scripts/dev-identity.sh creates one. Falls back to ad-hoc signing.
IDENTITY ?= $(shell security find-certificate -c "EVE-APM Mac Dev" >/dev/null 2>&1 && echo "EVE-APM Mac Dev" || echo -)

.PHONY: all build bundle icon run test release clean

all: bundle

build:
	swift build -c $(CONFIG) $(ARCHS)

bundle: build
	rm -rf "$(BUNDLE)"
	mkdir -p "$(BUNDLE)/Contents/MacOS" "$(BUNDLE)/Contents/Resources"
	cp "$(shell swift build -c $(CONFIG) $(ARCHS) --show-bin-path)/$(BINARY)" "$(BUNDLE)/Contents/MacOS/$(BINARY)"
	cp Resources/Info.plist "$(BUNDLE)/Contents/Info.plist"
	cp Resources/AppIcon.icns "$(BUNDLE)/Contents/Resources/AppIcon.icns"
	cp Resources/MenuBarIcon.png "$(BUNDLE)/Contents/Resources/MenuBarIcon.png"
	printf 'APPL????' > "$(BUNDLE)/Contents/PkgInfo"
	xattr -cr "$(BUNDLE)"
	codesign --force --sign "$(IDENTITY)" --identifier com.github.labaznov.eveapmmac "$(BUNDLE)"
	@echo "built $(BUNDLE)"

run: bundle
	open "$(BUNDLE)"

# Regenerates the icon from Resources/bee.png; only needed when the artwork
# changes, the result is committed.
icon:
	swift scripts/make-icon.swift
	swift scripts/make-menubar-icon.swift

test:
	swift test

# What is published: both architectures, and an ad-hoc signature so the download
# carries nobody's private key. Anyone can reproduce it from this checkout.
release:
	$(MAKE) bundle CONFIG=release ARCHS="--arch arm64 --arch x86_64" IDENTITY=- BUNDLE_DIR=build/release
	rm -f "$(ARCHIVE)"
	ditto -c -k --keepParent "build/release/$(APP).app" "$(ARCHIVE)"
	@echo "packaged $(ARCHIVE)"

clean:
	rm -rf build .build
