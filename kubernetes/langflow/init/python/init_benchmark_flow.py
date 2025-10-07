import os
import sys
import time
import requests

# FINAL VERSION - This script correctly prepares the benchmark environment.
# 1. Logs in as the superuser.
# 2. Creates a dedicated API key for the benchmark.
# 3. Creates a new flow with a non-cacheable 0.5s sleeper component.
# 4. Prints BOTH the FLOW_ID and the generated API_KEY for the Makefile.

LANGFLOW_URL = os.getenv("LANGFLOW_URL", "http://localhost:7860").rstrip("/")
USERNAME = os.getenv("LANGFLOW_SUPERUSER")
PASSWORD = os.getenv("LANGFLOW_SUPERUSER_PASSWORD")

if not USERNAME or not PASSWORD:
    sys.exit("Error: Superuser credentials not set.")

def die(msg, err=None):
    """Prints a fatal error and exits."""
    details = f" | Details: {err}" if err else ""
    print(f"FATAL: {msg}{details}", file=sys.stderr)
    sys.exit(1)

# --- Step 1: Login ---
try:
    print("Benchmark Prep: Logging in as superuser...")
    login_data = {"username": USERNAME, "password": PASSWORD, "grant_type": "password"}
    resp = requests.post(
        f"{LANGFLOW_URL}/api/v1/login",
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        data=login_data
    )
    resp.raise_for_status()
    token = resp.json().get("access_token")
    if not token:
        die("Login successful, but no access_token was returned.")
    print("Benchmark Prep: Login successful.")
except Exception as e:
    die("Login failed", e)

headers = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}

# --- Step 2: Create a dedicated API Key for the benchmark ---
try:
    print("Benchmark Prep: Creating a dedicated API key...")
    key_payload = {"name": f"benchmark-key-{int(time.time())}"}
    resp = requests.post(f"{LANGFLOW_URL}/api/v1/api_key/", headers=headers, json=key_payload)
    resp.raise_for_status()
    api_key = resp.json().get("api_key")
    if not api_key:
        die("API key created, but the key itself was not returned.")
    print("Benchmark Prep: API key created successfully.")
except Exception as e:
    die("Failed to create API key", e)

# --- Step 3: Create the sleeper flow ---
flow_name = f"BENCHMARK_SLEEPER_{int(time.time())}"
SLEEPER_CODE = (
    "from langflow import CustomComponent\nimport time\n\n"
    "class SleeperComponent(CustomComponent):\n"
    '    display_name = "Sleeper"\n'
    '    description = "Waits for 0.5s and returns a unique value."\n\n'
    "    def build(self, input_value: str) -> str:\n"
    "        time.sleep(0.5)\n"
    "        return f'{input_value} - {time.time_ns()}'"
)
flow_payload = {
    "name": flow_name,
    "data": {
        "nodes": [
            {"id": "input", "data": {"node": {"template": {"_type": "ChatInput"}}, "type": "ChatInput"}},
            {"id": "sleeper", "data": {"node": {"template": {"code": {"type": "code", "value": SLEEPER_CODE}, "_type": "CustomComponent"}}, "type": "CustomComponent"}},
            {"id": "output", "data": {"node": {"template": {"_type": "ChatOutput"}}, "type": "ChatOutput"}},
        ],
        "edges": [
            {"source": "input", "sourceHandle": "text", "target": "sleeper", "targetHandle": "input_value"},
            {"source": "sleeper", "sourceHandle": "text", "target": "output", "targetHandle": "text"},
        ],
    },
}
try:
    print(f"Benchmark Prep: Creating flow '{flow_name}'...")
    resp = requests.post(f"{LANGFLOW_URL}/api/v1/flows/", headers=headers, json=flow_payload)
    resp.raise_for_status()
    flow_id = resp.json().get("id")
    if not flow_id:
        die("Flow created, but no ID was returned.")
    print(f"Benchmark Prep: Flow created with ID: {flow_id}")
except Exception as e:
    die("Flow creation failed", e)

# --- Step 4: Output data for the Makefile ---
print(f"BENCHMARK_DATA:FLOW_ID={flow_id}")
print(f"BENCHMARK_DATA:API_KEY={api_key}")
