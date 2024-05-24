locals {
  remote_args = [
    "initrd=initramfs.xz",
    "init_on_alloc=1",
    "slab_nomerge",
    "pti=on",
    "console=tty0",
    "console=ttyS0",
    "printk.devkmsg=on",
    "talos.platform=metal",
    "talos.config=${var.matchbox_http_endpoint}/generic?uuid=$${uuid}&mac=$${mac:hexhyp}",
    "net.ifnames=0"
  ]
}

// Talos node profile
resource "matchbox_profile" "nodes" {
  count = length(var.nodes)
  # tflint-ignore: terraform_deprecated_index
  name = format("%s-%s", var.cluster_name, var.nodes.*.name[count.index])

  kernel = "/assets/vmlinuz-${var.nodes.*.architecture[count.index]}"
  initrd =  [
    "--name initramfs.xz /assets/initramfs-${var.nodes.*.architecture[count.index]}.xz"
  ]
  args   = local.remote_args

  # tflint-ignore: terraform_deprecated_index
  generic_config = file(var.nodes.*.talos_config[count.index])

}
