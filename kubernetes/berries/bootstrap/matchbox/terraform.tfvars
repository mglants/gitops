matchbox_http_endpoint = "http://172.16.30.200:9080"
matchbox_rpc_endpoint  = "172.16.30.200:9081"
# renovate: fixme
talos_version          = "v1.7.2"

cluster_name = "berries"

nodes = [
  {
    name         = "berries-cp1",
    mac          = "00:a0:98:4e:20:65",
    talos_config = "../talos/clusterconfig/berries-berries-cp1.yaml"
    architecture = "amd64"
  },
  {
    name         = "berries-cp2",
    mac          = "dc:a6:32:80:5b:9c",
    talos_config = "../talos/clusterconfig/berries-berries-cp2.yaml"
    architecture = "arm64"
  },
  {
    name         = "berries-cp3",
    mac          = "e4:5f:01:35:85:31",
    talos_config = "../talos/clusterconfig/berries-berries-cp3.yaml"
    architecture = "arm64"
  },
  {
    name         = "berries-worker1",
    mac          = "dc:a6:32:f9:bc:a5",
    talos_config = "../talos/clusterconfig/berries-berries-worker1.yaml"
    architecture = "arm64"
  },
  {
    name         = "berries-worker2",
    mac          = "dc:a6:32:f9:bc:1b",
    talos_config = "../talos/clusterconfig/berries-berries-worker2.yaml"
    architecture = "arm64"
  },
  {
    name         = "berries-worker3",
    mac          = "dc:a6:32:ae:44:6e",
    talos_config = "../talos/clusterconfig/berries-berries-worker3.yaml"
    architecture = "arm64"
  }
]
