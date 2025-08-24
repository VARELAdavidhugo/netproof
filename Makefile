SHELL := /usr/bin/env bash

.PHONY: all test install lint

all: test

install:
	install -Dm0755 netproof.sh /usr/local/bin/netproof

test:
	tests/smoke.sh

lint:
	@command -v shellcheck >/dev/null || { echo "Installez shellcheck pour lint" ; exit 0; }
	shellcheck netproof.sh || true
