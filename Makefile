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

# Create oauth2 ingress resource.
.PHONY: create-oauth2-ingress
create-oauth2-ingress:
	@echo "Creating OAuth2 Ingress resource..."
	kubectl apply -f src/oauth-proxy/oauth-ingress.yaml --namespace $(NAMESPACE)

# Create prefect server ingress resource.
.PHONY: create-server-ingress
create-server-ingress:
	@echo "Creating Prefect Server Ingress resource..."
	kubectl apply -f src/server/server-ingress.yaml --namespace $(NAMESPACE)

# Create ingress resources
.PHONY: create-ingress
create-ingress: create-cluster-issuer create-oauth2-ingress create-server-ingress

# Create namespace if it doesn't exist
.PHONY: create-namespace
create-namespace:
	@echo "Creating namespace $(NAMESPACE) if it doesn't exist..."
	kubectl create namespace $(NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -

# Install Prefect server using Helm
.PHONY: install-server
install-server: add-repos create-namespace
	@echo "Installing Prefect server in namespace $(NAMESPACE)..."
	helm install $(SERVER_RELEASE_NAME) $(SERVER_CHART_REPO) \
		--namespace $(NAMESPACE) \
		$(if $(wildcard $(SERVER_VALUES_FILE)),--values $(SERVER_VALUES_FILE),)

# Install Prefect worker using Helm
.PHONY: install-worker
install-worker: add-repos create-namespace
	@echo "Installing Prefect worker in namespace $(NAMESPACE)..."
	helm install $(WORKER_RELEASE_NAME) $(WORKER_CHART_REPO) \
		--namespace $(NAMESPACE) \
		$(if $(wildcard $(WORKER_VALUES_FILE)),--values $(WORKER_VALUES_FILE),)

.PHONY: install-oauth-proxy
install-oauth-proxy: add-repos create-namespace
	@echo "Installing OAuth proxy in namespace $(NAMESPACE)..."
	helm install prefect-oauth2-proxy oauth2-proxy/oauth2-proxy \
		--namespace $(NAMESPACE) \
		${if $(wildcard $(OAUTH2_VALUES_FILE)),--values $(OAUTH2_VALUES_FILE),}

# Install both server and worker
.PHONY: install
install: install-server install-worker install-oauth-proxy create-ingress

# Upgrade existing server installation
.PHONY: upgrade-server
upgrade-server: add-repos
	@echo "Upgrading Prefect server in namespace $(NAMESPACE)..."
	helm upgrade $(SERVER_RELEASE_NAME) $(SERVER_CHART_REPO) \
		--namespace $(NAMESPACE) \
		$(if $(wildcard $(SERVER_VALUES_FILE)),--values $(SERVER_VALUES_FILE),)

# Upgrade existing worker installation
.PHONY: upgrade-worker
upgrade-worker: add-repos
	@echo "Upgrading Prefect worker in namespace $(NAMESPACE)..."
	helm upgrade $(WORKER_RELEASE_NAME) $(WORKER_CHART_REPO) \
		--namespace $(NAMESPACE) \
		$(if $(wildcard $(WORKER_VALUES_FILE)),--values $(WORKER_VALUES_FILE),) \
		--set-file worker.config.baseJobTemplate.configuration=src/worker/base-job-template.json

# Upgrade OAuth2 Proxy
.PHONY: upgrade-oauth-proxy
upgrade-oauth-proxy: add-repos
	@echo "Upgrading OAuth2 Proxy in namespace $(NAMESPACE)..."
	helm upgrade prefect-oauth2-proxy oauth2-proxy/oauth2-proxy \
		--namespace $(NAMESPACE) \
		${if $(wildcard $(OAUTH2_VALUES_FILE)),--values $(OAUTH2_VALUES_FILE),}

# Upgrade both server and worker
.PHONY: upgrade
upgrade: upgrade-server upgrade-worker upgrade-oauth-proxy create-ingress

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

# Uninstall both server and worker
.PHONY: uninstall
uninstall: uninstall-server uninstall-worker uninstall-oauth-proxy

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
	@echo "  install-server     - Install only Prefect server"
	@echo "  install-worker     - Install only Prefect worker"
	@echo "  install-oauth-proxy - Install OAuth2 Proxy for authentication"
	@echo "  install            - Install both Prefect server and worker"
	@echo "  upgrade-server     - Upgrade existing Prefect server installation"
	@echo "  upgrade-worker     - Upgrade existing Prefect worker installation"
	@echo "  upgrade            - Upgrade both server and worker installations"
	@echo "  uninstall-server   - Uninstall Prefect server"
	@echo "  uninstall-worker   - Uninstall Prefect worker"
	@echo "  uninstall-oauth-proxy - Uninstall OAuth2 Proxy"
	@echo "  uninstall          - Uninstall both server and worker"
	@echo "  port-forward       - Start port forwarding to access Prefect UI"
	@echo "  status             - Check deployment status"
	@echo "  create-server-values - Create default server-values.yaml if it doesn't exist"
	@echo "  create-worker-values - Create default worker-values.yaml if it doesn't exist"
	@echo "  create-values      - Create both default values files if they don't exist"
	@echo "  help               - Show this help message"