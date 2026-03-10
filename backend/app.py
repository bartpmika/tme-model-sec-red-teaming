import os
import json

import google.auth
import google.auth.transport.requests
import requests
from flask import Flask, request, jsonify, send_from_directory

app = Flask(__name__, static_folder="../frontend")

GCP_PROJECT = os.environ.get("GCP_PROJECT", "bmika-cfcd")
GCP_REGION = os.environ.get("GCP_REGION", "us-west1")
VERTEX_ENDPOINT_ID = os.environ.get("VERTEX_ENDPOINT_ID", "")


def get_vertex_prediction(messages):
    """Send messages to the Vertex AI endpoint and return the response."""
    credentials, _ = google.auth.default(
        scopes=["https://www.googleapis.com/auth/cloud-platform"]
    )
    credentials.refresh(google.auth.transport.requests.Request())

    endpoint_url = (
        f"https://{GCP_REGION}-aiplatform.googleapis.com/v1/"
        f"projects/{GCP_PROJECT}/locations/{GCP_REGION}/"
        f"endpoints/{VERTEX_ENDPOINT_ID}:predict"
    )

    # Format for HuggingFace TGI on Vertex AI
    prompt = format_chat_prompt(messages)
    payload = {
        "instances": [{"inputs": prompt, "parameters": {"max_new_tokens": 512}}]
    }

    resp = requests.post(
        endpoint_url,
        json=payload,
        headers={
            "Authorization": f"Bearer {credentials.token}",
            "Content-Type": "application/json",
        },
        timeout=60,
    )
    resp.raise_for_status()
    data = resp.json()

    # Extract generated text from Vertex AI response
    predictions = data.get("predictions", [])
    if predictions:
        return predictions[0] if isinstance(predictions[0], str) else str(predictions[0])
    return "No response generated."


def format_chat_prompt(messages):
    """Format messages into TinyLlama chat template."""
    prompt = ""
    for msg in messages:
        role = msg.get("role", "user")
        content = msg.get("content", "")
        if role == "system":
            prompt += f"<|system|>\n{content}</s>\n"
        elif role == "user":
            prompt += f"<|user|>\n{content}</s>\n"
        elif role == "assistant":
            prompt += f"<|assistant|>\n{content}</s>\n"
    prompt += "<|assistant|>\n"
    return prompt


@app.route("/")
def index():
    return send_from_directory(app.static_folder, "index.html")


@app.route("/<path:path>")
def static_files(path):
    return send_from_directory(app.static_folder, path)


@app.route("/health")
def health():
    return jsonify({"status": "ok"})


@app.route("/api/chat", methods=["POST"])
def chat():
    data = request.get_json()
    if not data:
        return jsonify({"error": "Request body required"}), 400

    # Support both single message and messages array
    if "messages" in data:
        messages = data["messages"]
    elif "message" in data:
        messages = [{"role": "user", "content": data["message"]}]
    else:
        return jsonify({"error": "Provide 'message' or 'messages'"}), 400

    try:
        response_text = get_vertex_prediction(messages)
        return jsonify({"response": response_text})
    except requests.exceptions.HTTPError as e:
        app.logger.error("Vertex AI error: %s", e.response.text if e.response else e)
        return jsonify({"error": "Model inference failed"}), 502
    except Exception as e:
        app.logger.error("Unexpected error: %s", e)
        return jsonify({"error": "Internal server error"}), 500


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 8080)), debug=True)
