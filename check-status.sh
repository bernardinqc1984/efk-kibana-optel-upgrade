#!/bin/bash

# Kubernetes Monitoring Stack Status Checker
# ElasticSearch + Fluentd + Jaeger + OpenTelemetry

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="observability"

echo -e "${BLUE} Kubernetes Monitoring Stack Status${NC}"
echo -e "${BLUE}====================================${NC}"

# Function to print status
print_status() {
    echo -e "${GREEN} $1${NC}"
}

print_warning() {
    echo -e "${YELLOW} $1${NC}"
}

print_error() {
    echo -e "${RED} $1${NC}"
}

print_info() {
    echo -e "${CYAN}  $1${NC}"
}

# Check if namespace exists
if ! kubectl get namespace ${NAMESPACE} &> /dev/null; then
    print_error "Namespace '${NAMESPACE}' does not exist. Please run ./install.sh first."
    exit 1
fi

print_status "Namespace '${NAMESPACE}' exists"

# Function to check pod status
check_pod_status() {
    local app_name=$1
    local display_name=$2
    
    echo -e "\n${PURPLE}Checking ${display_name}...${NC}"
    
    # Get pod information
    PODS=$(kubectl get pods -n ${NAMESPACE} -l app=${app_name} --no-headers 2>/dev/null || echo "")
    
    if [ -z "$PODS" ]; then
        print_error "${display_name}: No pods found"
        return 1
    fi
    
    # Check each pod
    while IFS= read -r line; do
        if [ -n "$line" ]; then
            POD_NAME=$(echo $line | awk '{print $1}')
            POD_STATUS=$(echo $line | awk '{print $3}')
            READY=$(echo $line | awk '{print $2}')
            
            if [ "$POD_STATUS" = "Running" ]; then
                print_status "${display_name}: ${POD_NAME} is running (${READY})"
            else
                print_warning "${display_name}: ${POD_NAME} is ${POD_STATUS} (${READY})"
            fi
        fi
    done <<< "$PODS"
}

# Function to check service status
check_service_status() {
    local service_name=$1
    local display_name=$2
    
    if kubectl get service ${service_name} -n ${NAMESPACE} &> /dev/null; then
        SERVICE_INFO=$(kubectl get service ${service_name} -n ${NAMESPACE} --no-headers)
        print_status "${display_name} service: ${SERVICE_INFO}"
    else
        print_error "${display_name} service not found"
    fi
}

# Check ElasticSearch
check_pod_status "elasticsearch" "ElasticSearch"
check_service_status "elasticsearch" "ElasticSearch"

# Check Fluentd
check_pod_status "fluentd" "Fluentd"

# Check Kibana
check_pod_status "kibana" "Kibana"
check_service_status "kibana" "Kibana"

# Check Jaeger
check_pod_status "jaeger" "Jaeger"
check_service_status "jaeger-query" "Jaeger Query"

# Check OpenTelemetry Collector
check_pod_status "otel-collector" "OpenTelemetry Collector"
check_service_status "otel-collector" "OpenTelemetry"

# Check Sample App
check_pod_status "sample-app" "Sample Application"
check_service_status "sample-app" "Sample App"

# Overall pod status
echo -e "\n${PURPLE}Overall Pod Status:${NC}"
kubectl get pods -n ${NAMESPACE}

# Check persistent volumes
echo -e "\n${PURPLE}Persistent Volumes:${NC}"
kubectl get pv | grep ${NAMESPACE} || print_info "No persistent volumes found"

# Check persistent volume claims
echo -e "\n${PURPLE}Persistent Volume Claims:${NC}"
kubectl get pvc -n ${NAMESPACE} || print_info "No persistent volume claims found"

# Service endpoints
echo -e "\n${PURPLE}Service Endpoints:${NC}"
kubectl get svc -n ${NAMESPACE}

# Check ElasticSearch health (if running)
echo -e "\n${PURPLE}ElasticSearch Health Check:${NC}"
ES_POD=$(kubectl get pods -n ${NAMESPACE} -l app=elasticsearch --no-headers | head -1 | awk '{print $1}' 2>/dev/null || echo "")
if [ -n "$ES_POD" ]; then
    ES_STATUS=$(kubectl exec -n ${NAMESPACE} ${ES_POD} -- curl -s http://localhost:9200/_cluster/health 2>/dev/null || echo "Could not connect")
    if [[ "$ES_STATUS" == *"\"status\":\"green\""* ]]; then
        print_status "ElasticSearch cluster health: GREEN"
    elif [[ "$ES_STATUS" == *"\"status\":\"yellow\""* ]]; then
        print_warning "ElasticSearch cluster health: YELLOW"
    elif [[ "$ES_STATUS" == *"\"status\":\"red\""* ]]; then
        print_error "ElasticSearch cluster health: RED"
    else
        print_warning "ElasticSearch health check failed"
    fi
else
    print_warning "No ElasticSearch pods found for health check"
fi

# Check ElasticSearch indices
echo -e "\n${PURPLE}ElasticSearch Indices:${NC}"
if [ -n "$ES_POD" ]; then
    INDICES=$(kubectl exec -n ${NAMESPACE} ${ES_POD} -- curl -s http://localhost:9200/_cat/indices 2>/dev/null || echo "Could not retrieve indices")
    if [[ "$INDICES" == *"fluentd"* ]]; then
        print_status "Fluentd indices found in ElasticSearch"
        echo "$INDICES" | grep fluentd
    else
        print_warning "No Fluentd indices found yet (may take a few minutes after startup)"
    fi
else
    print_warning "Cannot check indices - ElasticSearch pod not available"
fi

# Resource usage
echo -e "\n${PURPLE}Resource Usage:${NC}"
kubectl top pods -n ${NAMESPACE} 2>/dev/null || print_info "Metrics server not available for resource usage"

# Connection instructions
echo -e "\n${BLUE} Access Instructions:${NC}"
echo -e "${YELLOW}ElasticSearch:${NC}"
echo -e "  kubectl port-forward svc/elasticsearch 9200:9200 -n ${NAMESPACE}"
echo -e "  Then visit: http://localhost:9200"

echo -e "\n${YELLOW}Kibana UI:${NC}"
echo -e "  kubectl port-forward svc/kibana 5601:5601 -n ${NAMESPACE}"
echo -e "  Then visit: http://localhost:5601"

echo -e "\n${YELLOW}Jaeger UI:${NC}"
echo -e "  kubectl port-forward svc/jaeger-query 16686:16686 -n ${NAMESPACE}"
echo -e "  Then visit: http://localhost:16686"

echo -e "\n${YELLOW}Sample Application:${NC}"
echo -e "  kubectl port-forward svc/sample-app 8080:8080 -n ${NAMESPACE}"
echo -e "  Then visit: http://localhost:8080"

# Quick health summary
echo -e "\n${BLUE} Quick Health Summary:${NC}"

TOTAL_PODS=$(kubectl get pods -n ${NAMESPACE} --no-headers 2>/dev/null | wc -l)
RUNNING_PODS=$(kubectl get pods -n ${NAMESPACE} --no-headers 2>/dev/null | grep "Running" | wc -l)
READY_PODS=$(kubectl get pods -n ${NAMESPACE} --no-headers 2>/dev/null | awk '$2 ~ /1\/1|2\/2|3\/3/ {count++} END {print count+0}')

echo -e "Total Pods: ${TOTAL_PODS}"
echo -e "Running Pods: ${RUNNING_PODS}/${TOTAL_PODS}"
echo -e "Ready Pods: ${READY_PODS}/${TOTAL_PODS}"

if [ ${RUNNING_PODS} -eq ${TOTAL_PODS} ] && [ ${READY_PODS} -eq ${TOTAL_PODS} ]; then
    echo -e "\n${GREEN} All services are healthy and running!${NC}"
elif [ ${RUNNING_PODS} -gt 0 ]; then
    echo -e "\n${YELLOW}  Some services may still be starting up. Run this script again in a few minutes.${NC}"
else
    echo -e "\n${RED} Services are not running properly. Check the installation.${NC}"
fi

echo -e "\n${CYAN}For detailed logs of any component:${NC}"
echo -e "kubectl logs -f deployment/<component-name> -n ${NAMESPACE}"
echo -e "\n${CYAN}For troubleshooting, check:${NC} docs/troubleshooting.md"
