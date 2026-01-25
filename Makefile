.PHONY: help test validate update sign clean

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-12s %s\n", $$1, $$2}'

test: ## Test package installation (PKG=name for one, default: all)
ifdef PKG
	./tests/test-package.sh $(PKG) $(IMAGE)
else
	./tests/test-all.sh $(IMAGE)
endif

validate: ## Validate local repo generation (VERSIONS="pkg:1.0.0")
	./tests/test-local-repo.sh $(VERSIONS)

update: ## Update repo metadata (VERSIONS="pkg:1.0.0")
	./scripts/update-repo.sh $(VERSIONS)

sign: ## Sign Release file with GPG
	./scripts/sign-release.sh

clean: ## Remove generated artifacts
	rm -rf artifacts/
