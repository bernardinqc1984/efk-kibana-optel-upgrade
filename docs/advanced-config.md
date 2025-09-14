# Advanced Configuration Guide

## Advanced Setup Options

### ElasticSearch Advanced Configuration

#### Multi-Node ElasticSearch Cluster
For production environments, consider running a multi-node cluster:

```yaml
# elasticsearch-cluster.yaml
apiVersion: elasticsearch.k8s.elastic.co/v1
kind: Elasticsearch
metadata:
  name: monitoring-cluster
  namespace: monitoring
spec:
  version: 8.5.1
  nodeSets:
  - name: master
    count: 3
    config:
      node.roles: ["master"]
      xpack.security.enabled: false
    volumeClaimTemplates:
    - metadata:
        name: elasticsearch-data
      spec:
        accessModes:
        - ReadWriteOnce
        resources:
          requests:
            storage: 20Gi
        storageClassName: fast-ssd
  - name: data
    count: 3
    config:
      node.roles: ["data", "ingest"]
      xpack.security.enabled: false
    volumeClaimTemplates:
    - metadata:
        name: elasticsearch-data
      spec:
        accessModes:
        - ReadWriteOnce
        resources:
          requests:
            storage: 100Gi
        storageClassName: fast-ssd
```

#### Custom Index Lifecycle Management
```json
{
  "policy": {
    "phases": {
      "hot": {
        "actions": {
          "rollover": {
            "max_size": "50GB",
            "max_age": "1d"
          }
        }
      },
      "warm": {
        "min_age": "7d",
        "actions": {
          "allocate": {
            "number_of_replicas": 0
          }
        }
      },
      "delete": {
        "min_age": "30d"
      }
    }
  }
}
```

### Fluentd Advanced Configuration

#### Custom Log Parsing
Add custom parsers for different application log formats:

```ruby
# Custom parser for JSON logs
<filter kubernetes.**>
  @type parser
  key_name log
  reserve_data true
  <parse>
    @type json
    time_key timestamp
    time_format %Y-%m-%dT%H:%M:%S.%NZ
  </parse>
</filter>

# Custom parser for structured logs
<filter kubernetes.var.log.containers.my-app**>
  @type parser
  key_name log
  <parse>
    @type regexp
    expression /^(?<timestamp>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}) \[(?<level>\w+)\] (?<message>.*)$/
    time_key timestamp
    time_format %Y-%m-%d %H:%M:%S
  </parse>
</filter>

# Multi-line log support for stack traces
<filter kubernetes.**>
  @type concat
  key log
  stream_identity_key stream
  multiline_start_regexp /^\d{4}-\d{2}-\d{2}/
  flush_interval 5s
  timeout_label "@NORMAL"
</filter>
```

#### Log Routing and Filtering
```ruby
# Route different namespaces to different indices
<match kubernetes.var.log.containers.**kube-system**>
  @type elasticsearch
  host elasticsearch
  port 9200
  index_name k8s-system-logs
  type_name _doc
</match>

<match kubernetes.var.log.containers.**production**>
  @type elasticsearch
  host elasticsearch
  port 9200
  index_name production-logs
  type_name _doc
</match>

# Filter out noisy logs
<filter kubernetes.**>
  @type grep
  <exclude>
    key log
    pattern /health|ping|heartbeat/i
  </exclude>
</filter>
```

### Jaeger Advanced Configuration

#### Jaeger with ElasticSearch Backend
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: jaeger-elasticsearch
  namespace: monitoring
spec:
  replicas: 1
  selector:
    matchLabels:
      app: jaeger
  template:
    metadata:
      labels:
        app: jaeger
    spec:
      containers:
      - name: jaeger-collector
        image: jaegertracing/jaeger-collector:1.41.0
        args:
        - "--es.server-urls=http://elasticsearch:9200"
        - "--es.num-shards=5"
        - "--es.num-replicas=1"
        - "--collector.zipkin.host-port=:9411"
        ports:
        - containerPort: 14267
        - containerPort: 14268
        - containerPort: 9411
        env:
        - name: SPAN_STORAGE_TYPE
          value: elasticsearch
      - name: jaeger-query
        image: jaegertracing/jaeger-query:1.41.0
        args:
        - "--es.server-urls=http://elasticsearch:9200"
        ports:
        - containerPort: 16686
        env:
        - name: SPAN_STORAGE_TYPE
          value: elasticsearch
```

#### Custom Sampling Configuration
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: jaeger-sampling-config
  namespace: monitoring
data:
  sampling.json: |
    {
      "service_strategies": [
        {
          "service": "sample-app",
          "type": "probabilistic",
          "param": 1.0
        },
        {
          "service": "high-volume-service",
          "type": "probabilistic",
          "param": 0.1
        }
      ],
      "default_strategy": {
        "type": "probabilistic",
        "param": 0.5
      }
    }
```

### OpenTelemetry Advanced Configuration

#### Custom Instrumentation Library Configuration
```yaml
receivers:
  prometheus:
    config:
      scrape_configs:
      - job_name: 'kubernetes-pods'
        kubernetes_sd_configs:
        - role: pod
        relabel_configs:
        - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
          action: keep
          regex: true
        - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
          action: replace
          target_label: __metrics_path__
          regex: (.+)

  k8s_events:
    auth_type: serviceAccount
    
  k8s_cluster:
    auth_type: serviceAccount
    node: ${K8S_NODE_NAME}
    collection_interval: 10s
    
processors:
  # Resource detection for better context
  resourcedetection:
    detectors: [env, system, k8snode]
    timeout: 5s
    
  # Attributes processor for custom labels
  attributes:
    actions:
    - key: environment
      value: production
      action: upsert
    - key: cluster.name
      value: monitoring-cluster
      action: upsert
      
  # Span processor for trace sampling
  probabilistic_sampler:
    sampling_percentage: 50
    
  # Memory ballast for stability
  memory_ballast:
    size_mib: 165
```

#### Custom Metrics and Dashboards
```yaml
# Custom receiver for application metrics
receivers:
  httpcheck:
    targets:
    - endpoint: http://sample-app:8080/health
      method: GET
    collection_interval: 30s
    
  redis:
    endpoint: redis:6379
    collection_interval: 10s
    
  mysql:
    endpoint: mysql:3306
    username: monitor
    password: ${MYSQL_PASSWORD}
    database: myapp
    collection_interval: 10s
```

### Security Configurations

#### RBAC for Monitoring Components
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: monitoring-reader
rules:
- apiGroups: [""]
  resources: ["nodes", "nodes/metrics", "services", "endpoints", "pods"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["apps"]
  resources: ["deployments", "daemonsets", "replicasets", "statefulsets"]
  verbs: ["get", "list", "watch"]
- nonResourceURLs: ["/metrics"]
  verbs: ["get"]
```

#### Network Policies
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: monitoring-network-policy
  namespace: monitoring
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: monitoring
    ports:
    - protocol: TCP
      port: 9200  # ElasticSearch
    - protocol: TCP
      port: 16686 # Jaeger
  egress:
  - to: []
    ports:
    - protocol: TCP
      port: 53   # DNS
    - protocol: UDP
      port: 53   # DNS
```

### Performance Tuning

#### ElasticSearch Performance
```yaml
env:
- name: ES_JAVA_OPTS
  value: "-Xms2g -Xmx2g -XX:+UseG1GC"
- name: indices.memory.index_buffer_size
  value: "30%"
- name: thread_pool.write.queue_size
  value: "1000"
resources:
  requests:
    memory: "4Gi"
    cpu: "1"
  limits:
    memory: "4Gi"
    cpu: "2"
```

#### Fluentd Performance
```ruby
# Buffer configuration for high throughput
<buffer>
  @type file
  path /var/log/fluentd-buffers/kubernetes.buffer
  flush_mode interval
  flush_interval 5s
  flush_thread_count 8
  chunk_limit_size 8MB
  total_limit_size 1GB
  retry_max_interval 30
  retry_forever true
  overflow_action block
</buffer>

# System configuration
<system>
  workers 4
  root_dir /tmp/fluentd
  log_level warn
  suppress_repeated_stacktrace true
</system>
```

### Monitoring the Monitoring Stack

#### Prometheus Metrics for Components
```yaml
# ServiceMonitor for monitoring ElasticSearch
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: elasticsearch-metrics
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app: elasticsearch
  endpoints:
  - port: http
    path: /_prometheus/metrics
    interval: 30s
```

#### Alerting Rules
```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: monitoring-alerts
  namespace: monitoring
spec:
  groups:
  - name: elasticsearch
    rules:
    - alert: ElasticSearchClusterHealthRed
      expr: elasticsearch_cluster_health_status{color="red"} == 1
      for: 5m
      labels:
        severity: critical
      annotations:
        summary: "ElasticSearch cluster health is RED"
    
    - alert: ElasticSearchDiskSpaceHigh
      expr: elasticsearch_filesystem_data_free_bytes / elasticsearch_filesystem_data_size_bytes < 0.1
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "ElasticSearch disk space is running low"
```

### Backup and Recovery

#### ElasticSearch Snapshot Configuration
```bash
# Create snapshot repository
curl -X PUT "elasticsearch:9200/_snapshot/backup" -H 'Content-Type: application/json' -d'
{
  "type": "fs",
  "settings": {
    "location": "/usr/share/elasticsearch/backup"
  }
}'

# Create automated backup policy
curl -X PUT "elasticsearch:9200/_slm/policy/daily-backup" -H 'Content-Type: application/json' -d'
{
  "schedule": "0 2 * * *",
  "name": "<daily-backup-{now/d}>",
  "repository": "backup",
  "config": {
    "indices": ["fluentd-*"],
    "ignore_unavailable": false,
    "include_global_state": false
  },
  "retention": {
    "expire_after": "30d",
    "min_count": 5,
    "max_count": 50
  }
}'
```

### Integration with External Systems

#### Slack Notifications
```yaml
# AlertManager configuration for Slack
route:
  group_by: ['alertname']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 1h
  receiver: 'slack-notifications'

receivers:
- name: 'slack-notifications'
  slack_configs:
  - api_url: 'YOUR_SLACK_WEBHOOK_URL'
    channel: '#monitoring'
    title: 'Monitoring Alert'
    text: '{{ range .Alerts }}{{ .Annotations.summary }}{{ end }}'
```

#### External Log Forwarding
```ruby
# Forward logs to external systems
<match **>
  @type copy
  <store>
    @type elasticsearch
    host elasticsearch
    port 9200
  </store>
  <store>
    @type s3
    aws_key_id YOUR_AWS_KEY
    aws_sec_key YOUR_AWS_SECRET
    s3_bucket monitoring-logs
    s3_region us-west-2
    path logs/
    buffer_type file
    buffer_path /var/log/fluent/s3
    time_slice_format %Y%m%d%H
    time_slice_wait 10m
  </store>
</match>
```
