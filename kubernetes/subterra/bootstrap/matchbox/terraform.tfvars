matchbox_http_endpoint = "http://192.168.48.150:9080"
matchbox_rpc_endpoint  = "192.168.48.150:9081"
# renovate: fixme
talos_version          = "v1.7.2"

cluster_name = "subterra"

nodes = [
  {
    name         = "subterra-cp3",
    mac          = "14:18:77:6d:83:b7",
    talos_config = "../talos/clusterconfig/subterra-subterra-cp3.yaml"
    architecture = "amd64"
  },
  {
    name         = "subterra-cp2",
    mac          = "14:18:77:71:3d:0e",
    talos_config = "../talos/clusterconfig/subterra-subterra-cp2.yaml"
    architecture = "amd64"
  },
  {
    name         = "subterra-cp1",
    mac          = "d0:94:66:02:d6:ce",
    talos_config = "../talos/clusterconfig/subterra-subterra-cp1.yaml"
    architecture = "amd64"
  }
]
