# smoovmux — formatting, linting, QA targets.
#
# All hooks (devenv git-hooks, Xcode build phase, future CI) call into here so
# there is one source of truth for "what passes."
#
# Quick reference:
#   make fmt          # autoformat with swift-format (writes)
#   make fmt-check    # swift-format lint mode (read-only)
#   make lint         # swiftlint, no autofix
#   make lint-fix     # swiftlint --fix, then format
#   make qa           # what hooks/CI run: fmt-check + lint
#   make scripts-test # shell-script behavior tests
#   make secrets      # gitleaks scan
#
# `swift format` ships with the Swift 6 toolchain (no install).
# `swiftlint` and `gitleaks` come from mise (.mise.toml) or devenv (devenv.nix).

SWIFT_DIRS := App Sources Tests
SWIFT_FORMAT_CONFIG := .swift-format

.PHONY: fmt fmt-check lint lint-fix qa scripts-test secrets help

help:
	@awk 'BEGIN { FS = ":.*##" } /^[a-zA-Z_-]+:.*?##/ { printf "  %-12s %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

fmt: ## autoformat Swift sources in place
	swift format --in-place --recursive --configuration $(SWIFT_FORMAT_CONFIG) $(SWIFT_DIRS)

fmt-check: ## verify formatting (no writes); fails on diff
	swift format lint --strict --recursive --configuration $(SWIFT_FORMAT_CONFIG) $(SWIFT_DIRS)

lint: ## swiftlint, no autofix
	swiftlint --quiet

lint-fix: ## swiftlint --fix, then re-format
	swiftlint --fix --quiet
	$(MAKE) fmt

qa: fmt-check lint ## what pre-commit / CI runs

scripts-test: ## run shell-script behavior tests
	Tests/Scripts/install-build-tests.sh
	Tests/Scripts/set-version-tests.sh
	Tests/Scripts/release-tests.sh

secrets: ## scan for committed secrets
	gitleaks detect --source . --redact --verbose --no-git
