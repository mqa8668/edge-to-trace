SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help
export GIT_SHA ?= $(shell git rev-parse --short HEAD 2>/dev/null || echo dev)
DOCKER ?= docker
BEYLA_PRIVILEGED := $(shell grep -s '^BEYLA_PRIVILEGED=' .env | cut -d= -f2)
# Optional files: Telegram delivery when both secrets exist, privileged Beyla on request, EXTRA_COMPOSE for local overrides.
COMPOSE_FILES := -f compose.yaml \
  $(if $(and $(wildcard secrets/telegram_bot_token.txt),$(wildcard secrets/telegram_chat_id.txt)),-f compose.telegram.yaml) \
  $(if $(filter 1,$(BEYLA_PRIVILEGED)),-f compose.beyla-privileged.yaml) $(EXTRA_COMPOSE)
COMPOSE := $(DOCKER) compose $(COMPOSE_FILES) --profile lite
export DOCKER
export E2T_UID := $(shell id -u)
export E2T_GID := $(shell id -g)
export COMPOSE_EXTRA := $(COMPOSE_FILES)
APPS := catalog recs storefront alert-sink

.PHONY: help bootstrap up down clean doctor logs ps test lint smoke slo dashboards demo demo-reset chaos-latency chaos-errors chaos-reset

help: ## Show this help
	@awk 'BEGIN {FS = ":.*## "} /^[a-zA-Z_-]+:.*## / {printf "  %-16s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

bootstrap: ## Create .env with random secrets
	@scripts/bootstrap.sh

up: bootstrap ## Build and start the lite profile, wait until healthy
	$(COMPOSE) up -d --build --wait
	@echo; echo "storefront:   http://localhost:8080/api/products/1"; echo "grafana:      http://localhost:3000   (admin password in .env)"; echo "prometheus:   http://localhost:9090"; echo "alertmanager: http://localhost:9093"; echo "alert-sink:   http://localhost:9095/alerts"

down: ## Stop containers, keep volumes
	$(COMPOSE) --profile tools down

clean: ## Stop and remove containers, volumes and locally built images (FORCE=1 skips the prompt)
	@if [ "$(FORCE)" != "1" ]; then read -r -p "Remove all e2t containers, volumes and images? [y/N] " a; [ "$$a" = y ]; fi
	$(COMPOSE) --profile tools down -v --rmi local --remove-orphans

doctor: ## Check the host (Docker, memory, architecture)
	@scripts/doctor.sh

logs: ## Follow logs; S=<service> to pick one
	$(COMPOSE) logs -f --tail=100 $(S)

ps: ## List containers
	$(COMPOSE) ps

test: ## Unit tests for every app, run inside containers (no local toolchains needed)
	@for a in $(APPS); do echo "== $$a"; docker build -q --target test apps/$$a >/dev/null || exit 1; done; echo "unit tests passed"
	@docker run --rm --entrypoint promtool -v "$$PWD:/w" -w /w prom/prometheus:v3.13.4@sha256:87861b8cf91579109319ebc300f3f1060e6da9c05d6ae8ad15a20c879e84e32e test rules tests/prometheus/platform_test.yml tests/prometheus/slo_test.yml
	@tests/alertmanager_routes.sh

lint: ## Compose config, hadolint, shellcheck, gitleaks
	@scripts/bootstrap.sh >/dev/null && $(COMPOSE) config -q
	@for f in apps/*/Dockerfile db/Dockerfile; do echo "hadolint $$f"; docker run --rm -i hadolint/hadolint:v2.15.1@sha256:32dac94127fd60b7b7e3fbfc65e1383b9b5e25c9bfd7b8536de7a539fe68a12d hadolint --ignore DL3008 - < $$f || exit 1; done
	@shellcheck -S warning scripts/*.sh tests/*.sh
	@scripts/check-pins.sh && scripts/check-runbooks.sh
	@python3 scripts/gen-dashboards.py >/dev/null && git diff --exit-code grafana/dashboards
	@gitleaks dir . --no-banner --redact

chaos-latency: ## Inject latency (TARGET=recs|catalog|storefront, default recs)
	@scripts/chaos.sh latency $(TARGET)
chaos-errors: ## Inject 503s (TARGET=..., default catalog)
	@scripts/chaos.sh errors $(TARGET)
chaos-reset: ## Remove all injected faults
	@scripts/chaos.sh reset $(TARGET)

smoke: ## API-level checks against the running stack
	@scripts/smoke.sh

slo: ## Regenerate prometheus/rules/slo/*.generated.yml from slo/*.yml with sloth
	@docker run --rm --user "$$(id -u):$$(id -g)" -v "$$PWD:/w" -w /w ghcr.io/slok/sloth@sha256:f0f0075b0d45c1cf684e92947508cc1d5bf573925f785f803a439b2306c8b9a5 generate -i slo/storefront.yml -o prometheus/rules/slo/storefront.generated.yml

dashboards: ## Regenerate grafana/dashboards/*.json from scripts/gen-dashboards.py
	@python3 scripts/gen-dashboards.py

demo: export GRAFANA_VIEWERS_CAN_EDIT := true
demo: up ## One command: start the stack, run baseline load, inject latency, follow the alert to the trace
	@scripts/demo.sh run

demo-reset: ## End the demo: remove injected faults (WAIT=1 also waits for the resolved notification)
	@scripts/demo.sh reset $(if $(WAIT),--wait)
