import logging
import os
from flask import Flask, request, jsonify
from prometheus_flask_exporter import PrometheusMetrics

log_dir = "/var/log/app"
os.makedirs(log_dir, exist_ok=True)

logging.basicConfig(
    filename=f"{log_dir}/app.log",
    format='%(asctime)s - %(levelname)s - %(message)s',
    level=logging.INFO
)

app = Flask(__name__)
metrics = PrometheusMetrics(app)

@app.route("/", methods=["GET"])
def home():
    app.logger.info("GET request received")
    return "Hello from the app!"

@app.route("/data", methods=["POST"])
def data():
    content = request.json
    if not content:
        app.logger.warning("No JSON received")
        return jsonify({"error": "Missing JSON"}), 400
    if "error" in content:
        app.logger.error("Received error in request")
        return jsonify({"error": "Simulated error"}), 500
    app.logger.info(f"Received data: {content}")
    return jsonify({"status": "OK"}), 200

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
