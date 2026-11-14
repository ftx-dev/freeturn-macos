CORE_VERSION := v4.1.5
F := /Library/Developer/CommandLineTools/Library/Developer/Frameworks
L := /Library/Developer/CommandLineTools/Library/Developer/usr/lib
# Xcode нет: Testing.framework лежит в Command Line Tools вне путей поиска по умолчанию.
SWIFT_TEST_FLAGS := -Xswiftc -F$(F) -Xlinker -F$(F) -Xlinker -rpath -Xlinker $(F) -Xlinker -rpath -Xlinker $(L)

.PHONY: deps engine helper app test test-go test-app test-sh run ftctl

deps:
	git submodule update --init

engine:
	cd third_party/amnezia-box && go build -trimpath -ldflags "-s -w" -tags "with_gvisor,with_wireguard,with_awg" -o ../../build/amnezia-box ./cmd/sing-box

helper:
	cd helper && go build -trimpath -ldflags "-checklinkname=0 -s -w -X github.com/samosvalishe/free-turn-proxy/mobile.version=$(CORE_VERSION)" -o ../build/ ./cmd/...

test-go:
	cd helper && go test -ldflags=-checklinkname=0 ./...

test-app:
	cd App && swift test $(SWIFT_TEST_FLAGS)

test-sh:
	scripts/proof-lib.test.sh

test: test-go test-app test-sh

ftctl:
	cd App && swift build --product ftctl

app: engine helper
	scripts/bundle-app.sh

run:
	open build/FreeTurn.app
