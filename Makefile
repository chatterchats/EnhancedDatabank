include tools/mod.mk

# This repo's own targets and hooks go below. Document targets with "## text" so
# `make help` lists them; hooks use double colons (test-extra:: and so on, see tools/mod.mk).

debug-logs: ## Copy UE4SS.log, the mod log and recent crash reports into dev/debug/ (CRASHES=n)
	tools/collect_debug_logs.sh $(if $(CRASHES),--crashes $(CRASHES))
