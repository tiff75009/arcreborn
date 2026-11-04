.PHONY: dev build check release-check
dev:
	./native/scripts/dev.sh
build:
	./native/scripts/dev.sh --build-only
check:
	./native/scripts/check.sh
release-check:
	/usr/bin/python3 native/scripts/release.py check
