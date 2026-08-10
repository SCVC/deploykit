.PHONY: help lint check config
help:              ## show targets
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | sed 's/:.*##/ —/'
lint:              ## shellcheck all shell scripts
	@shellcheck -x macos/*.sh scripts/*.sh onboarding/*.sh || true
check: lint        ## alias for lint
config:            ## create config.env from the example
	@test -f config.env || cp config.env.example config.env; echo "edit config.env"
