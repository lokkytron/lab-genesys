#!/bin/bash

# Si SCRIPT_DIR no está definido, usar ruta relativa al script actual
if [ -z "$SCRIPT_DIR" ]; then
  SCRIPT_DIR="$(dirname "$(realpath "$0")")/.."
  echo "SCRIPT_DIR no estaba definido. Usando: $SCRIPT_DIR"
fi

KUBE_DIR="$SCRIPT_DIR/infra/kubernetes"

# 1. Namespace Telemetry
kubectl create namespace telemetry

# 2. Prometheus
kubectl  apply -f $KUBE_DIR/prometheus/prometheus-rbac.yaml
kubectl  apply -f $KUBE_DIR/prometheus/prometheus-configmap.yaml
kubectl  apply -f $KUBE_DIR/prometheus/prometheus-alertrules.yaml
kubectl  apply -f $KUBE_DIR/prometheus/prometheus-service.yaml
kubectl  apply -f $KUBE_DIR/prometheus/prometheus-statefullset.yaml
kubectl  apply -f $KUBE_DIR/prometheus/prometheus-ingress.yaml

# 3. Alertmanager
kubectl  apply -f $KUBE_DIR/alert-manager/alertmanager-rbac.yaml
kubectl  apply -f $KUBE_DIR/alert-manager/alertmanager-webhook.yaml
kubectl  apply -f $KUBE_DIR/alert-manager/alertmanager-configmap.yaml
kubectl  apply -f $KUBE_DIR/alert-manager/alertmanager-service.yaml
kubectl  apply -f $KUBE_DIR/alert-manager/alertmanager-deployment.yaml
kubectl  apply -f $KUBE_DIR/alert-manager/alertmanager-transformer.yaml

# 4. Kube State Metrics
kubectl  apply -f $KUBE_DIR/kube-state-metrics/kubestatemetrics-rbac.yaml
kubectl  apply -f $KUBE_DIR/kube-state-metrics/kubestatemetrics-service.yaml
kubectl  apply -f $KUBE_DIR/kube-state-metrics/kubestatemetrics-deployment.yaml

# 5. Node Exporter
kubectl  apply -f $KUBE_DIR/node-exporter/nodeexporter-service.yaml
kubectl  apply -f $KUBE_DIR/node-exporter/nodeexporter-daemonset.yaml

# 6. Loki
kubectl  apply -f $KUBE_DIR/loki/loki-configmap.yaml
kubectl  apply -f $KUBE_DIR/loki/loki-statefullset.yaml

# 7.Esperar a que el Service de Loki esté disponible
echo "Esperando a que el Service de Loki esté disponible..."

# 8. Obtener ClusterIP de Loki y exportar variable
while true; do
  LOKI_CLUSTERIP=$(kubectl get svc loki -n telemetry -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
  if [[ -n "$LOKI_CLUSTERIP" ]]; then
    echo "Service Loki disponible en IP: $LOKI_CLUSTERIP"
    break
  fi
  echo "Aún no disponible... esperando 2s"
  sleep 2
done

export LOKI_CLUSTERIP
echo "LOKI_IP=$LOKI_CLUSTERIP"

# 9. Generar promtail-configmap.yaml desde template usando envsubst
envsubst < $KUBE_DIR/promtail/promtail-configmap.yaml.template > $KUBE_DIR/promtail/promtail-configmap.yaml

# 10. Promtail
kubectl  apply -f $KUBE_DIR/promtail/promtail-rbac.yaml
kubectl  apply -f $KUBE_DIR/promtail/promtail-configmap.yaml
kubectl  apply -f $KUBE_DIR/promtail/promtail-daemonset.yaml

# 11. Grafana
kubectl  apply -f $KUBE_DIR/grafana/grafana-serviceaccount.yaml
kubectl  apply -f $KUBE_DIR/grafana/grafana-providers.yaml
kubectl  apply -f $KUBE_DIR/grafana/grafana-datasources.yaml
kubectl  apply -f $KUBE_DIR/grafana/grafana-persistentvolumeclaim.yaml
kubectl  apply -f $KUBE_DIR/grafana/grafana-deployment.yaml
kubectl  apply -f $KUBE_DIR/grafana/grafana-service.yaml
kubectl  apply -f $KUBE_DIR/grafana/grafana-ingress.yaml

# 12. Dashboards aquí (si se cargan como configmaps o por API)
# Se puede usar la API de Grafana o montar los JSON como configmaps si se tiene automatizado
for f in $KUBE_DIR/grafana/grafana-dashboards/*.json; do
  name=$(basename "$f" .json)
  kubectl create configmap grafana-dashboard-$name \
    --from-file="$name.json=$f" \
    -n telemetry
done

echo ""
echo "✅ Namespace telemetry deployed."
