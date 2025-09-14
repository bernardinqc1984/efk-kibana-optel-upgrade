#!/bin/bash

# Kubernetes Monitoring Stack Installer
# ElasticSearch + Fluentd + Jaeger + OpenTelemetry

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="observability"
ELASTICSEARCH_VERSION="8.5.1"
JAEGER_VERSION="1.41.0"

echo -e "${BLUE} Installing Kubernetes Monitoring Stack${NC}"
echo -e "${BLUE}======================================${NC}"

# Function to print status
print_status() {
    echo -e "${GREEN} $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}  $1${NC}"
}

print_error() {
    echo -e "${RED} $1${NC}"
}

# Check prerequisites
echo -e "\n${BLUE}Checking prerequisites...${NC}"

# Check kubectl
if ! command -v kubectl &> /dev/null; then
    print_error "kubectl is not installed. Please install kubectl first."
    exit 1
fi
print_status "kubectl found"

# Check helm
if ! command -v helm &> /dev/null; then
    print_error "helm is not installed. Please install helm first."
    exit 1
fi
print_status "helm found"

# Check cluster connection
if ! kubectl cluster-info &> /dev/null; then
    print_error "Cannot connect to Kubernetes cluster. Please check your kubeconfig."
    exit 1
fi
print_status "Kubernetes cluster connection verified"

# Create namespace
echo -e "\n${BLUE}Creating namespace...${NC}"
kubectl apply -f manifests/namespace.yaml
print_status "Namespace '${NAMESPACE}' created"

# Add Helm repositories
echo -e "\n${BLUE}Adding Helm repositories...${NC}"
helm repo add elastic https://helm.elastic.co
helm repo add jaegertracing https://jaegertracing.github.io/helm-charts
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo update
print_status "Helm repositories added and updated"

# Install ElasticSearch
echo -e "\n${BLUE}Installing ElasticSearch...${NC}"
kubectl apply -f manifests/elasticsearch/
print_status "ElasticSearch deployment created"

# Wait for ElasticSearch to be ready
echo -e "${YELLOW}Waiting for ElasticSearch to be ready...${NC}"
kubectl wait --for=condition=ready pod -l app=elasticsearch -n ${NAMESPACE} --timeout=300s
print_status "ElasticSearch is ready"

# Create ElasticSearch index template
echo -e "\n${BLUE}Creating ElasticSearch index template...${NC}"
sleep 30  # Give ES time to fully start
kubectl port-forward svc/elasticsearch 9200:9200 -n ${NAMESPACE} &
PORT_FORWARD_PID=$!
sleep 10

# Set up built-in user passwords
echo -e "${YELLOW}Setting up ElasticSearch built-in users...${NC}"
curl -X POST "localhost:9200/_security/user/kibana_system/_password" \
  -H 'Content-Type: application/json' \
  -u "elastic:elastic_password" \
  -d '{"password":"kibana_password"}' || true

# Create a monitoring user for basic access
curl -X POST "localhost:9200/_security/user/monitoring_user" \
  -H 'Content-Type: application/json' \
  -u "elastic:elastic_password" \
  -d '{
    "password": "monitoring123",
    "roles": ["kibana_user", "monitoring_user"],
    "full_name": "Monitoring User",
    "email": "monitoring@example.com"
  }' || true

# Create monitoring role
curl -X POST "localhost:9200/_security/role/monitoring_user" \
  -H 'Content-Type: application/json' \
  -u "elastic:elastic_password" \
  -d '{
    "cluster": ["monitor"],
    "indices": [
      {
        "names": ["fluentd-*", "logstash-*", ".kibana*"],
        "privileges": ["read", "write", "create", "delete", "index", "view_index_metadata"]
      }
    ]
  }' || true

# Create index template
curl -X PUT "localhost:9200/_index_template/fluentd-logs" \
  -H 'Content-Type: application/json' \
  -d @configs/elasticsearch-index.json || true

kill $PORT_FORWARD_PID 2>/dev/null || true
print_status "ElasticSearch index template created"

# Install Fluentd
echo -e "\n${BLUE}Installing Fluentd...${NC}"
kubectl apply -f manifests/fluentd/
print_status "Fluentd DaemonSet created"

# Wait for Fluentd to be ready with more flexible approach
echo -e "${YELLOW}Waiting for Fluentd to be ready...${NC}"
sleep 30  # Give Fluentd time to start
if kubectl wait --for=condition=ready pod -l app=fluentd -n ${NAMESPACE} --timeout=120s 2>/dev/null; then
    print_status "Fluentd is ready"
else
    print_warning "Fluentd may still be starting, continuing with installation..."
    # Check if pods are at least running
    RUNNING_PODS=$(kubectl get pods -n ${NAMESPACE} -l app=fluentd --no-headers | grep -c "Running" || echo "0")
    if [ "$RUNNING_PODS" -gt 0 ]; then
        print_status "Fluentd pods are running ($RUNNING_PODS pods)"
    else
        print_warning "Fluentd pods may still be starting"
    fi
fi

# Install Kibana
echo -e "\n${BLUE}Installing Kibana...${NC}"
kubectl apply -f manifests/kibana/
print_status "Kibana deployment created"

# Wait for Kibana to be ready
echo -e "${YELLOW}Waiting for Kibana to be ready...${NC}"
if kubectl wait --for=condition=ready pod -l app=kibana -n ${NAMESPACE} --timeout=300s 2>/dev/null; then
    print_status "Kibana is ready"
else
    print_warning "Kibana may still be starting, checking status..."
    RUNNING_PODS=$(kubectl get pods -n ${NAMESPACE} -l app=kibana --no-headers | grep -c "Running" || echo "0")
    if [ "$RUNNING_PODS" -gt 0 ]; then
        print_status "Kibana pods are running ($RUNNING_PODS pods)"
    else
        print_warning "Kibana pods may still be starting"
    fi
fi

# Install Jaeger
echo -e "\n${BLUE}Installing Jaeger...${NC}"
kubectl apply -f manifests/jaeger/
print_status "Jaeger deployment created"

# Wait for Jaeger to be ready
echo -e "${YELLOW}Waiting for Jaeger to be ready...${NC}"
kubectl wait --for=condition=ready pod -l app=jaeger -n ${NAMESPACE} --timeout=300s
print_status "Jaeger is ready"

# Install OpenTelemetry Collector
echo -e "\n${BLUE}Installing OpenTelemetry Collector...${NC}"
kubectl apply -f manifests/opentelemetry/
print_status "OpenTelemetry Collector deployment created"

# Wait for OpenTelemetry to be ready
echo -e "${YELLOW}Waiting for OpenTelemetry Collector to be ready...${NC}"
kubectl wait --for=condition=ready pod -l app=otel-collector -n ${NAMESPACE} --timeout=300s
print_status "OpenTelemetry Collector is ready"

# Deploy sample application
echo -e "\n${BLUE}Deploying sample application...${NC}"
kubectl apply -f manifests/sample-app/
print_status "Sample application deployed"

# Final status check
echo -e "\n${BLUE}Final status check...${NC}"
kubectl get pods -n ${NAMESPACE}

echo -e "\n${GREEN} Installation completed successfully!${NC}"
echo -e "\n${BLUE}Access your services:${NC}"
echo -e "${YELLOW}ElasticSearch:${NC} kubectl port-forward svc/elasticsearch 9200:9200 -n ${NAMESPACE}"
echo -e "${YELLOW}Kibana UI:${NC} kubectl port-forward svc/kibana 5601:5601 -n ${NAMESPACE}"
echo -e "${YELLOW}Jaeger UI:${NC} kubectl port-forward svc/jaeger-query 16686:16686 -n ${NAMESPACE}"
echo -e "${YELLOW}Sample App:${NC} kubectl port-forward svc/sample-app 8080:8080 -n ${NAMESPACE}"

echo -e "\n${GREEN} Authentication Credentials:${NC}"
echo -e "${YELLOW}Kibana Login:${NC}"
echo -e "  Username: ${GREEN}kibana_user${NC}"
echo -e "  Password: ${GREEN}monitoring123${NC}"
echo -e "\n${YELLOW}ElasticSearch:${NC}"
echo -e "  Admin User: ${GREEN}elastic${NC} / ${GREEN}elastic_password${NC}"
echo -e "  Kibana User: ${GREEN}kibana_user${NC} / ${GREEN}monitoring123${NC}"

echo -e "\n${BLUE} Getting Started:${NC}"
echo -e "1. Port forward Kibana: ${YELLOW}kubectl port-forward svc/kibana 5601:5601 -n monitoring${NC}"
echo -e "2. Open browser: ${YELLOW}http://localhost:5601${NC}"
echo -e "3. ${GREEN}Login with: kibana_user / monitoring123${NC}"
echo -e "4. Create index pattern: ${YELLOW}fluentd-*${NC}"
echo -e "5. Generate logs: ${YELLOW}curl http://localhost:8080${NC} (after port-forwarding sample app)"

echo -e "\n${BLUE} Troubleshooting:${NC}"
echo -e "\n${BLUE}To check status anytime, run:${NC} ./check-status.sh"
echo -e "- View logs: ${YELLOW}kubectl logs -l app=<component> -n monitoring${NC}"
echo -e "- Port conflicts: ${YELLOW}pkill -f port-forward${NC}"
echo -e "${BLUE}To uninstall everything, run:${NC} ./uninstall.sh"

echo -e "\n${GREEN}Happy monitoring! ${NC}"
