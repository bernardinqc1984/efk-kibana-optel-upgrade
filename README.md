# Kubernetes Monitoring Stack: ElasticSearch + Fluentd + Jaeger + OpenTelemetry

## Overview

This project provides a complete monitoring and observability stack for Kubernetes clusters, combining:
- **ElasticSearch**: Search and analytics engine for log storage
- **Fluentd**: Log collection and forwarding
- **Jaeger**: Distributed tracing system
- **OpenTelemetry**: Observability framework for metrics, logs, and traces

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                           │
├─────────────────────────────────────────────────────────────────┤
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐       │
│  │  Sample App  │    │  Sample App  │    │  Sample App  │       │
│  │    Pod 1     │    │    Pod 2     │    │    Pod 3     │       │
│  └──────┬───────┘    └──────┬───────┘    └──────┬───────┘       │
│         │                   │                   │               │
│         └───────────────────┼───────────────────┘               │
│                             │                                   │
│  ┌─────────────────────────┬┴──────────────────────────┐        │
│  │                    Fluentd DaemonSet                │        │
│  │         (Collects logs from all pods)               │        │
│  └─────────────────────────┬───────────────────────────┘        │
│                             │                                   │
│  ┌─────────────────────────┴───────────────────────────┐        │
│  │                  ElasticSearch                      │        │
│  │            (Stores and indexes logs)                │        │
│  └─────────────────────────────────────────────────────┘        │
│                                                                 │
│  ┌─────────────────────────────────────────────────────┐        │
│  │                     Jaeger                          │        │
│  │         (Distributed tracing storage)               │        │
│  └─────────────────────────────────────────────────────┘        │
│                                                                 │
│  ┌─────────────────────────────────────────────────────┐        │
│  │                OpenTelemetry Collector              │        │
│  │    (Collects metrics, traces, and telemetry)        │        │
│  └─────────────────────────────────────────────────────┘        │
└─────────────────────────────────────────────────────────────────┘
```

## Components Breakdown

### 1. ElasticSearch
- **Purpose**: Stores and indexes all your application logs
- **What it does**: Think of it as a super-fast search engine for your logs
- **Why we need it**: Instead of manually checking each pod's logs, ElasticSearch lets you search across ALL logs instantly

### 2. Fluentd
- **Purpose**: Collects logs from all pods and sends them to ElasticSearch
- **What it does**: Like a mail carrier that picks up logs from every house (pod) and delivers them to the post office (ElasticSearch)
- **Why we need it**: Kubernetes pods generate logs that disappear when pods restart. Fluentd saves them permanently.

### 3. Jaeger
- **Purpose**: Tracks how requests travel through your application
- **What it does**: Like a GPS tracker that shows the complete journey of a user request across multiple services
- **Why we need it**: Helps find bottlenecks and errors in distributed applications

### 4. OpenTelemetry
- **Purpose**: Standardized way to collect observability data
- **What it does**: Like a universal translator that speaks to all monitoring tools
- **Why we need it**: Provides consistent telemetry data collection across different technologies

## Quick Start

### Prerequisites
- Kubernetes cluster (v1.20+)
- kubectl configured
- Helm 3.x installed
- At least 4GB RAM available in cluster

### Installation

```bash
# Make scripts executable
chmod +x install.sh uninstall.sh check-status.sh

# Install the complete monitoring stack
./install.sh

# Check installation status
./check-status.sh

# View ElasticSearch indices
kubectl port-forward svc/elasticsearch 9200:9200 -n observability
curl http://localhost:9200/_cat/indices
```

### Uninstallation

```bash
./uninstall.sh
```

## Use Case Example: E-commerce Application Monitoring

Imagine you have an e-commerce application with these services:
- **Frontend**: User interface
- **API Gateway**: Routes requests
- **User Service**: Handles authentication
- **Product Service**: Manages product catalog
- **Order Service**: Processes orders
- **Payment Service**: Handles payments

### How Our Stack Helps:

1. **Logs with Fluentd + ElasticSearch**:
   - When a user can't log in, search logs for "authentication failed"
   - Find all payment errors in the last hour
   - Track which products are causing crashes

2. **Traces with Jaeger**:
   - See the complete journey of a purchase request
   - Identify which service is slow (maybe Payment Service takes 5 seconds)
   - Find where errors occur in the request chain

3. **Metrics with OpenTelemetry**:
   - Monitor response times for each service
   - Track memory and CPU usage
   - Set up alerts for high error rates

## Project Structure

```
├── README.md                      # This file
├── install.sh                     # Installation script
├── uninstall.sh                   # Cleanup script
├── check-status.sh                # Status checker
├── manifests/
│   ├── namespace.yaml             # Observability namespace
│   ├── elasticsearch/             # ElasticSearch deployment
│   ├── fluentd/                   # Fluentd configuration
│   ├── jaeger/                    # Jaeger tracing setup
│   ├── opentelemetry/             # OpenTelemetry collector
│   └── sample-app/                # Demo application
├── configs/
│   ├── fluentd-config.yaml        # Fluentd configuration
│   ├── otel-config.yaml           # OpenTelemetry config
│   └── elasticsearch-index.json   # ES index template
└── docs/
    ├── troubleshooting.md         # Common issues
    └── advanced-config.md         # Advanced configurations
```

## Accessing Services

After installation, access the services:

### ElasticSearch
```bash
kubectl port-forward svc/elasticsearch 9200:9200 -n observability
# Open http://localhost:9200 in browser
```

### Jaeger UI
```bash
kubectl port-forward svc/jaeger-query 16686:16686 -n observability
# Open http://localhost:16686 in browser
```

### Sample Application
```bash
kubectl port-forward svc/sample-app 8080:8080 -n observability
# Open http://localhost:8080 in browser
```

## Monitoring Dashboard

Once everything is running, you can:

1. **View Logs**: Search application logs in ElasticSearch
2. **Trace Requests**: Follow request paths in Jaeger UI
3. **Monitor Metrics**: View performance metrics through OpenTelemetry

## Customization

### Adding Your Application

1. Add OpenTelemetry instrumentation to your app
2. Configure your app to send logs to stdout
3. Fluentd will automatically collect and forward logs
4. Update the `sample-app` configuration with your app details

### Custom Log Parsing

Edit `configs/fluentd-config.yaml` to add custom log parsing rules for your application format.

## Troubleshooting

### Common Issues

1. **Pods not starting**: Check resource limits
   ```bash
   kubectl describe pod <pod-name> -n observability
   ```

2. **No logs in ElasticSearch**: Verify Fluentd configuration
   ```bash
   kubectl logs -f daemonset/fluentd -n observability
   ```

3. **Jaeger not receiving traces**: Check OpenTelemetry collector
   ```bash
   kubectl logs -f deployment/otel-collector -n observability
   ```

## Learning Resources

- [ElasticSearch Documentation](https://www.elastic.co/guide/en/elasticsearch/reference/current/index.html)
- [Fluentd Documentation](https://docs.fluentd.org/)
- [Jaeger Documentation](https://www.jaegertracing.io/docs/)
- [OpenTelemetry Documentation](https://opentelemetry.io/docs/)

## Contributing

Feel free to submit issues and enhancement requests!

## License

This project is licensed under the MIT License.
