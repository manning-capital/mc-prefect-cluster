# Makefile for Prefect Server Helm Installation

# Default values - adjust these as needed
NAMESPACE ?= prefect
SERVER_RELEASE_NAME ?= prefect-server
WORKER_RELEASE_NAME ?= prefect-worker
SERVER_CHART_REPO ?= prefect/prefect-server
WORKER_CHART_REPO ?= prefect/prefect-worker
CHART_VERSION ?= latest
SERVER_VALUES_FILE ?= server-values.yaml
WORKER_VALUES_FILE ?= worker-values.yaml
KUBE_CONTEXT ?= $(shell kubectl config current-context)
WORKER_WORK_QUEUE ?= default

# Default target
.PHONY: all
all: help

# Add Prefect Helm repository
.PHONY: add-repo
add-repo:
	@echo "Adding Prefect Helm repository..."
	helm repo add prefect https://prefecthq.github.io/prefect-helm
	helm repo update

# Add rbac permissions for Prefect server and worker
.PHONY: add-rbac
add-rbac:
	@echo "Adding RBAC permissions for Prefect server and worker..."
	kubectl apply -f worker-rbac.yaml

# Create namespace if it doesn't exist
.PHONY: create-namespace
create-namespace:
	@echo "Creating namespace $(NAMESPACE) if it doesn't exist..."
	kubectl create namespace $(NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -

# Install Prefect server using Helm
.PHONY: install-server
install-server: add-repo create-namespace
	@echo "Installing Prefect server in namespace $(NAMESPACE)..."
	helm install $(SERVER_RELEASE_NAME) $(SERVER_CHART_REPO) \
		--namespace $(NAMESPACE) \
		$(if $(wildcard $(SERVER_VALUES_FILE)),--values $(SERVER_VALUES_FILE),)

# Install Prefect worker using Helm
.PHONY: install-worker
install-worker: add-repo create-namespace
	@echo "Installing Prefect worker in namespace $(NAMESPACE)..."
	helm install $(WORKER_RELEASE_NAME) $(WORKER_CHART_REPO) \
		--namespace $(NAMESPACE) \
		$(if $(wildcard $(WORKER_VALUES_FILE)),--values $(WORKER_VALUES_FILE),)

# Install both server and worker
.PHONY: install
install: install-server install-worker

# Upgrade existing server installation
.PHONY: upgrade-server
upgrade-server: add-repo
	@echo "Upgrading Prefect server in namespace $(NAMESPACE)..."
	helm upgrade $(SERVER_RELEASE_NAME) $(SERVER_CHART_REPO) \
		--namespace $(NAMESPACE) \
		$(if $(wildcard $(SERVER_VALUES_FILE)),--values $(SERVER_VALUES_FILE),)

# Upgrade existing worker installation
.PHONY: upgrade-worker
upgrade-worker: add-repo
	@echo "Upgrading Prefect worker in namespace $(NAMESPACE)..."
	helm upgrade $(WORKER_RELEASE_NAME) $(WORKER_CHART_REPO) \
		--namespace $(NAMESPACE) \
		$(if $(wildcard $(WORKER_VALUES_FILE)),--values $(WORKER_VALUES_FILE),)

# Upgrade both server and worker
.PHONY: upgrade
upgrade: upgrade-server upgrade-worker

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

# Uninstall both server and worker
.PHONY: uninstall
uninstall: uninstall-server uninstall-worker

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
	@echo "# Prefect Server Helm chart configuration" > $(SERVER_VALUES_FILE)
	@echo "# See https://github.com/PrefectHQ/prefect-helm/tree/main/charts/prefect-server for all options" >> $(SERVER_VALUES_FILE)
	@echo "" >> $(SERVER_VALUES_FILE)
	@echo "# Server configuration" >> $(SERVER_VALUES_FILE)
	@echo "server:" >> $(SERVER_VALUES_FILE)
	@echo "  replicas: 1" >> $(SERVER_VALUES_FILE)

# Create default worker values file if it doesn't exist
$(WORKER_VALUES_FILE):
	@echo "Creating default worker values file at $(WORKER_VALUES_FILE)..."
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
	@echo "  add-repo           - Add Prefect Helm repository"
	@echo "  add-rbac           - Add RBAC permissions for Prefect server and worker"
	@echo "  create-namespace   - Create Kubernetes namespace"
	@echo "  install-server     - Install only Prefect server"
	@echo "  install-worker     - Install only Prefect worker"
	@echo "  install            - Install both Prefect server and worker"
	@echo "  upgrade-server     - Upgrade existing Prefect server installation"
	@echo "  upgrade-worker     - Upgrade existing Prefect worker installation"
	@echo "  upgrade            - Upgrade both server and worker installations"
	@echo "  uninstall-server   - Uninstall Prefect server"
	@echo "  uninstall-worker   - Uninstall Prefect worker"
	@echo "  uninstall          - Uninstall both server and worker"
	@echo "  port-forward       - Start port forwarding to access Prefect UI"
	@echo "  status             - Check deployment status"
	@echo "  create-server-values - Create default server-values.yaml if it doesn't exist"
	@echo "  create-worker-values - Create default worker-values.yaml if it doesn't exist"
	@echo "  create-values      - Create both default values files if they don't exist"
	@echo "  help               - Show this help message"
	@echo ""
	@echo "Customizable variables:"
	@echo "  NAMESPACE           - Kubernetes namespace (default: prefect)"
	@echo "  SERVER_RELEASE_NAME - Helm release name for server (default: prefect-server)"
	@echo "  WORKER_RELEASE_NAME - Helm release name for worker (default: prefect-worker)"
	@echo "  CHART_VERSION       - Helm chart version (default: latest)"
	@echo "  SERVER_VALUES_FILE  - Path to server values file (default: server-values.yaml)"
	@echo "  WORKER_VALUES_FILE  - Path to worker values file (default: worker-values.yaml)"
	@echo "  KUBE_CONTEXT        - Kubernetes context to use (default: current context)"
	@echo "  WORKER_WORK_QUEUE   - Work queue name for worker (default: default)"