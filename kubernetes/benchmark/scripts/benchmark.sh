#!/bin/sh
set -e

if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
  echo "Error: FLOW_ID, API_KEY and BENCHMARK_TYPE (hey|locust) arguments are required!" >&2
  exit 1
fi

FLOW_ID=$1
API_KEY=$2
BENCHMARK_TYPE=$3
export LANGFLOW_SERVER_URL="http://langflow:7860"

WORKER_COUNTS="1 2 4 8 16 32 64"
BEST_WORKERS=0
MAX_RPS=0.0
FAILURE_THRESHOLD=5

echo "Benchmark Job Started. Target Flow ID: $FLOW_ID. Test type: $BENCHMARK_TYPE"

for workers in $WORKER_COUNTS; do
  echo "\n--- Testing with $workers workers ---"

  echo "Patching ConfigMap to set WEB_CONCURRENCY=$workers..."
  kubectl patch configmap langflow-config --patch "{\"data\":{\"WEB_CONCURRENCY\":\"$workers\"}}"

  echo "Restarting Langflow deployment..."
  kubectl rollout restart deployment/langflow
  echo "Waiting for rollout to complete..."
  kubectl rollout status deployment/langflow --timeout=180s

  echo "Waiting for pod to be ready..."
  kubectl wait --for=condition=ready pod -l app=langflow --timeout=60s

  echo "Giving Langflow extra time to initialize..."
  sleep 15

  echo "Running load test..."

  if [ "$BENCHMARK_TYPE" = "hey" ]; then
    echo "Running HEY benchmark..."
    JSON_PAYLOAD='{"input_value": "hello", "input_type": "text", "output_type": "text"}'
    CONC=$(( workers * 25 ))
    RESULT=$(hey -z 30s -c $CONC -t 30 \
      -H "x-api-key: $API_KEY" -H "Content-Type: application/json" \
      -m POST -d "$JSON_PAYLOAD" \
      "$LANGFLOW_SERVER_URL/api/v1/run/$FLOW_ID?stream=false")
    RPS=$(echo "$RESULT" | awk '/Requests\/sec:/ {print $2}')

    HTTP_ERRORS=$(echo "$RESULT" | awk '/\[5..\]/ {sum+=$2} END {print sum+0}')
    OTHER_ERRORS=$(echo "$RESULT" | awk '/Error distribution:/,0' | grep -o '\[[0-9]\+]' | tr -d '[]' | awk '{s+=$1} END {print s+0}')
    ERROR_COUNT=$((HTTP_ERRORS + OTHER_ERRORS))

  elif [ "$BENCHMARK_TYPE" = "locust" ]; then
    echo "Running LOCUST benchmark..."
    export FLOW_ID
    export API_KEY
    CSV_PREFIX="locust_results_${workers}"

    RESULT=$(locust -f /app/locustfile.py --headless \
      --users $(( workers * 50 )) --spawn-rate $(( workers * 25 )) \
      -t 30s --host "$LANGFLOW_SERVER_URL" \
      --csv="$CSV_PREFIX" --exit-code-on-error 1)

    STATS_CSV_FILE="${CSV_PREFIX}_stats.csv"

    if [ -f "$STATS_CSV_FILE" ]; then
      RPS=$(cat "$STATS_CSV_FILE" | grep "Aggregated" | awk -F',' '{print $10}'); RPS=${RPS:-0}
      REQUEST_COUNT=$(cat "$STATS_CSV_FILE" | grep "Aggregated" | awk -F',' '{print $3}'); REQUEST_COUNT=${REQUEST_COUNT:-0}
      FAILURE_COUNT=$(cat "$STATS_CSV_FILE" | grep "Aggregated" | awk -F',' '{print $4}'); FAILURE_COUNT=${FAILURE_COUNT:-0}
      if [ "$REQUEST_COUNT" -eq 0 ]; then echo "System unresponsive. 0 requests completed."; ERROR_COUNT=9999; else ERROR_COUNT=$FAILURE_COUNT; fi
      echo "\n--- Content of ${STATS_CSV_FILE} ---"
      cat "$STATS_CSV_FILE"
      echo "----------------------------------------\n"
    else
      echo "Warning: Locust stats CSV file not found: $STATS_CSV_FILE. Assuming 0 RPS and high error count."
      RPS=0.0
      ERROR_COUNT=999
    fi

  else
    echo "Error: Unknown benchmark type '$BENCHMARK_TYPE'. Use 'hey' or 'locust'." >&2
    exit 1
  fi

  echo "--- Full Test Output: ---"
  echo "$RESULT"
  echo "-------------------------"

  if [ -z "$ERROR_COUNT" ]; then
    ERROR_COUNT=0
  fi

  echo "Result with $workers workers: $RPS Requests/sec, Errors: $ERROR_COUNT"

  if [ $(echo "$RPS > $MAX_RPS" | bc) -eq 1 ] && [ $(echo "$ERROR_COUNT == 0" | bc) -eq 1 ]; then
    MAX_RPS=$RPS
    BEST_WORKERS=$workers
    echo ">>> New best result found! <<<"
  fi

  if [ "$ERROR_COUNT" -gt "$FAILURE_THRESHOLD" ]; then
    echo "\n--- System overloaded at $workers workers (Errors: $ERROR_COUNT) ---"
    echo "Stopping benchmark prematurely."
    break
  fi

done

echo "\n--- Benchmark Finished ---"
echo "Optimal worker count: $BEST_WORKERS ($MAX_RPS Requests/sec)"

echo "Patching ConfigMap with final optimal worker count: $BEST_WORKERS"
kubectl patch configmap langflow-config --patch "{\"data\":{\"WEB_CONCURRENCY\":\"$BEST_WORKERS\"}}"

echo -n "$BEST_WORKERS" > .optimal_workers
echo "Benchmark complete. Result saved to .optimal_workers"
