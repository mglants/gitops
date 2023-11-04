# Outpost for LDAP example

```
kubernetes_json_patches:
  service:
    - op: add
      path: /spec/loadBalancerIP
      value: "192.168.40.16"
    - op: add
      path: /metadata/annotations
      value:
        external-dns.alpha.kubernetes.io/hostname: ldap.ur30.ru
        external-dns.alpha.kubernetes.io/type: internal

```
