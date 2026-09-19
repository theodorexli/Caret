.PHONY: demo app install dmg test check sources

demo:
	python3 -m caret preview --fixture fixtures/meeting.json

app:
	python3 scripts/run_mac.py

install:
	python3 scripts/package_mac.py --install

dmg:
	python3 scripts/package_mac.py --dmg

test:
	python3 -m unittest discover -s tests -v

check: test
	python3 scripts/check_sources.py
	swift build --package-path apps/mac

sources:
	git submodule update --init --depth 1 packages/keytype packages/ghosttype packages/computer-use-jev
