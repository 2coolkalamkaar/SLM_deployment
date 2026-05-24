# 🧠 Inference Mesh — AWS Infrastructure

A two-tier AI inference microservices stack deployed on AWS EC2, fronted by an Application Load Balancer and managed via Terraform.

---

## Architecture

```
                        ┌─────────────────────────────────────────────┐
                        │               AWS us-east-1                 │
                        │                                             │
  User / Client         │   ┌──────────────────────────────────────┐  │
  ─────────────         │   │    VPC: inference-mesh-vpc            │  │
  curl / HTTP    ──────►│   │    10.0.0.0/16                       │  │
                        │   │                                      │  │
                        │   │  ┌────────────────────────────────┐  │  │
                        │   │  │   Application Load Balancer     │  │  │
                        │   │  │   (inference-mesh-alb)          │  │  │
                        │   │  │   Port 80  ·  HTTP              │  │  │
                        │   │  │   Subnets: public_a + public_b  │  │  │
                        │   │  └───────────────┬────────────────┘  │  │
                        │   │                  │ port 3111          │  │
                        │   │                  ▼                    │  │
                        │   │  ┌────────────────────────────────┐  │  │
                        │   │  │   TypeScript Caller Worker      │  │  │
                        │   │  │   (typescript-caller-hub)       │  │  │
                        │   │  │   EC2 t2.micro · us-east-1a    │  │  │
                        │   │  │                                 │  │  │
                        │   │  │   ┌─────────────────────────┐  │  │  │
                        │   │  │   │  iii-engine (mesh hub)  │  │  │  │
                        │   │  │   │  Port 49134 (WebSocket) │  │  │  │
                        │   │  │   └────────────┬────────────┘  │  │  │
                        │   │  │                │               │  │  │
                        │   │  └────────────────│───────────────┘  │  │
                        │   │                   │ ws://             │  │
                        │   │            port 49134 (self SG)      │  │
                        │   │                   │                   │  │
                        │   │  ┌────────────────▼───────────────┐  │  │
                        │   │  │   Python Inference Worker       │  │  │
                        │   │  │   (python-inference-engine)     │  │  │
                        │   │  │   EC2 t3.medium · us-east-1a   │  │  │
                        │   │  │   30GB gp3  ·  8GB swap        │  │  │
                        │   │  │                                 │  │  │
                        │   │  │    AI Model (transformers)   │  │  │
                        │   │  │   inference_worker.py           │  │  │
                        │   │  └────────────────────────────────┘  │  │
                        │   └──────────────────────────────────────┘  │
                        └─────────────────────────────────────────────┘
```

### Traffic Flow

```
Client ──HTTP:80──► ALB ──HTTP:3111──► TypeScript Worker
                                              │
                                    ws://[PY_PRIVATE_IP]:49134
                                              │
                                              ▼
                                      Python AI Worker
                                    (inference_worker.py)
```

---

## Services

| Service | EC2 Type | Port | Role |
|---|---|---|---|
| **TypeScript Caller Worker** | `t3.medium` | `3111` (HTTP) | Receptionist — accepts OpenAI-style HTTP/JSON requests |
| **iii-engine** | _(runs on TS instance)_ | `49134` (WebSocket) | Mesh hub — routes messages between workers |
| **Python Inference Worker** | `t3.medium` | `49134` (WebSocket out) | Heavy lifter — loads AI model and generates text |

---

## Project Structure

```
SLM_deployment/
├── README.md
├── deploy-scripts/
│   ├── ts-setup.sh          # Bootstraps TypeScript caller worker + iii-engine
│   └── python-setup.sh      # Bootstraps Python AI inference worker
└── terraform/
    ├── main.tf              # All infrastructure: VPC, SGs, IAM, ALB, EC2
    ├── outputs.tf           # Post-apply values: IPs, instance IDs, SSM commands
    └── variables.tf         # Tuneable parameters with defaults
```

---

## Security Groups

| Group | Inbound | Source |
|---|---|---|
| `alb-sg` | Port 80 (HTTP) | `0.0.0.0/0` (internet) |
| `worker-sg` | Port 3111 (API) | `alb-sg` only |
| `worker-sg` | Port 49134 (mesh) | Self (internal EC2-to-EC2 only) |

---

## Prerequisites

### 1. AWS CLI Credentials

Terraform needs valid AWS credentials. Choose one method:

**Option A — Environment Variables (recommended for CI/quick use)**
```bash
export AWS_ACCESS_KEY_ID="YOUR_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="YOUR_SECRET_KEY"
export AWS_DEFAULT_REGION="us-east-1"
```

**Option B — AWS CLI Profile**
```bash
aws configure
# Enter your Access Key ID, Secret Key, region (us-east-1), output format (json)
```

**Option C — IAM Role (if running from an EC2 instance)**

No extra config needed — Terraform will auto-detect the instance role.

---

### 2. Terraform

Install Terraform (>= 1.5.0):

```bash
# Download binary directly (no sudo required)
TERRAFORM_VERSION="1.15.4"
curl -sLo /tmp/terraform.zip \
  "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip"

mkdir -p ~/bin
python3 -c "import zipfile; zipfile.ZipFile('/tmp/terraform.zip').extract('terraform', '$HOME/bin/')"
chmod +x ~/bin/terraform

# Add to PATH (add this to your ~/.bashrc for persistence)
export PATH="$HOME/bin:$PATH"

terraform version
```

---

## Setup Guide

### Step 1 — Clone this repo

```bash
git clone https://github.com/2coolkalamkaar/SLM_deployment.git
cd SLM_deployment
```

### Step 2 — Configure AWS credentials

See [Prerequisites](#1-aws-cli-credentials) above.

### Step 3 — Initialize Terraform

```bash
cd terraform/
terraform init
```

Expected output:
```
Terraform has been successfully initialized!
```

### Step 4 — Validate configuration

```bash
terraform validate
# Success! The configuration is valid.
```

### Step 5 — Preview the plan

Review exactly what Terraform will create before spending any money:

```bash
terraform plan
```

This will show **~10 resources** to be created:
- 1 VPC + 2 subnets + 1 IGW + 1 route table
- 2 security groups
- 1 IAM role + policy attachment + instance profile
- 1 ALB + 1 target group + 1 listener
- 2 EC2 instances

### Step 6 — Apply

```bash
terraform apply
```

Type `yes` when prompted. Provisioning takes ~2 minutes.

### Step 7 — Get the ALB URL

```bash
terraform output alb_dns_name
```

### Step 8 — Test the endpoint

Wait ~3–5 minutes after apply for the EC2 instances to finish bootstrapping, then:

```bash
ALB_DNS=$(terraform output -raw alb_dns_name)

curl -s http://${ALB_DNS}/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "default",
    "messages": [{"role": "user", "content": "Hello!"}]
  }' | jq .
```

---

## Instance Access (No SSH Key Required)

Instances use **AWS SSM Session Manager** — no key pair, no open port 22:

```bash
# Connect to the TypeScript worker
aws ssm start-session --target <ts-instance-id>

# Connect to the Python worker
aws ssm start-session --target <py-instance-id>

# Get instance IDs
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=typescript-caller-hub" \
  --query "Reservations[0].Instances[0].InstanceId" \
  --output text
```

---

## Checking Service Status on EC2

After connecting via SSM:

```bash
# TypeScript worker
systemctl status iii-engine
systemctl status caller-worker
journalctl -u caller-worker -f

# Python worker
systemctl status inference-worker
journalctl -u inference-worker -f
```

---

## Teardown

```bash
terraform destroy
```

Type `yes` to confirm. All AWS resources will be deleted.

---

## Notes

- The **Python worker** connects **outbound** to the TS worker's private IP (`ws://<TS_PRIVATE_IP>:49134`). This IP is injected at provision time via Terraform's `templatefile()`.
- The **iii-engine** (running on the TS instance) listens on `localhost:49134`. The caller-worker connects to it locally.
- The Python instance has a **30 GB gp3** root volume and **8 GB swap** to handle large model weights without OOM crashes.
- The ALB health check polls `/v1/chat/completions` with a broad `200–499` matcher to handle pre-warm-up states.
