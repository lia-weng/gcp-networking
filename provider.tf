provider "google" {
  credentials = file("./terraform-service-account-key.json")

  project = "cloud-networking-477403"
  region  = "us-central1"
  zone    = "us-central1-a"
}
