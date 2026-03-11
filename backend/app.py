import os
import json

import google.auth
import google.auth.transport.requests
import requests
from flask import Flask, request, jsonify, send_from_directory, Response, stream_with_context

app = Flask(__name__, static_folder="../frontend")

GCP_PROJECT = os.environ.get("GCP_PROJECT", "bmika-cfcd")
GCP_REGION = os.environ.get("GCP_REGION", "us-west1")
GEMINI_REGION = os.environ.get("GEMINI_REGION", "us-central1")
GEMINI_MODEL = os.environ.get("GEMINI_MODEL", "gemini-2.0-flash")

SYSTEM_PROMPT = "You are a helpful assistant. Keep every response to 3 sentences or fewer."


def _get_credentials():
    credentials, _ = google.auth.default(
        scopes=["https://www.googleapis.com/auth/cloud-platform"]
    )
    credentials.refresh(google.auth.transport.requests.Request())
    return credentials


def stream_gemini(user_text):
    """Stream tokens from Gemini via Vertex AI streamGenerateContent."""
    credentials = _get_credentials()

    endpoint_url = (
        f"https://{GEMINI_REGION}-aiplatform.googleapis.com/v1/"
        f"projects/{GCP_PROJECT}/locations/{GEMINI_REGION}/"
        f"publishers/google/models/{GEMINI_MODEL}:streamGenerateContent?alt=sse"
    )

    payload = {
        "contents": [{"role": "user", "parts": [{"text": user_text}]}],
        "systemInstruction": {"parts": [{"text": SYSTEM_PROMPT}]},
        "generationConfig": {"maxOutputTokens": 150},
    }

    resp = requests.post(
        endpoint_url,
        json=payload,
        headers={
            "Authorization": f"Bearer {credentials.token}",
            "Content-Type": "application/json",
        },
        timeout=120,
        stream=True,
    )

    if not resp.ok:
        app.logger.error("Gemini error (%s): %s", resp.status_code, resp.text[:500])
        yield f"data: {json.dumps({'error': 'Model inference failed'})}\n\n"
        yield "data: [DONE]\n\n"
        return

    for line in resp.iter_lines(decode_unicode=True):
        if not line or not line.startswith("data:"):
            continue
        data_str = line[len("data:"):].strip()
        if not data_str:
            continue
        try:
            chunk = json.loads(data_str)
            candidates = chunk.get("candidates", [])
            for candidate in candidates:
                parts = candidate.get("content", {}).get("parts", [])
                for part in parts:
                    text = part.get("text", "")
                    if text:
                        yield f"data: {json.dumps({'token': text})}\n\n"
        except json.JSONDecodeError:
            continue

    yield "data: [DONE]\n\n"


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

    if "messages" in data:
        user_msgs = [m for m in data["messages"] if m.get("role") == "user"]
        if not user_msgs:
            return jsonify({"error": "No user message found"}), 400
        user_text = user_msgs[-1].get("content", "")
    elif "message" in data:
        user_text = data["message"]
    else:
        return jsonify({"error": "Provide 'message' or 'messages'"}), 400

    try:
        return Response(
            stream_with_context(stream_gemini(user_text)),
            content_type="text/event-stream",
            headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
        )
    except Exception as e:
        app.logger.error("Unexpected error: %s", e)
        return jsonify({"error": "Internal server error"}), 500


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 8080)), debug=True)
