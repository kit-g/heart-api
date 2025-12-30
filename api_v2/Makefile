COMMIT ?= $(shell git rev-parse HEAD)
BUILD_TIME ?= $(shell date -u +"%Y-%m-%dT%H:%M:%SZ")

build-ApiV2Function:
	dart pub get
	dart compile exe bin/main.dart \
		-DCOMMIT=$(COMMIT) \
		-DBUILD_TIME=$(BUILD_TIME) \
		-o bootstrap \
		--target-os=linux