#!/bin/sh
set -e

if [ -z "$1" ] || [ -z "$2" ]; then
  echo "Error: FLOW_ID and API_KEY arguments are required!" >&2
  exit 1
fi

FLOW_ID=$1
API_KEY=$2
# Worker counts to test. Feel free to adjust this list.
WORKER_COUNTS="1 1 2 3 4 8 12 16 32"
BEST_WORKERS=0
MAX_RPS=0.0

echo "Benchmark Job Started. Target Flow ID: $FLOW_ID"

for workers in $WORKER_COUNTS; do
  echo "\n--- Testing with $workers workers ---"

  echo "Patching ConfigMap to set LANGFLOW_WORKERS=$workers..."
  kubectl patch configmap langflow-config --patch "{\"data\":{\"LANGFLOW_WORKERS\":\"$workers\"}}"

  echo "Restarting Langflow deployment..."
  kubectl rollout restart deployment/langflow
  echo "Waiting for rollout to complete..."
  kubectl rollout status deployment/langflow --timeout=180s

  echo "Running load test against internal service (http://langflow:7860)..."
  RESULT=$(hey -z 30s -c 10 -disable-keepalive -H "x-api-key: $API_KEY" -m POST -d '{"input_value":"hello"}' "http://langflow:7860/api/v1/run/$FLOW_ID?stream=false")
  RPS=$(echo "$RESULT" | awk '/Requests\/sec:/ {print $2}')

  echo "Result: $RPS Requests/sec"

  if [ $(echo "$RPS > $MAX_RPS" | bc) -eq 1 ]; then
    MAX_RPS=$RPS
    BEST_WORKERS=$workers
    echo "New best result found!"
  fi
done

echo "\n--- Benchmark Finished ---"
echo "Optimal worker count: $BEST_WORKERS ($MAX_RPS Requests/sec)"

echo "Patching ConfigMap with final optimal worker count: $BEST_WORKERS"
kubectl patch configmap langflow-config --patch "{\"data\":{\"LANGFLOW_WORKERS\":\"$BEST_WORKERS\"}}"

# Write the result to the hostPath volume for the Makefile to retrieve
echo "$BEST_WORKERS" > /workspace/.optimal_workers

echo "Benchmark complete. Result saved."