# Troubleshooting Guide

## Common Issues and Solutions

### ElasticSearch Issues

#### ElasticSearch Pod Not Starting
**Symptoms:** Pod stuck in `Pending` or `CrashLoopBackOff`

**Solutions:**
```bash
# Check pod events
kubectl describe pod <elasticsearch-pod-name> -n monitoring

# Common fixes:
# 1. Increase vm.max_map_count on nodes
sudo sysctl -w vm.max_map_count=262144

# 2. Check storage availability
kubectl get pv
kubectl get pvc -n monitoring

# 3. Check resource limits
kubectl top nodes
```

#### ElasticSearch Health is Yellow/Red
**Symptoms:** Cluster health not green

**Solutions:**
```bash
# Check cluster health
kubectl port-forward svc/elasticsearch 9200:9200 -n monitoring &
curl http://localhost:9200/_cluster/health?pretty

# Check indices
curl http://localhost:9200/_cat/indices?v

# Fix unassigned shards (single node cluster)
curl -X PUT "localhost:9200/_settings" -H 'Content-Type: application/json' -d'
{
  "index": {
    "number_of_replicas": 0
  }
}'
```

### Fluentd Issues

#### Fluentd Not Collecting Logs
**Symptoms:** No logs appearing in ElasticSearch

**Solutions:**
```bash
# Check Fluentd logs
kubectl logs -f daemonset/fluentd -n monitoring

# Check if pods have log files
kubectl exec -it <any-pod> -- ls -la /var/log/containers/

# Verify ElasticSearch connectivity
kubectl exec -it <fluentd-pod> -n monitoring -- curl elasticsearch:9200
```

#### Fluentd Parse Errors
**Symptoms:** Logs with parse errors in Fluentd

**Solutions:**
```bash
# Check the log format in your applications
kubectl logs <app-pod> | head -5

# Update Fluentd config for custom log formats
# Edit manifests/fluentd/fluentd.yaml
```

### Jaeger Issues

#### Jaeger UI Not Accessible
**Symptoms:** Cannot access Jaeger UI

**Solutions:**
```bash
# Check if Jaeger is running
kubectl get pods -n monitoring -l app=jaeger

# Port forward to access UI
kubectl port-forward svc/jaeger-query 16686:16686 -n monitoring

# Check service endpoints
kubectl get endpoints jaeger-query -n monitoring
```

#### No Traces in Jaeger
**Symptoms:** Jaeger UI shows no traces

**Solutions:**
```bash
# Check if applications are sending traces
kubectl logs -f deployment/otel-collector -n monitoring

# Verify OpenTelemetry configuration
kubectl describe configmap otel-collector-config -n monitoring

# Test with sample trace
curl -X POST http://localhost:4318/v1/traces \
  -H "Content-Type: application/json" \
  -d '{"resourceSpans":[{"spans":[{"traceId":"test","spanId":"test","name":"test"}]}]}'
```

### OpenTelemetry Issues

#### OpenTelemetry Collector Not Starting
**Symptoms:** OTel collector pod failing

**Solutions:**
```bash
# Check configuration syntax
kubectl logs -f deployment/otel-collector -n monitoring

# Validate YAML syntax
kubectl get configmap otel-collector-config -n monitoring -o yaml

# Check resource limits
kubectl describe pod <otel-collector-pod> -n monitoring
```

#### Metrics Not Being Collected
**Symptoms:** No metrics in Prometheus endpoint

**Solutions:**
```bash
# Check Prometheus endpoint
kubectl port-forward svc/otel-collector 8889:8889 -n monitoring &
curl http://localhost:8889/metrics

# Verify receivers are working
kubectl port-forward svc/otel-collector 55679:55679 -n monitoring &
# Visit http://localhost:55679 for zPages
```

### Sample Application Issues

#### Sample App Not Accessible
**Symptoms:** Cannot access sample application

**Solutions:**
```bash
# Check if pods are running
kubectl get pods -n monitoring -l app=sample-app

# Port forward to access app
kubectl port-forward svc/sample-app 8080:8080 -n monitoring

# Check service configuration
kubectl describe svc sample-app -n monitoring
```

### General Debugging Commands

#### Check All Resources
```bash
# Get overview of all resources
kubectl get all -n monitoring

# Check events in namespace
kubectl get events -n monitoring --sort-by=.metadata.creationTimestamp

# Check resource usage
kubectl top pods -n monitoring
kubectl top nodes
```

#### Network Connectivity Tests
```bash
# Test DNS resolution
kubectl run test-pod --image=busybox -n monitoring --rm -it -- nslookup elasticsearch

# Test service connectivity
kubectl run test-pod --image=busybox -n monitoring --rm -it -- wget -qO- http://elasticsearch:9200
```

#### Logs and Diagnostics
```bash
# Get logs from all pods
kubectl logs -l app=elasticsearch -n monitoring
kubectl logs -l app=fluentd -n monitoring
kubectl logs -l app=jaeger -n monitoring
kubectl logs -l app=otel-collector -n monitoring

# Describe problematic pods
kubectl describe pod <pod-name> -n monitoring
```

### Emergency Recovery

#### Complete Reset
```bash
# If everything is broken, reset the entire stack
./uninstall.sh
kubectl delete namespace monitoring --force --grace-period=0
./install.sh
```

#### Partial Reset
```bash
# Reset specific components
kubectl delete deployment elasticsearch -n monitoring
kubectl apply -f manifests/elasticsearch/

# Reset data
kubectl delete pvc --all -n monitoring
```

### Getting Help

If you're still having issues:

1. **Check the logs** first - they usually contain the answer
2. **Verify resource limits** - ensure your cluster has enough resources
3. **Check network policies** - ensure pods can communicate
4. **Review configuration** - validate YAML syntax and values
5. **Search online** - look for similar issues in community forums

### Useful Monitoring Queries

#### ElasticSearch Queries
```bash
# Search for errors in logs
curl "localhost:9200/fluentd-*/_search?pretty" -H 'Content-Type: application/json' -d'
{
  "query": {
    "match": {
      "log": "error"
    }
  }
}'

# Get logs from specific namespace
curl "localhost:9200/fluentd-*/_search?pretty" -H 'Content-Type: application/json' -d'
{
  "query": {
    "term": {
      "kubernetes.namespace_name": "monitoring"
    }
  }
}'
```

#### Sample Application Test Endpoints
```bash
# Generate different types of logs
curl http://localhost:8080/           # Normal access
curl http://localhost:8080/health     # Health check
curl http://localhost:8080/slow       # Slow request
curl http://localhost:8080/error      # Error generation
```
