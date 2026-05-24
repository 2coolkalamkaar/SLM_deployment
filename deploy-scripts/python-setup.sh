#!/bin/bash
# 1. Prevent OOM by creating 8GB Swap immediately
fallocate -l 8G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab

# 2. Install Dependencies
apt-get update && apt-get install -y python3-venv python3-pip git
git clone https://github.com/Alchemyst-ai/hiring.git /opt/hiring
cd /opt/hiring/may-2026/devops/quickstart/workers/inference-worker

# 3. Setup Virtual Environment safely
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
pip install iii-sdk

mkdir -p pip_tmp
TMPDIR=$(pwd)/pip_tmp pip install --no-cache-dir transformers accelerate gguf torch

# 4. Create Systemd Service for Inference Worker
cat << EOF > /etc/systemd/system/inference-worker.service
[Unit]
Description=Python AI Inference Worker
After=network.target

[Service]
WorkingDirectory=/opt/hiring/may-2026/devops/quickstart/workers/inference-worker
# Terraform injects the TS Hub IP dynamically here
Environment="III_URL=ws://${TS_PRIVATE_IP}:49134"
ExecStart=/opt/hiring/may-2026/devops/quickstart/workers/inference-worker/venv/bin/python inference_worker.py
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

# 5. Enable and Start Service
systemctl daemon-reload
systemctl enable inference-worker
systemctl start inference-worker
