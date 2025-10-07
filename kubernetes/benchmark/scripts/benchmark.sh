#!/bin/sh
set -e

if [ -z "$1" ] || [ -z "$2" ]; then
  echo "Error: FLOW_ID and API_KEY arguments are required!" >&2
  exit 1
fi

FLOW_ID=$1
API_KEY=$2

echo "Running a single diagnostic request to check the 422 error..."

curl -v -X POST \
  -H "Content-Type: application/json" \
  -H "x-api-key: $API_KEY" \
  -d '{"inputs": {"input_value": "hello"}}' \
  "http://langflow:7860/api/v1/run/$FLOW_ID?stream=false"

echo "\n\nDiagnostic run finished. Check the response body above for the validation error."

##!/bin/sh
#set -e
#
#if [ -z "$1" ] || [ -z "$2" ]; then
#  echo "Error: FLOW_ID and API_KEY arguments are required!" >&2
#  exit 1
#fi
#
#FLOW_ID=$1
#API_KEY=$2
## Worker counts to test. Feel free to adjust this list.
#WORKER_COUNTS="1 1 2 3 4 8 12 16 32"
#BEST_WORKERS=0
#MAX_RPS=0.0
#
#echo "Benchmark Job Started. Target Flow ID: $FLOW_ID"
#
#for workers in $WORKER_COUNTS; do
#  echo "\n--- Testing with $workers workers ---"
#
#  echo "Patching ConfigMap to set LANGFLOW_WORKERS=$workers..."
#  kubectl patch configmap langflow-config --patch "{\"data\":{\"LANGFLOW_WORKERS\":\"$workers\"}}"
#
#  echo "Restarting Langflow deployment..."
#  kubectl rollout restart deployment/langflow
#  echo "Waiting for rollout to complete..."
#  kubectl rollout status deployment/langflow --timeout=180s
#
#  echo "Waiting for pod to be ready..."
#  kubectl wait --for=condition=ready pod -l app=langflow --timeout=60s
#
#  echo "testing workers..."
#  # Temporarily disable exit-on-error for worker check
#  set +e
#
#  CONFIGURED_WORKERS=$(kubectl get configmap langflow-config -o jsonpath='{.data.LANGFLOW_WORKERS}' 2>/dev/null)
#  if [ -z "$CONFIGURED_WORKERS" ]; then
#    CONFIGURED_WORKERS="Not Set"
#  fi
#
#  LANGFLOW_POD=$(kubectl get pods -l app=langflow -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
#
#  echo "Configured workers (in ConfigMap): $CONFIGURED_WORKERS"
#
#  if [ -n "$LANGFLOW_POD" ]; then
#    echo "Found pod: $LANGFLOW_POD"
#    RUNNING_PROCESSES=$(kubectl exec "$LANGFLOW_POD" -- sh -c "ps -ef | grep '[g]unicorn' | wc -l" 2>/dev/null | tr -d '[:space:]')
#
#    if [ -n "$RUNNING_PROCESSES" ] && [ "$RUNNING_PROCESSES" -gt "0" ] 2>/dev/null; then
#      RUNNING_WORKERS=$((RUNNING_PROCESSES - 1))
#      echo "Running Gunicorn master + workers (in pod): $RUNNING_PROCESSES"
#      echo "Actual running worker processes: $RUNNING_WORKERS"
#    else
#      echo "Could not count running processes"
#    fi
#  else
#    echo "Langflow pod not found"
#  fi
#
#  # Re-enable exit-on-error
#  set -e
#
#  echo "Running load test against internal service (http://langflow:7860)..."
#  JSON_PAYLOAD='{"inputs": {"input_value": "hello"}}'
#  RESULT=$(hey -z 30s -c 10 -disable-keepalive -H "x-api-key: $API_KEY" -m POST -d "$JSON_PAYLOAD" "http://langflow:7860/api/v1/run/$FLOW_ID?stream=false")
#
#  echo "--- Full 'hey' command output: ---"
#  echo "$RESULT"
#  echo "------------------------------------"
#
#  RPS=$(echo "$RESULT" | awk '/Requests\/sec:/ {print $2}')
#
#  echo "Result: $RPS Requests/sec"
#
#  ERROR_COUNT=$(echo "$RESULT" | awk '/\[5..\]/ {sum+=$2} END {print sum}')
#  if [ -z "$ERROR_COUNT" ]; then
#    ERROR_COUNT=0
#  fi
#
#  if [ $(echo "$RPS > $MAX_RPS" | bc) -eq 1 ] && [ $ERROR_COUNT -eq 0 ]; then
#    MAX_RPS=$RPS
#    BEST_WORKERS=$workers
#    echo "New best result found!"
#  fi
#done
#
#echo "\n--- Benchmark Finished ---"
#echo "Optimal worker count: $BEST_WORKERS ($MAX_RPS Requests/sec)"
#
#echo "Patching ConfigMap with final optimal worker count: $BEST_WORKERS"
#kubectl patch configmap langflow-config --patch "{\"data\":{\"LANGFLOW_WORKERS\":\"$BEST_WORKERS\"}}"
#
## Write the result to the hostPath volume for the Makefile to retrieve
#echo "$BEST_WORKERS" > /workspace/.optimal_workers
#
#echo "Benchmark complete. Result saved."