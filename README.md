# GCP Internal Load Balancer with Frontend & Backend

This Terraform project deploys a multi-tier web application on Google Cloud Platform, demonstrating an internal HTTP load balancer connecting frontend and backend VMs across separate VPC networks.

## Architecture

```
Internet → Frontend VM (public IP) → Internal Load Balancer → Backend VM1 & VM2
           (vpc-fe)                    (vpc-be)                (vpc-be)
                 \________________VPC Peering________________/
```

**What it creates:**

- 2 backend VMs running Flask apps in `vpc-be`
- 1 frontend VM running Flask app in `vpc-fe` (with public IP)
- Internal HTTP Load Balancer (Layer 7) distributing traffic to backend VMs
- VPC peering connecting frontend and backend networks
- Firewall rules, subnets, and health checks

## Prerequisites

1. **GCP Account** with billing enabled
2. **Terraform** installed ([Download](https://www.terraform.io/downloads))
3. **gcloud CLI** installed ([Download](https://cloud.google.com/sdk/docs/install))

## Setup

### 1. Authenticate with GCP

```bash
# Login to GCP
gcloud auth login

# Set your project
gcloud config set project YOUR_PROJECT_ID

# Enable required APIs
gcloud services enable compute.googleapis.com

# Set up credentials for Terraform
gcloud auth application-default login
```

### 2. Configure Provider

Create a `provider.tf` file in the project root:

```hcl
provider "google" {
  project = "YOUR_PROJECT_ID"
  region  = "us-central1"
}
```

Replace `YOUR_PROJECT_ID` with your actual GCP project ID.

### 3. Deploy Infrastructure

```bash
# Initialize Terraform
terraform init

# Preview changes
terraform plan

# Deploy (takes 5-10 minutes)
terraform apply
```

Type `yes` when prompted.

## Access the Application

After deployment, Terraform will output:

```
frontend_external_ip = "34.123.45.67"
load_balancer_ip = "10.0.1.5"
```

**Access the frontend:**

```
http://<frontend_external_ip>
```

Click the button on the webpage to make requests through the internal load balancer to the backend VMs. You'll see responses alternating between `vm-be1` and `vm-be2`.

## Testing

### Test from command line:

```bash
# Get the frontend external IP
FRONTEND_IP=$(terraform output -raw frontend_external_ip)

# Access the frontend
curl http://$FRONTEND_IP

# SSH into frontend and test load balancer
gcloud compute ssh vm-fe --zone=us-central1-a
curl http://$(terraform output -raw load_balancer_ip)
```

### Verify load balancing:

```bash
# SSH into frontend VM
gcloud compute ssh vm-fe --zone=us-central1-a

# Make multiple requests - see different backend VMs respond
for i in {1..10}; do
  curl http://<load_balancer_ip>
  echo ""
done
```

## Clean Up

**Important:** To avoid ongoing charges, destroy all resources when done:

```bash
terraform destroy
```

Type `yes` to confirm.

## How It Works

1. **Frontend VM** has a public IP accessible from the internet
2. **VPC Peering** allows frontend VM to communicate with backend network
3. **Frontend** makes HTTP requests to the **Internal Load Balancer** IP
4. **Load Balancer** distributes requests between the two backend VMs
5. **Backend VMs** respond with their hostname, showing load balancing in action

The internal load balancer is Layer 7 (HTTP-aware) and only accessible from within the VPC networks, not from the internet.
