# Match each node to a profile

resource "matchbox_group" "node" {
  count = length(var.nodes)
  # tflint-ignore: terraform_deprecated_index
  name = format("%s-%s", var.cluster_name, var.nodes.*.name[count.index])
  # tflint-ignore: terraform_deprecated_index
  profile = matchbox_profile.nodes.*.name[count.index]

  selector = {
    # tflint-ignore: terraform_deprecated_index
    mac = var.nodes.*.mac[count.index]
  }
}
