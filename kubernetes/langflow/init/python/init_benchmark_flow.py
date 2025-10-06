import os
import sys
import requests

# This script is solely for preparing the benchmark environment.
# It creates a simple flow and an API key, then prints their details for the benchmark script.

LANGFLOW_URL = os.getenv("LANGFLOW_URL", "http://localhost:7860")
USERNAME = os.getenv("LANGFLOW_SUPERUSER")
PASSWORD = os.getenv("LANGFLOW_SUPERUSER_PASSWORD")

if not USERNAME or not PASSWORD:
    print("Error: LANGFLOW_SUPERUSER or LANGFLOW_SUPERUSER_PASSWORD not set", file=sys.stderr)
    sys.exit(1)

# --- Step 1: Login to get access token ---
try:
    response = requests.post(
        f"{LANGFLOW_URL}/api/v1/login",
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        data={"username": USERNAME, "password": PASSWORD, "grant_type": "password"}
    )
    response.raise_for_status()
    ACCESS_TOKEN = response.json().get("access_token")
    if not ACCESS_TOKEN:
        raise ValueError("Could not get access token from login response.")
    print("Benchmark Prep: Got superuser access token.")
except Exception as e:
    print(f"Benchmark Prep: Login failed: {e}", file=sys.stderr)
    sys.exit(1)

headers = {"Authorization": f"Bearer {ACCESS_TOKEN}"}

# --- Step 2: Create a dedicated API key for benchmark ---
try:
    api_key_resp = requests.post(
        f"{LANGFLOW_URL}/api/v1/api_key/",
        headers=headers,
        json={"name": "benchmark_key"},
    )
    api_key_resp.raise_for_status()
    BENCHMARK_API_KEY = api_key_resp.json().get("api_key")
    if not BENCHMARK_API_KEY:
        raise ValueError("Could not get API key from response.")
    print(f"Benchmark Prep: Created a dedicated API key for testing.")
except Exception as e:
    print(f"Benchmark Prep: API key creation failed: {e}", file=sys.stderr)
    sys.exit(1)

# --- Step 3: Create a minimal "Demo Chatbot" flow for benchmarking ---
print("Benchmark Prep: Creating a new 'Demo Chatbot' for benchmark...")
new_flow_payload = {
    "name": "Demo Chatbot",
    "description": "A simple chatbot created automatically for benchmarking.",
    "data": { "nodes": [], "edges": [] }
}
try:
    create_response = requests.post(f"{LANGFLOW_URL}/api/v1/flows/", headers=headers, json=new_flow_payload)
    create_response.raise_for_status()
    BENCHMARK_FLOW_ID = create_response.json().get("id")
    if not BENCHMARK_FLOW_ID:
        raise ValueError("Could not get Flow ID from create response.")
    print(f"Benchmark Prep: Successfully created 'Demo Chatbot' with ID: {BENCHMARK_FLOW_ID}")
except Exception as e:
    print(f"Benchmark Prep: Failed to create 'Demo Chatbot'. Error: {e}", file=sys.stderr)
    sys.exit(1)

# --- Step 4: Output data for benchmark ---
if BENCHMARK_FLOW_ID and BENCHMARK_API_KEY:
    print(f"BENCHMARK_DATA:FLOW_ID={BENCHMARK_FLOW_ID}")
    print(f"BENCHMARK_DATA:API_KEY={BENCHMARK_API_KEY}")
