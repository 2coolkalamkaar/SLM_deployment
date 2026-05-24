#!/bin/bash
# 1. Install Dependencies
curl -fsSL https://install.iii.dev/iii/main/install.sh | sh
cp /root/.local/bin/iii /usr/local/bin/
apt-get update && apt-get install -y git npm nodejs

# 2. Get Application Code
git clone https://github.com/Alchemyst-ai/hiring.git /opt/hiring
cd /opt/hiring/may-2026/devops/quickstart/workers/caller-worker
npm install

# 3. Create Systemd Service for Central Engine
cat << 'EOF' > /etc/systemd/system/iii-engine.service
[Unit]
Description=III Mesh Central Engine
After=network.target

[Service]
ExecStart=/usr/local/bin/iii --use-default-config
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

# 4. Create Systemd Service for Caller Worker
cat << 'EOF' > /etc/systemd/system/caller-worker.service
[Unit]
Description=TypeScript Caller Worker
After=iii-engine.service

[Service]
WorkingDirectory=/opt/hiring/may-2026/devops/quickstart/workers/caller-worker
Environment="PORT=3111"
Environment="III_URL=ws://localhost:49134"
ExecStart=/usr/bin/npm run dev
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

# 5. Enable and Start Services
systemctl daemon-reload
systemctl enable iii-engine caller-worker
systemctl start iii-engine caller-worker
