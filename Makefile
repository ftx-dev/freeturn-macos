CORE_VERSION := v4.1.5
F := /Library/Developer/CommandLineTools/Library/Developer/Frameworks
L := /Library/Developer/CommandLineTools/Library/Developer/usr/lib
# Xcode нет: Testing.framework лежит в Command Line Tools вне путей поиска по умолчанию.
SWIFT_TEST_FLAGS := -Xswiftc -F$(F) -Xlinker -F$(F) -Xlinker -rpath -Xlinker $(F) -Xlinker -rpath -Xlinker $(L)

.PHONY: deps engine helper app dmg test test-go test-app test-sh run ftctl icon

deps:
	git submodule update --init

# GOARCH=amd64 GOOUT=build/x86_64 - сборка под Intel (так делает make dmg).
GOOUT ?= build

engine:
	cd third_party/amnezia-box && go build -trimpath -ldflags "-s -w" -tags "with_gvisor,with_wireguard,with_awg" -o $(CURDIR)/$(GOOUT)/amnezia-box ./cmd/sing-box

helper:
	cd helper && go build -trimpath -ldflags "-checklinkname=0 -s -w -X github.com/samosvalishe/free-turn-proxy/mobile.version=$(CORE_VERSION)" -o $(CURDIR)/$(GOOUT)/ ./cmd/...

test-go:
	cd helper && go test -ldflags=-checklinkname=0 ./...

test-app:
	cd App && swift test $(SWIFT_TEST_FLAGS)

test-sh:
	scripts/proof-lib.test.sh
	scripts/install-daemon.test.sh

test: test-go test-app test-sh

ftctl:
	cd App && swift build --product ftctl

app: engine helper
	scripts/bundle-app.sh

# Установщики: build/FreeTurn-<версия>-arm64.dmg и build/FreeTurn-<версия>-x86_64.dmg.
dmg:
	scripts/make-dmg.sh arm64
	scripts/make-dmg.sh x86_64

icon:
	swift scripts/make-icon.swift App/Bundle/AppIcon.svg App/Bundle/AppIcon.icns

run:
	open build/FreeTurn.app
