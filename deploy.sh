#!/usr/bin/env bash
set -a
source .env
set +a

if [[ "$ANSIBLE_TAGS" == "" ]]; then
    tofu -chdir=terraform apply -auto-approve || exit 1
else
    echo "ANSIBLE_TAGS is not empty, skipping terraform apply..."
fi

ANSIBLE_ARGS=(--connection=ssh --timeout=30 --private-key "$SSH_KEY" -v -i inventory.proxmox.yml -i hosts.yml playbook.yml)
[[ -n "$ANSIBLE_TAGS" ]] && ANSIBLE_ARGS+=(--tags "$ANSIBLE_TAGS")
[[ -n "$ANSIBLE_LIMIT" ]] && ANSIBLE_ARGS+=(--limit "$ANSIBLE_LIMIT")
[[ -n "$ANSIBLE_EXTRA_VARS" ]] && ANSIBLE_ARGS+=(-e "$ANSIBLE_EXTRA_VARS")

echo "Executing Ansible with tags: $ANSIBLE_TAGS limit: $ANSIBLE_LIMIT"
cd ./ansible && ansible-playbook "${ANSIBLE_ARGS[@]}" || exit 1
