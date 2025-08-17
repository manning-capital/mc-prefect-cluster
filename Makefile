# Makefile for Prefect Server Helm Installation

# Default values - adjust these as needed
NAMESPACE ?= prefect
CERT_MANAGER_NAMESPACE ?= cert-manager
SERVER_RELEASE_NAME ?= prefect-server
WORKER_RELEASE_NAME ?= prefect-worker
SERVER_CHART_REPO ?= prefect/prefect-server
WORKER_CHART_REPO ?= prefect/prefect-worker
CHART_VERSION ?= latest
SERVER_VALUES_FILE ?= src/server/values.yaml
WORKER_VALUES_FILE ?= src/worker/values.yaml
OAUTH2_VALUES_FILE ?= src/oauth-proxy/values.yaml
NGINX_INGRESS_VALUES_FILE ?= src/nginx-ingress-controller/values.yaml
NGINX_INGRESS_RELEASE_NAME ?= prefect-nginx-ingress
NGINX_INGRESS_NAMESPACE ?= $(NAMESPACE)
KUBE_CONTEXT ?= $(shell kubectl config current-context)
WORKER_WORK_QUEUE ?= default

# Default target
.PHONY: all
all: help

# Add Prefect Helm and OAuth2 Proxy repository
.PHONY: add-repos
add-repos:
	@echo "Adding Prefect Helm repository..."
	helm repo add prefect https://prefecthq.github.io/prefect-helm
	helm repo add oauth2-proxy https://oauth2-proxy.github.io/manifests
	helm repo update

# Add rbac permissions for Prefect server and worker
.PHONY: add-rbac
add-rbac:
	@echo "Adding RBAC permissions for Prefect server and worker..."
	kubectl apply -f src/worker/rbac.yaml

# Create cluster issuer for Let's Encrypt
.PHONY: create-cluster-issuer
create-cluster-issuer:
	@echo "Creating cluster issuer for Let's Encrypt..."
	kubectl apply -f src/oauth-proxy/cluster-issuer.yaml --namespace $(CERT_MANAGER_NAMESPACE)

# Create namespace if it doesn't exist
.PHONY: create-namespace
create-namespace:
	@echo "Creating namespace $(NAMESPACE) if it doesn't exist..."
	kubectl create namespace $(NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -

# Upgrade/Install Prefect server using Helm (--install flag ensures it installs if not exists, upgrades if exists)
.PHONY: upgrade-server
upgrade-server: add-repos create-namespace
	@echo "Upgrading/Installing Prefect server in namespace $(NAMESPACE)..."
	helm upgrade --install $(SERVER_RELEASE_NAME) $(SERVER_CHART_REPO) \
		--namespace $(NAMESPACE) \
		$(if $(wildcard $(SERVER_VALUES_FILE)),--values $(SERVER_VALUES_FILE),)

# Upgrade/Install Prefect worker using Helm (--install flag ensures it installs if not exists, upgrades if exists)
.PHONY: upgrade-worker
upgrade-worker: add-repos create-namespace
	@echo "Upgrading/Installing Prefect worker in namespace $(NAMESPACE)..."
	helm upgrade --install $(WORKER_RELEASE_NAME) $(WORKER_CHART_REPO) \
		--namespace $(NAMESPACE) \
		$(if $(wildcard $(WORKER_VALUES_FILE)),--values $(WORKER_VALUES_FILE),) \
		--set-file worker.config.baseJobTemplate.configuration=src/worker/base-job-template.json

# Upgrade/Install OAuth2 Proxy with optional secrets
# Note: cookieSecret must be 16, 24, or 32 bytes (raw) or 22, 32, or 44 characters (base64)
.PHONY: upgrade-oauth-proxy
upgrade-oauth-proxy: add-repos create-namespace
	@echo "Upgrading/Installing OAuth proxy in namespace $(NAMESPACE)..."
	helm upgrade --install prefect-oauth2-proxy oauth2-proxy/oauth2-proxy \
		--namespace $(NAMESPACE) \
		${if $(wildcard $(OAUTH2_VALUES_FILE)),--values $(OAUTH2_VALUES_FILE),} \
		${if $(OAUTH2_CLIENT_ID),--set config.clientID=$(OAUTH2_CLIENT_ID),} \
		${if $(OAUTH2_CLIENT_SECRET),--set config.clientSecret=$(OAUTH2_CLIENT_SECRET),} \
		${if $(OAUTH2_COOKIE_SECRET),--set config.cookieSecret=$(OAUTH2_COOKIE_SECRET),}

# Upgrade/Install both server and worker, then upgrade ingresses
.PHONY: upgrade
upgrade: upgrade-server upgrade-worker upgrade-oauth-proxy
	@echo "Upgrading ingress resources..."
	$(MAKE) create-cluster-issuer
	$(MAKE) upgrade-server-ingress
	$(MAKE) upgrade-oauth2-ingress

# Upgrade server ingress
.PHONY: upgrade-server-ingress
upgrade-server-ingress:
	@echo "Upgrading Prefect Server Ingress resource..."
	kubectl apply -f src/server/server-ingress.yaml --namespace $(NAMESPACE)

# Upgrade oauth2 ingress
.PHONY: upgrade-oauth2-ingress
upgrade-oauth2-ingress:
	@echo "Upgrading OAuth2 Ingress resource..."
	kubectl apply -f src/oauth-proxy/oauth-ingress.yaml --namespace $(NAMESPACE)

# Uninstall Prefect server
.PHONY: uninstall-server
uninstall-server:
	@echo "Uninstalling Prefect server from namespace $(NAMESPACE)..."
	helm uninstall $(SERVER_RELEASE_NAME) --namespace $(NAMESPACE) --kube-context $(KUBE_CONTEXT)

# Uninstall Prefect worker
.PHONY: uninstall-worker
uninstall-worker:
	@echo "Uninstalling Prefect worker from namespace $(NAMESPACE)..."
	helm uninstall $(WORKER_RELEASE_NAME) --namespace $(NAMESPACE) --kube-context $(KUBE_CONTEXT)

# Uninstall OAuth2 Proxy
.PHONY: uninstall-oauth-proxy
uninstall-oauth-proxy:
	@echo "Uninstalling OAuth2 Proxy from namespace $(NAMESPACE)..."
	helm uninstall prefect-oauth2-proxy --namespace $(NAMESPACE)

# Uninstall server ingress
.PHONY: uninstall-server-ingress
uninstall-server-ingress:
	@echo "Uninstalling Prefect Server Ingress resource..."
	kubectl delete -f src/server/server-ingress.yaml --namespace $(NAMESPACE) --ignore-not-found=true

# Uninstall oauth2 ingress
.PHONY: uninstall-oauth2-ingress
uninstall-oauth2-ingress:
	@echo "Uninstalling OAuth2 Ingress resource..."
	kubectl delete -f src/oauth-proxy/oauth-ingress.yaml --namespace $(NAMESPACE) --ignore-not-found=true

# Uninstall both server and worker
.PHONY: uninstall
uninstall: uninstall-server uninstall-worker uninstall-oauth-proxy uninstall-server-ingress uninstall-oauth2-ingress

# Start port forwarding to access Prefect UI
.PHONY: port-forward
port-forward:
	@echo "Port forwarding Prefect UI to http://localhost:4200..."
	kubectl port-forward --namespace $(NAMESPACE) svc/$(SERVER_RELEASE_NAME) 4200:4200

# Check the status of the deployment
.PHONY: status
status:
	@echo "Checking deployment status in namespace $(NAMESPACE)..."
	kubectl get pods,svc,deployments -n $(NAMESPACE)

# Create default server values file if it doesn't exist
$(SERVER_VALUES_FILE):
	@echo "Creating default server values file at $(SERVER_VALUES_FILE)..."
	@mkdir -p src/server
	@echo "# Prefect Server Helm chart configuration" > $(SERVER_VALUES_FILE)
	@echo "# See https://github.com/PrefectHQ/prefect-helm/tree/main/charts/prefect-server for all options" >> $(SERVER_VALUES_FILE)
	@echo "" >> $(SERVER_VALUES_FILE)
	@echo "# Server configuration" >> $(SERVER_VALUES_FILE)
	@echo "server:" >> $(SERVER_VALUES_FILE)
	@echo "  replicas: 1" >> $(SERVER_VALUES_FILE)

# Create default worker values file if it doesn't exist
$(WORKER_VALUES_FILE):
	@echo "Creating default worker values file at $(WORKER_VALUES_FILE)..."
	@mkdir -p src/worker
	@echo "# Prefect Worker Helm chart configuration" > $(WORKER_VALUES_FILE)
	@echo "# See https://github.com/PrefectHQ/prefect-helm/tree/main/charts/prefect-worker for all options" >> $(WORKER_VALUES_FILE)
	@echo "" >> $(WORKER_VALUES_FILE)
	@echo "# Worker configuration" >> $(WORKER_VALUES_FILE)
	@echo "worker:" >> $(WORKER_VALUES_FILE)
	@echo "  replicas: 1" >> $(WORKER_VALUES_FILE)

.PHONY: create-server-values
create-server-values: $(SERVER_VALUES_FILE)

.PHONY: create-worker-values
create-worker-values: $(WORKER_VALUES_FILE)

.PHONY: create-values
create-values: create-server-values create-worker-values

# Display help information
.PHONY: help
help:
	@echo "Prefect Server and Worker Helm Installation Makefile"
	@echo ""
	@echo "Available targets:"
	@echo "  add-repos          - Add Prefect Helm repository"
	@echo "  add-rbac           - Add RBAC permissions for Prefect server and worker"
	@echo "  create-namespace   - Create Kubernetes namespace"
	@echo "  upgrade-server     - Upgrade/Install Prefect server (uses --install flag)"
	@echo "  upgrade-worker     - Upgrade/Install Prefect worker (uses --install flag)"
	@echo "  upgrade-oauth-proxy - Upgrade/Install OAuth2 Proxy (uses --install flag)"
	@echo "  upgrade            - Upgrade/Install both Prefect server and worker, then upgrade ingresses"
	@echo "  upgrade-server-ingress - Upgrade Prefect Server Ingress resource"
	@echo "  upgrade-oauth2-ingress - Upgrade OAuth2 Ingress resource"
	@echo "  uninstall-server   - Uninstall Prefect server"
	@echo "  uninstall-worker   - Uninstall Prefect worker"
	@echo "  uninstall-oauth-proxy - Uninstall OAuth2 Proxy"
	@echo "  uninstall-server-ingress - Uninstall Prefect Server Ingress resource"
	@echo "  uninstall-oauth2-ingress - Uninstall OAuth2 Ingress resource"
	@echo "  uninstall          - Uninstall both server and worker with ingresses"
	@echo "  port-forward       - Start port forwarding to access Prefect UI"
	@echo "  status             - Check deployment status"
	@echo "  create-server-values - Create default server-values.yaml if it doesn't exist"
	@echo "  create-worker-values - Create default worker-values.yaml if it doesn't exist"
	@echo "  create-values      - Create both default values files if they don't exist"
	@echo "  help               - Show this help message"