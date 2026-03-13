import os
import json
import datetime
import functools

import jwt
import google.auth
import google.auth.transport.requests
import requests
from werkzeug.security import check_password_hash
from flask import Flask, request, jsonify, send_from_directory, Response, stream_with_context, session, redirect, url_for

app = Flask(__name__, static_folder="../frontend")
app.secret_key = os.environ.get("APP_SECRET_KEY", "dev-secret-key-change-me")
app.permanent_session_lifetime = datetime.timedelta(minutes=10)

GCP_PROJECT = os.environ.get("GCP_PROJECT", "bmika-cfcd")
GCP_REGION = os.environ.get("GCP_REGION", "us-west1")
GEMINI_REGION = os.environ.get("GEMINI_REGION", "us-central1")
GEMINI_MODEL = os.environ.get("GEMINI_MODEL", "gemini-2.5-flash-lite")

APP_USERNAME = os.environ.get("APP_USERNAME", "test")
APP_PASSWORD_HASH = os.environ.get("APP_PASSWORD_HASH", "")

OAUTH_CLIENT_ID = os.environ.get("OAUTH_CLIENT_ID", "")
OAUTH_CLIENT_SECRET = os.environ.get("OAUTH_CLIENT_SECRET", "")

SYSTEM_PROMPT = "You are a helpful assistant. Keep every response to 3 sentences or fewer."


# ── Auth helpers ─────────────────────────────────────────────────────

def login_required(f):
    @functools.wraps(f)
    def decorated(*args, **kwargs):
        if session.get("logged_in"):
            return f(*args, **kwargs)
        return redirect(url_for("login_page"))
    return decorated


def _verify_bearer_token():
    """Return True if the request carries a valid Bearer JWT."""
    auth_header = request.headers.get("Authorization", "")
    if not auth_header.startswith("Bearer "):
        return False
    token = auth_header[len("Bearer "):]
    try:
        jwt.decode(token, app.secret_key, algorithms=["HS256"])
        return True
    except jwt.InvalidTokenError:
        return False


def _get_credentials():
    credentials, _ = google.auth.default(
        scopes=["https://www.googleapis.com/auth/cloud-platform"]
    )
    credentials.refresh(google.auth.transport.requests.Request())
    return credentials


# ── Gemini streaming ─────────────────────────────────────────────────

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


# ── OAuth 2.0 token endpoint ────────────────────────────────────────

@app.route("/oauth2/token", methods=["POST"])
def oauth2_token():
    data = request.get_json(silent=True) or {}
    grant_type = data.get("grant_type", "")
    client_id = data.get("client_id", "")
    client_secret = data.get("client_secret", "")

    if grant_type != "client_credentials":
        return jsonify({"error": "unsupported_grant_type"}), 400

    if not OAUTH_CLIENT_ID or not OAUTH_CLIENT_SECRET:
        return jsonify({"error": "server_misconfigured"}), 500

    if client_id != OAUTH_CLIENT_ID or client_secret != OAUTH_CLIENT_SECRET:
        return jsonify({"error": "invalid_client"}), 401

    now = datetime.datetime.now(datetime.timezone.utc)
    payload = {
        "sub": client_id,
        "iat": now,
        "exp": now + datetime.timedelta(minutes=10),
    }
    access_token = jwt.encode(payload, app.secret_key, algorithm="HS256")

    return jsonify({
        "access_token": access_token,
        "token_type": "bearer",
        "expires_in": 600,
    })


# ── Session login / logout ──────────────────────────────────────────

@app.route("/login", methods=["GET"])
def login_page():
    if session.get("logged_in"):
        return redirect(url_for("index"))
    return send_from_directory(app.static_folder, "login.html")


@app.route("/login", methods=["POST"])
def login_submit():
    data = request.get_json(silent=True) or {}
    username = data.get("username", "")
    password = data.get("password", "")

    if username == APP_USERNAME and APP_PASSWORD_HASH and check_password_hash(APP_PASSWORD_HASH, password):
        session.permanent = True
        session["logged_in"] = True
        return jsonify({"ok": True})
    return jsonify({"error": "Invalid credentials"}), 401


@app.route("/logout")
def logout():
    session.clear()
    return redirect(url_for("login_page"))


# ── Page routes ──────────────────────────────────────────────────────

@app.route("/")
@login_required
def index():
    return send_from_directory(app.static_folder, "index.html")


@app.route("/<path:path>")
def static_files(path):
    if path == "login.html" or path.startswith("css/") or path.startswith("js/") or path == "favicon.svg":
        return send_from_directory(app.static_folder, path)
    if not session.get("logged_in"):
        return redirect(url_for("login_page"))
    return send_from_directory(app.static_folder, path)


@app.route("/health")
def health():
    return jsonify({"status": "ok"})


# ── Chat API ─────────────────────────────────────────────────────────

@app.route("/api/chat", methods=["POST"])
def chat():
    if not _verify_bearer_token() and not session.get("logged_in"):
        return jsonify({"error": "Unauthorized"}), 401

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
