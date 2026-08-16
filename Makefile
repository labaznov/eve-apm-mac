APP      := EVE-APM Mac
BUNDLE   := build/$(APP).app
BINARY   := EVEAPMMac
CONFIG   ?= release
# A stable signature keeps the Screen Recording and Accessibility grants across
# rebuilds; scripts/dev-identity.sh creates one. Falls back to ad-hoc signing.
IDENTITY ?= $(shell security find-certificate -c "EVE-APM Mac Dev" >/dev/null 2>&1 && echo "EVE-APM Mac Dev" || echo -)

.PHONY: all build bundle run test clean

all: bundle

build:
	swift build -c $(CONFIG)

bundle: build
	rm -rf "$(BUNDLE)"
	mkdir -p "$(BUNDLE)/Contents/MacOS" "$(BUNDLE)/Contents/Resources"
	cp "$(shell swift build -c $(CONFIG) --show-bin-path)/$(BINARY)" "$(BUNDLE)/Contents/MacOS/$(BINARY)"
	cp Resources/Info.plist "$(BUNDLE)/Contents/Info.plist"
	printf 'APPL????' > "$(BUNDLE)/Contents/PkgInfo"
	codesign --force --sign "$(IDENTITY)" --identifier com.github.labaznov.eveapmmac "$(BUNDLE)"
	@echo "built $(BUNDLE)"

run: bundle
	open "$(BUNDLE)"

test:
	swift test

clean:
	rm -rf build .build
