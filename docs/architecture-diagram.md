# Monitoring Stack Architecture

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          Kubernetes Cluster                                 │
│                                                                             │
│  ┌─────────────────┐   ┌─────────────────┐   ┌─────────────────┐            │
│  │   Sample App    │   │   Sample App    │   │   Sample App    │            │
│  │     Pod 1       │   │     Pod 2       │   │     Pod 3       │            │ 
│  │                 │   │                 │   │                 │            │ 
│  │ ┌─────────────┐ │   │ ┌─────────────┐ │   │ ┌─────────────┐ │            │
│  │ │   stdout    │ │   │ │   stdout    │ │   │ │   stdout    │ │            │
│  │ │   stderr    │ │   │ │   stderr    │ │   │ │   stderr    │ │            │
│  │ │    logs     │ │   │ │    logs     │ │   │ │    logs     │ │            │
│  │ └─────┬───────┘ │   │ └─────┬───────┘ │   │ └─────┬───────┘ │            │
│  └───────┼─────────┘   └───────┼─────────┘   └───────┼─────────┘            │
│          │                     │                     │                      │
│          │     ┌───────────────┼─────────────────────┼───────────────┐      │
│          │     │               │                     │               │      │
│          └─────▼───────────────▼─────────────────────▼──────────────▼┐      │
│                │              Fluentd DaemonSet                      │      │
│                │         (Runs on every node)                        │      │
│                │   • Collects logs from /var/log/containers/         │      │
│                │   • Adds Kubernetes metadata                        │      │
│                │   • Parses and structures log data                  │      │
│                └─────────────────────┬───────────────────────────────┘      │
│                                      │                                      │
│                                      ▼                                      │
│                ┌─────────────────────────────────────────────────────┐      │
│                │                ElasticSearch                        │      │
│                │                                                     │      │
│                │  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐    │      │
│                │  │   Index 1   │ │   Index 2   │ │   Index 3   │    │      │
│                │  │fluentd-2024 │ │fluentd-2024 │ │fluentd-2024 │    │      │
│                │  │    -01-01   │ │    -01-02   │ │    -01-03   │    │      │
│                │  └─────────────┘ └─────────────┘ └─────────────┘    │      │
│                │                                                     │      │
│                │  • Stores and indexes all logs                      │      │
│                │  • Provides search capabilities                     │      │
│                │  • Time-based indices for performance               │      │
│                └─────────────────────────────────────────────────────┘      │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                     Application Traces                              │    │
│  │                                                                     │    │
│  │  App → OpenTelemetry Agent → OpenTelemetry Collector → Jaeger       │    │
│  │                                                                     │    │
│  └─────────────────────────┬───────────────────────────────────────────┘    │
│                            │                                                │
│                            ▼                                                │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                OpenTelemetry Collector                              │    │
│  │                                                                     │    │
│  │  • Receives traces, metrics, and logs                               │    │
│  │  • Processes and enriches telemetry data                            │    │
│  │  • Routes data to appropriate backends                              │    │
│  │                                                                     │    │
│  │  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐              │    │
│  │  │  Receivers  │    │ Processors  │    │  Exporters  │              │    │
│  │  │             │    │             │    │             │              │    │
│  │  │ • OTLP      │───▶│ • Batch     │───▶│ • Jaeger    │              │    │
│  │  │ • Prometheus│    │ • Resource  │    │ • Prometheus│              │    │
│  │  │ • K8s Stats │    │ • Memory    │    │ • Logging   │              │    │
│  │  └─────────────┘    │   Limiter   │    └─────────────┘              │    │
│  │                     └─────────────┘                                 │    │
│  └─────────────────────────┬───────────────────────────────────────────┘    │
│                            │                                                │
│                            ▼                                                │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                         Jaeger                                      │    │
│  │                                                                     │    │
│  │  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐              │    │
│  │  │   Jaeger    │    │   Jaeger    │    │   Jaeger    │              │    │
│  │  │   Agent     │    │  Collector  │    │   Query     │              │    │
│  │  │             │    │             │    │             │              │    │
│  │  │ • Receives  │───▶│ • Processes │───▶│ • Query UI  │              │    │
│  │  │   traces    │    │   traces    │    │ • REST API  │              │    │
│  │  │ • Batches   │    │ • Stores in │    │ • Search &  │              │    │
│  │  │   data      │    │   memory    │    │   analyze   │              │    │
│  │  └─────────────┘    └─────────────┘    └─────────────┘              │    │
│  │                                                                     │    │
│  │  • Distributed tracing system                                       │    │
│  │  • Track request flows across services                              │    │
│  │  • Identify performance bottlenecks                                 │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Data Flow

### 1. Log Collection Flow
```
Application Pods → stdout/stderr → Container Runtime → 
/var/log/containers/*.log → Fluentd → ElasticSearch
```

### 2. Trace Collection Flow
```
Application → OpenTelemetry SDK → OpenTelemetry Collector → 
Jaeger Collector → Jaeger Storage → Jaeger Query UI
```

### 3. Metrics Collection Flow
```
Kubernetes API → OpenTelemetry Collector → Prometheus Exporter → 
External Prometheus (or internal metrics endpoint)
```

## User Access Points

```
┌─────────────────────────────────────────────────────────────────┐
│                    User Access Methods                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────┐    ┌─────────────────┐    ┌───────────────┐│
│  │  ElasticSearch  │    │    Jaeger UI    │    │   Sample App  ││
│  │     (Logs)      │    │    (Traces)     │    │    (Demo)     ││
│  │                 │    │                 │    │               ││
│  │ Port Forward:   │    │ Port Forward:   │    │ Port Forward: ││
│  │ kubectl port-   │    │ kubectl port-   │    │ kubectl port- ││
│  │ forward svc/    │    │ forward svc/    │    │ forward svc/  ││
│  │ elasticsearch   │    │ jaeger-query    │    │ sample-app    ││
│  │ 9200:9200       │    │ 16686:16686     │    │ 8080:8080     ││
│  │                 │    │                 │    │               ││
│  │ Access:         │    │ Access:         │    │ Access:       ││
│  │ localhost:9200  │    │ localhost:16686 │    │ localhost:8080││
│  └─────────────────┘    └─────────────────┘    └───────────────┘│
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## What Each Component Monitors

### ElasticSearch + Fluentd (Logs)
- Application stdout/stderr
- Container logs
- Kubernetes events
- System logs
- Error messages
- Access logs
- Custom application logs

### Jaeger (Traces)
- Request traces across services
- Service dependencies
- Performance bottlenecks
- Error propagation
- Latency analysis
- Service maps

### OpenTelemetry (Metrics + Coordination)
- Application metrics
- Infrastructure metrics
- Custom business metrics
- Resource utilization
- Error rates
- Request throughput

## Example Monitoring Scenario

```
User makes request to Sample App
         │
         ▼
┌─────────────────────────────────────────────────────────────────┐
│ 1. Request hits Sample App                                      │
│    • Nginx access log generated → Fluentd → ElasticSearch       │
│    • OpenTelemetry span created → OTel Collector → Jaeger       │
│    • Metrics updated → OTel Collector → Prometheus endpoint     │
├─────────────────────────────────────────────────────────────────┤
│ 2. User can now:                                                │
│    • Search logs in ElasticSearch for this request              │
│    • View trace in Jaeger UI to see request flow                │
│    • Check metrics for response time and error rate             │
├─────────────────────────────────────────────────────────────────┤
│ 3. If something goes wrong:                                     │
│    • Error logs appear in ElasticSearch                         │
│    • Failed spans show up in Jaeger with error tags             │
│    • Error metrics spike in OpenTelemetry                       │
└─────────────────────────────────────────────────────────────────┘
```

This architecture provides complete observability into your Kubernetes applications!
