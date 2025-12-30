build-ApiV2Function:
	dart pub get
	dart compile exe bin/main.dart -o bootstrap --target-os=linux
	cp bootstrap $(ARTIFACTS_DIR)/