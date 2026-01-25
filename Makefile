.PHONY: help test test-all test-local update sign clean

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-12s %s\n", $$1, $$2}'

test: ## Test first package (or: make test PKG=name IMAGE=ubuntu:24.04)
	./tests/test-package.sh $(PKG) $(IMAGE)

test-all: ## Test all packages (or: make test-all IMAGE=ubuntu:24.04)
	./tests/test-all.sh $(IMAGE)

test-local: ## Validate local repo generation (or: make test-local VERSIONS="pkg:1.0.0")
	./tests/test-local-repo.sh $(VERSIONS)

update: ## Update repo metadata (or: make update VERSIONS="pkg:1.0.0")
	./scripts/update-repo.sh $(VERSIONS)

sign: ## Sign Release file with GPG
	./scripts/sign-release.sh

clean: ## Remove generated artifacts
	rm -rf artifacts/
