import os
import sys
import time
import requests

# Minimal initializer for a fresh benchmark setup:
# - logs in
# - ensures an API key named "benchmark_key"
# - creates a brand-new flow with an async 0.5s sleeper component
# - prints FLOW_ID and API_KEY for the benchmark runner

LANGFLOW_URL = os.getenv("LANGFLOW_URL", "http://localhost:7860").rstrip("/")
USERNAME = os.getenv("LANGFLOW_SUPERUSER")
PASSWORD = os.getenv("LANGFLOW_SUPERUSER_PASSWORD")

if not USERNAME or not PASSWORD:
    print("Error: LANGFLOW_SUPERUSER or LANGFLOW_SUPERUSER_PASSWORD not set", file=sys.stderr)
    sys.exit(1)

def die(msg, err=None):
    if err:
        print(f"{msg} | {err}", file=sys.stderr)
    else:
        print(msg, file=sys.stderr)
    sys.exit(1)

# 1) Login
try:
    resp = requests.post(
        f"{LANGFLOW_URL}/api/v1/login/access-token",
        data={"username": USERNAME, "password": PASSWORD},
        timeout=30,
    )
    resp.raise_for_status()
    token = resp.json().get("access_token")
    if not token:
        die("Login succeeded but no access_token in response.")
except Exception as e:
    die("Login failed.", e)

headers = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}

# 2) Ensure API key (create only; no listing/patching)
try:
    # Try to fetch keys; if none or name not found, create one.
    r = requests.get(f"{LANGFLOW_URL}/api/v1/api_key/", headers=headers, timeout=30)
    r.raise_for_status()
    api_keys = (r.json() or {}).get("api_keys", []) or []
    api_key = None
    for k in api_keys:
        if k.get("name") == "benchmark_key" and k.get("api_key"):
            api_key = k["api_key"]
            break
    if not api_key:
        r = requests.post(
            f"{LANGFLOW_URL}/api/v1/api_key/",
            headers=headers,
            json={"name": "benchmark_key"},
            timeout=30,
        )
        r.raise_for_status()
        data = r.json() or {}
        api_key = data.get("api_key") or data.get("key") or data.get("token")
    if not api_key:
        die("Could not obtain API key value.")
except Exception as e:
    die("API key ensure failed.", e)

# 3) Create a brand-new flow (no listing/updating; always unique name)
flow_name = f"BENCHMARK_SLEEP_500ms_{int(time.time())}"

ASYNC_CODE = (
    "from langflow.custom import CustomComponent\n"
    "import asyncio\n"
    "\n"
    "class Sleeper(CustomComponent):\n"
    '    display_name = "Sleeper"\n'
    '    description = "Waits for 0.5s then echoes the input."\n'
    "    inputs = [{\"name\": \"input_value\", \"type\": \"str\", \"required\": True}]\n"
    "    outputs = [{\"name\": \"text\", \"type\": \"str\", \"method\": \"run\"}]\n"
    "\n"
    "    async def run(self, input_value: str) -> str:\n"
    "        await asyncio.sleep(0.5)\n"
    "        return input_value\n"
)

flow_payload = {
    "name": flow_name,
    "description": "Benchmark flow with async 0.5s sleep.",
    "data": {
        "nodes": [
            {
                "id": "chat_input",
                "type": "chat_input",
                "data": {
                    "node": {
                        "template": {
                            "input_value": {"value": "", "type": "str"}
                        }
                    }
                },
                "position": {"x": 0, "y": 0},
            },
            {
                "id": "python_code",
                "type": "python_node",
                "data": {
                    "node": {
                        "template": {
                            "code": {"value": ASYNC_CODE, "type": "code"},
                            "input_value": {"value": "{{chat_input.input_value}}", "type": "str"},
                        }
                    }
                },
                "position": {"x": 400, "y": 0},
            },
            {
                "id": "chat_output",
                "type": "chat_output",
                "data": {
                    "node": {
                        "template": {
                            "output_value": {"value": "{{python_code.text}}", "type": "str"}
                        }
                    }
                },
                "position": {"x": 800, "y": 0},
            },
        ],
        "edges": [
            {"source": "chat_input", "target": "python_code"},
            {"source": "python_code", "target": "chat_output"},
        ],
    },
}

try:
    r = requests.post(
        f"{LANGFLOW_URL}/api/v1/flows/",
        headers=headers,
        json=flow_payload,
        timeout=30,
    )
    r.raise_for_status()
    j = r.json() or {}
    flow_id = j.get("id") or j.get("_id") or j.get("flow_id")
    if not flow_id:
        die("Flow created but no ID found in response.")
except Exception as e:
    die("Flow creation failed.", e)

# 4) Output for the benchmark job
print(f"BENCHMARK_DATA:FLOW_ID={flow_id}")
print(f"BENCHMARK_DATA:API_KEY={api_key}")
