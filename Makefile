.PHONY: help test validate update sign lint lint-sh lint-js lint-actions lint-md lint-fix lint-sh-fix lint-js-fix lint-md-fix clean

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

lint: lint-sh lint-js lint-actions lint-md ## Check all (shell + JS + actions + markdown)
	@echo "All checks passed"

lint-sh: ## Check shell scripts (formatting + linting)
	shfmt -d -i 2 -ci -bn -sr scripts/ tests/
	shellcheck --severity=warning scripts/*.sh scripts/lib/*.sh tests/*.sh

lint-js: ## Check JavaScript (biome)
	npx biome check functions/

lint-actions: ## Check GitHub Actions workflows (actionlint)
	actionlint

lint-md: ## Check Markdown files (markdownlint)
	markdownlint-cli2 "*.md" "docs/**/*.md"

lint-fix: lint-sh-fix lint-js-fix lint-md-fix ## Fix all formatting

lint-sh-fix: ## Fix shell script formatting
	shfmt -w -i 2 -ci -bn -sr scripts/ tests/

lint-js-fix: ## Fix JavaScript formatting
	npx biome check --write functions/

lint-md-fix: ## Fix Markdown files
	markdownlint-cli2 --fix "*.md" "docs/**/*.md"

clean: ## Remove generated artifacts
	rm -rf artifacts/
