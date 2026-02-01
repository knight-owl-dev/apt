.PHONY: help test validate update sign lint lint-fix clean

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-12s %s\n", $$1, $$2}'

test: ## Test package installation (PKG=name for one, default: all)
ifdef PKG
	./tests/test-package.sh $(PKG) $(IMAGE)
else
	./tests/test-all.sh $(IMAGE)
endif

validate: ## Validate local repo generation (VERSIONS="pkg:1.0.0" CLEAN=1)
ifdef CLEAN
	./tests/test-local-repo.sh --clean $(VERSIONS)
else
	./tests/test-local-repo.sh $(VERSIONS)
endif

update: ## Update repo metadata (VERSIONS="pkg:1.0.0")
	./scripts/update-repo.sh $(VERSIONS)

sign: ## Sign Release file with GPG
	./scripts/sign-release.sh

lint: ## Check shell script formatting
	shfmt -d -i 2 -ci -bn -sr scripts/ tests/

lint-fix: ## Fix shell script formatting
	shfmt -w -i 2 -ci -bn -sr scripts/ tests/

clean: ## Remove generated artifacts
	rm -rf artifacts/
