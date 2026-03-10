FROM python:3.12-slim

WORKDIR /app

COPY backend/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY backend/ ./backend/
COPY frontend/ ./frontend/

ENV PORT=8080

CMD gunicorn --bind "0.0.0.0:${PORT}" --workers 2 --timeout 120 backend.app:app
