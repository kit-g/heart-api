COMMIT ?= $(shell git rev-parse HEAD)
BUILD_TIME ?= $(shell date -u +"%Y-%m-%dT%H:%M:%SZ")

# The card scripts compile into the binary (pages/cards/, via `make cards`), and
# so do the response shapes (via `make openapi`).
build-ApiFunction:
	$(MAKE) -C .. cards
	$(MAKE) -C .. openapi
	dart pub get
	cp bin/supabase-ca.crt $(ARTIFACTS_DIR)/supabase-ca.crt
	dart compile exe bin/main.dart \
		-DCOMMIT='$(COMMIT)' \
		-DBUILD_TIME='$(BUILD_TIME)' \
		--target-os=linux \
		--target-arch=arm64 \
		-o $(ARTIFACTS_DIR)/bootstrap
