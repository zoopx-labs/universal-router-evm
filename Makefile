# Makefile targets for running tests and static analysis
.PHONY: test test-ci slither

test:
	forge test -vvv

test-ci:
	forge test --profile ci

slither:
	slither . --solc-remaps @openzeppelin/=lib/openzeppelin-contracts/ --exclude-informational
