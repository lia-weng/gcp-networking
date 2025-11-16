terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
      version = "4.51.0"
    }
  }
}

# ============================================
# BACKEND NETWORK & RESOURCES
# ============================================

// backend network
resource "google_compute_network" "vpc-be" {
  name = "vpc-be"
  auto_create_subnetworks = "false"
}

// backend firewall
resource "google_compute_firewall" "fw-be" {
  project = "cloud-networking-477403"
  name        = "fw-be"
  network     = google_compute_network.vpc-be.name
  depends_on = [google_compute_network.vpc-be]

  allow {
    protocol  = "tcp"
    ports     = ["22", "80"]
  }
  allow {
    protocol = "udp"
  }
  allow {
    protocol = "icmp"
  }
  source_ranges = ["0.0.0.0/0"]
}

# Cloud router for NAT
resource "google_compute_router" "nat-router" {
  name    = "nat-router"
  network = google_compute_network.vpc-be.name
  region  = "us-central1"
}

# Cloud NAT configuration
resource "google_compute_router_nat" "nat-config" {
  name   = "nat-config"
  router = google_compute_router.nat-router.name
  region = "us-central1"

  nat_ip_allocate_option               = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat   = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

// proxy-only subnet (required for internal load balancer)
resource "google_compute_subnetwork" "sub-proxy1" {
  name          = "sub-proxy1"
  ip_cidr_range = "10.0.0.0/24"
  region        = "us-central1"
  purpose       = "REGIONAL_MANAGED_PROXY"
  role          = "ACTIVE"
  network       = google_compute_network.vpc-be.id
}

// backend subnet
resource "google_compute_subnetwork" "sub-be1" {
  name          = "sub-be1"
  ip_cidr_range = "10.0.1.0/24"
  region        = "us-central1"
  network       = google_compute_network.vpc-be.id
}

// backend vm 1 - simple web server
resource "google_compute_instance" "vm-be1" {
  name = "vm-be1"
  machine_type = "e2-small"
  zone = "us-central1-a"  
  depends_on = [google_compute_network.vpc-be, google_compute_subnetwork.sub-be1]
  
  network_interface {
    network = google_compute_network.vpc-be.name
    subnetwork = google_compute_subnetwork.sub-be1.name
  }

  boot_disk {
    initialize_params {
      image = "debian-12-bookworm-v20240312"
    }
  } 
  
  metadata = {
    startup-script = <<-EOF
      #!/bin/bash
      sudo apt-get update -y
      sudo apt-get install -y apache2
      HOSTNAME=$(hostname)
      echo "<h1>Backend Server: $HOSTNAME</h1>" > /var/www/html/index.html
      systemctl restart apache2
    EOF
  }
}

// backend vm 2 - simple web server
resource "google_compute_instance" "vm-be2" {
  name = "vm-be2"
  machine_type = "e2-small"
  zone = "us-central1-a"  
  depends_on = [google_compute_network.vpc-be, google_compute_subnetwork.sub-be1]
  
  network_interface {
    network = google_compute_network.vpc-be.name
    subnetwork = google_compute_subnetwork.sub-be1.name
  }

  boot_disk {
    initialize_params {
      image = "debian-12-bookworm-v20240312"
    }
  } 
  
  metadata = {
    startup-script = <<-EOF
      #!/bin/bash
      sudo apt-get update -y
      sudo apt-get install -y apache2
      HOSTNAME=$(hostname)
      echo "<h1>Backend Server: $HOSTNAME</h1>" > /var/www/html/index.html
      systemctl restart apache2
    EOF
  }
}

// unmanaged instance group for backend VMs
resource "google_compute_instance_group" "backend-group" {
  name        = "backend-instance-group"
  description = "Unmanaged instance group for backend VMs"
  zone        = "us-central1-a"
  network     = google_compute_network.vpc-be.id

  instances = [
    google_compute_instance.vm-be1.self_link,
    google_compute_instance.vm-be2.self_link,
  ]

  named_port {
    name = "http"
    port = "80"
  }
}

// health check
resource "google_compute_region_health_check" "default" {
  project = "cloud-networking-477403"
  name     = "hc-be"
  region   = "us-central1"
  
  http_health_check {
    port_specification = "USE_SERVING_PORT"
  }
}

// backend service
resource "google_compute_region_backend_service" "default" {
  name                  = "backend-service"
  region                = "us-central1"
  protocol              = "HTTP"
  load_balancing_scheme = "INTERNAL_MANAGED"
  timeout_sec           = 10
  health_checks         = [google_compute_region_health_check.default.id]
  
  backend {
    group           = google_compute_instance_group.backend-group.id
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0
  }
}

// URL map
resource "google_compute_region_url_map" "default" {
  name            = "url-map-be"
  region          = "us-central1"
  default_service = google_compute_region_backend_service.default.id
}

// HTTP target proxy
resource "google_compute_region_target_http_proxy" "default" {
  name     = "http-proxy-be"
  region   = "us-central1"
  url_map  = google_compute_region_url_map.default.id
}

// forwarding rule (this gets the internal LB IP)
resource "google_compute_forwarding_rule" "forwarding-rule-be" {
  name                  = "forwarding-rule-be"
  region                = "us-central1"
  depends_on            = [google_compute_subnetwork.sub-proxy1]
  ip_protocol           = "TCP"
  load_balancing_scheme = "INTERNAL_MANAGED"
  port_range            = "80"
  target                = google_compute_region_target_http_proxy.default.id
  network               = google_compute_network.vpc-be.id
  subnetwork            = google_compute_subnetwork.sub-be1.id
  network_tier          = "PREMIUM"
}

# ============================================
# FRONTEND NETWORK & RESOURCES
# ============================================

// frontend network
resource "google_compute_network" "vpc-fe" {
  name = "vpc-fe"
  auto_create_subnetworks = "false"
}

// frontend firewall
resource "google_compute_firewall" "fw-fe" {
  project = "cloud-networking-477403"
  name        = "fw-fe"
  network     = google_compute_network.vpc-fe.name
  depends_on = [google_compute_network.vpc-fe]

  allow {
    protocol  = "tcp"
    ports     = ["22", "80", "443"]
  }
  allow {
    protocol = "udp"
  }
  allow {
    protocol = "icmp"
  }
  source_ranges = ["0.0.0.0/0"]
}

// frontend subnet
resource "google_compute_subnetwork" "sub-fe1" {
  name          = "sub-fe1"
  ip_cidr_range = "10.0.2.0/24"
  region        = "us-central1"
  network       = google_compute_network.vpc-fe.id
}

// VPC peering: frontend -> backend
resource "google_compute_network_peering" "fe-to-be" {
  name         = "fe-to-be-peering"
  network      = google_compute_network.vpc-fe.id
  peer_network = google_compute_network.vpc-be.id
}

// VPC peering: backend -> frontend
resource "google_compute_network_peering" "be-to-fe" {
  name         = "be-to-fe-peering"
  network      = google_compute_network.vpc-be.id
  peer_network = google_compute_network.vpc-fe.id
}

// frontend vm
resource "google_compute_instance" "vm-fe" {
  name = "vm-fe"
  machine_type = "e2-small"
  zone = "us-central1-a"  
  depends_on = [
    google_compute_network.vpc-fe, 
    google_compute_subnetwork.sub-fe1,
    google_compute_network_peering.fe-to-be,
    google_compute_network_peering.be-to-fe
  ]
  
  network_interface {
    network = google_compute_network.vpc-fe.name
    subnetwork = google_compute_subnetwork.sub-fe1.name
    
    // Add external IP so you can SSH in
    access_config {
      // Ephemeral external IP
    }
  }

  boot_disk {
    initialize_params {
      image = "debian-12-bookworm-v20240312"
    }
  } 
  
  metadata = {
    startup-script = <<-EOF
      #!/bin/bash
      apt-get update
      apt-get install -y curl
      
      # Create a test script
      cat > /root/test-lb.sh << 'SCRIPT'
#!/bin/bash
LB_IP="${google_compute_forwarding_rule.forwarding-rule-be.ip_address}"

echo "=========================================="
echo "Testing Internal Load Balancer"
echo "Load Balancer IP: $LB_IP"
echo "=========================================="
echo ""

for i in {1..10}; do
  echo "Request $i:"
  curl -s http://$LB_IP
  echo ""
done
SCRIPT
      
      chmod +x /root/test-lb.sh
    EOF
  }
}

# ============================================
# OUTPUTS
# ============================================

output "load_balancer_ip" {
  value = google_compute_forwarding_rule.forwarding-rule-be.ip_address
  description = "Internal IP address of the load balancer"
}

output "frontend_external_ip" {
  value = google_compute_instance.vm-fe.network_interface[0].access_config[0].nat_ip
  description = "External IP address of the frontend VM (SSH here)"
}

output "backend_vm1_ip" {
  value = google_compute_instance.vm-be1.network_interface[0].network_ip
  description = "Internal IP of backend VM 1"
}

output "backend_vm2_ip" {
  value = google_compute_instance.vm-be2.network_interface[0].network_ip
  description = "Internal IP of backend VM 2"
}

output "test_instructions" {
  value = <<-EOT
  
  To test the load balancer:
  
  1. SSH into the frontend VM:
     gcloud compute ssh vm-fe --zone=us-central1-a
  
  2. Run the test script:
     sudo /root/test-lb.sh
  
  3. You should see responses alternating between vm-be1 and vm-be2
  
  EOT
  description = "Instructions for testing"
}