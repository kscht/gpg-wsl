# gpg-wsl - share one YubiKey OpenPGP card between two WSL users.
#
# Required variables (pass on command line or export):
#   PRIMARY_USER     - the user whose scdaemon talks to the YubiKey directly
#   SECONDARY_USER   - the user whose gpg-agent proxies through to PRIMARY_USER
#
# Targets:
#   make install   PRIMARY_USER=alice SECONDARY_USER=bob    (needs root)
#   make uninstall PRIMARY_USER=alice SECONDARY_USER=bob    (needs root)
#   make status    PRIMARY_USER=alice SECONDARY_USER=bob
#   make help

PROJECT_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
SCRIPTS     := $(PROJECT_DIR)/scripts

ENV := PRIMARY_USER='$(PRIMARY_USER)' SECONDARY_USER='$(SECONDARY_USER)' PROJECT_DIR='$(PROJECT_DIR)'

.PHONY: help install uninstall status check-vars

help:
	@awk '/^[^# ]./{exit} {sub(/^# ?/,""); print}' $(firstword $(MAKEFILE_LIST))

check-vars:
	@if [ -z "$(PRIMARY_USER)" ] || [ -z "$(SECONDARY_USER)" ]; then \
	    echo "PRIMARY_USER and SECONDARY_USER must be set, e.g.:"; \
	    echo "    make $(MAKECMDGOALS) PRIMARY_USER=alice SECONDARY_USER=bob"; \
	    exit 1; \
	fi

install: check-vars
	@$(ENV) bash $(SCRIPTS)/install.sh

uninstall: check-vars
	@$(ENV) bash $(SCRIPTS)/uninstall.sh

status: check-vars
	@$(ENV) bash $(SCRIPTS)/status.sh
