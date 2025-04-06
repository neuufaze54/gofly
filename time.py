import requests
from datetime import datetime
import time

# Correct FastAPI server endpoint
FASTAPI_SERVER_URL = "https://fe38ebf6-c57e-4ba5-b241-eef83b85ea53.deepnoteproject.com/upload"

def get_current_datetime():
    """Returns current date and time as string."""
    return datetime.now().strftime("%Y-%m-%d %H:%M:%S")

def send_datetime_to_server():
    """Send the current datetime to the FastAPI server, overwriting the previous one."""
    payload = {"link": get_current_datetime()}
    attempt = 0

    while True:
        try:
            response = requests.post(FASTAPI_SERVER_URL, json=payload)
            if response.status_code == 200:
                print("✅ Current time uploaded successfully!")
                break
            else:
                print(f"❌ Failed to send (status code {response.status_code}). Retrying...")
        except requests.RequestException as e:
            print(f"🌐 Network error: {e}. Retrying...")

        attempt += 1
        time.sleep(5)

if __name__ == "__main__":
    send_datetime_to_server()
