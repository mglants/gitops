variable "cluster_name" {
  type        = string
  description = "Unique cluster name"
}

variable "matchbox_http_endpoint" {
  type        = string
  description = "Matchbox HTTP read-only endpoint (e.g. http://matchbox.example.com:8080)"
}

variable "matchbox_rpc_endpoint" {
  type        = string
  description = "Matchbox gRPC API endpoint, without the protocol (e.g. matchbox.example.com:8081)"
}

variable "talos_version" {
  type        = string
  description = "Talos version to PXE and install (e.g. v1.3.0)"
}

# machines

variable "nodes" {
  type = list(object({
    name         = string
    mac          = string
    talos_config = string
    architecture = string
  }))
}
