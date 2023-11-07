#!bash

# get name of running admin pod
admin_pod=$(kubectl get pods -l 'app.kubernetes.io/component=admin,app.kubernetes.io/name=mailu' -o jsonpath="{.items[0].metadata.name}")
if [[ -z "${admin_pod}" ]]; then
    echo "Sorry, can't find a running Mailu admin pod."
    echo "You need to start this in the right Kubernetes context (where the Mailu cluster is running)."
    exit 1
fi

# Get the name of the mailu-dovecot pod
dovecot_pod=$(kubectl get pods -l 'app.kubernetes.io/name=mailu,app.kubernetes.io/component=dovecot' -o jsonpath="{.items[0].metadata.name}")

# Fetch list of users from admin pod using kubectl
declare -A users=()
while read line; do
    users[${line#* }]="${line/ *}"
done < <(
    kubectl exec "${admin_pod}" -- flask mailu config-export -j user.email user.enabled 2>/dev/null | jq -r '.user[] | "\(.enabled) \(.email)"'
)

if [[ ${#users[@]} -eq 0 ]]; then
    echo "Mailu config-export returned no users. Aborted."
    exit 3
fi
for email in "${!users[@]}"; do
    echo $email
done
# diff list of users <> storage, now using kubectl to access the mail directory
unknown=false
disabled=false
# We list the directories inside the mail storage using kubectl exec
maildirs=$(kubectl exec "${dovecot_pod}" -- ls /mail)

for maildir in $maildirs; do
    email="${maildir}"
    enabled="${users[${email}]:-}"
    if [[ -z "${enabled}" ]]; then
        unknown=true
        users[${email}]="unknown"
    elif [[ ${enabled} == "true" ]]; then
        unset users[${email}]
    else
        disabled=true
        users[${email}]="disabled"
    fi
done

if [[ ${#users[@]} -eq 0 ]]; then
    echo "Nothing to clean up."
    exit 0
fi

# Check if webmail is in use in the Mailu cluster
webmail_pod=$(kubectl get pods -l 'app.kubernetes.io/name=mailu,app.kubernetes.io/component=webmail' -o jsonpath="{.items[0].metadata.name}")
webmail_in_use=false
if [[ -n "${webmail_pod}" ]]; then
    webmail_in_use=true
fi

# output actions
if ${unknown}; then
    echo "# To delete maildirs unknown to Mailu, run:"
    for email in "${!users[@]}"; do
        [[ "${users[${email}]}" == "unknown" ]] || continue
        echo "kubectl exec ${dovecot_pod} -- rm -rf '/mail/${email}'"
        if ${webmail_in_use}; then
            echo "kubectl exec ${webmail_pod} -- su mailu -c '/var/www/roundcube/bin/deluser.sh --host=front ${email}'"
        fi
    done
    echo
fi

if ${disabled}; then
    echo "# To purge disabled users, run:"
    for email in "${!users[@]}"; do
        [[ "${users[${email}]}" == "disabled" ]] || continue
        echo "kubectl exec ${admin_pod} -- flask mailu user-delete -r ${email} && kubectl exec ${dovecot_pod} -- rm -rf '/mail/${email}'"
        if ${webmail_in_use}; then
            echo "kubectl exec ${webmail_pod} -- su mailu -c '/var/www/roundcube/bin/deluser.sh --host=front ${email}'"
        fi
    done
    echo
fi
