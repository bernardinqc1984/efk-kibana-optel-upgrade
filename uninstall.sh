#!/bin/bash

# Kubernetes Monitoring Stack Uninstaller
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

echo -e "${RED}  Uninstalling Kubernetes Monitoring Stack${NC}"
echo -e "${RED}===========================================${NC}"

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

# Confirmation prompt
echo -e "\n${YELLOW}This will remove ALL monitoring components from the '${NAMESPACE}' namespace.${NC}"
read -p "Are you sure you want to continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${BLUE}Uninstallation cancelled.${NC}"
    exit 0
fi

# Check if namespace exists
if ! kubectl get namespace ${NAMESPACE} &> /dev/null; then
    print_warning "Namespace '${NAMESPACE}' does not exist. Nothing to uninstall."
    exit 0
fi

echo -e "\n${BLUE}Starting uninstallation...${NC}"

# Remove sample application
echo -e "\n${BLUE}Removing sample application...${NC}"
kubectl delete -f manifests/sample-app/ --ignore-not-found=true
print_status "Sample application removed"

# Remove OpenTelemetry Collector
echo -e "\n${BLUE}Removing OpenTelemetry Collector...${NC}"
kubectl delete -f manifests/opentelemetry/ --ignore-not-found=true
print_status "OpenTelemetry Collector removed"

# Remove Jaeger
echo -e "\n${BLUE}Removing Jaeger...${NC}"
kubectl delete -f manifests/jaeger/ --ignore-not-found=true
print_status "Jaeger removed"

# Remove Kibana
echo -e "\n${BLUE}Removing Kibana...${NC}"
kubectl delete -f manifests/kibana/ --ignore-not-found=true
print_status "Kibana removed"

# Remove Fluentd
echo -e "\n${BLUE}Removing Fluentd...${NC}"
kubectl delete -f manifests/fluentd/ --ignore-not-found=true
print_status "Fluentd removed"

# Remove ElasticSearch
echo -e "\n${BLUE}Removing ElasticSearch...${NC}"
kubectl delete -f manifests/elasticsearch/ --ignore-not-found=true
print_status "ElasticSearch removed"

# Wait for pods to terminate
echo -e "\n${YELLOW}Waiting for pods to terminate...${NC}"
sleep 10

# Check if any pods are still running
REMAINING_PODS=$(kubectl get pods -n ${NAMESPACE} --no-headers 2>/dev/null | wc -l)
if [ ${REMAINING_PODS} -gt 0 ]; then
    echo -e "${YELLOW}Waiting for remaining pods to terminate...${NC}"
    kubectl wait --for=delete pod --all -n ${NAMESPACE} --timeout=120s || true
fi

# Remove persistent volumes and claims
echo -e "\n${BLUE}Removing persistent volumes and claims...${NC}"
kubectl delete pvc --all -n ${NAMESPACE} --ignore-not-found=true
print_status "Persistent volume claims removed"

# Remove the namespace
echo -e "\n${BLUE}Removing namespace...${NC}"
kubectl delete namespace ${NAMESPACE} --ignore-not-found=true
print_status "Namespace '${NAMESPACE}' removed"

# Remove Helm repositories (optional)
read -p "Do you want to remove the added Helm repositories? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo -e "\n${BLUE}Removing Helm repositories...${NC}"
    helm repo remove elastic 2>/dev/null || true
    helm repo remove jaegertracing 2>/dev/null || true
    helm repo remove open-telemetry 2>/dev/null || true
    print_status "Helm repositories removed"
fi

echo -e "\n${GREEN} Uninstallation completed successfully!${NC}"
echo -e "${BLUE}All monitoring components have been removed from your cluster.${NC}"

# Final cleanup verification
echo -e "\n${BLUE}Verifying cleanup...${NC}"
if kubectl get namespace ${NAMESPACE} &> /dev/null; then
    print_warning "Namespace still exists (may take a few moments to fully delete)"
else
    print_status "Namespace completely removed"
fi

echo -e "\n${GREEN}Cleanup complete! ${NC}"
