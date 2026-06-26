set -a
source .env
set +a

TAGS=""

if [[ "$ANSIBLE_TAGS" != "" ]]; then
    TAGS="--tags $ANSIBLE_TAGS"
fi

if [[ "$ANSIBLE_TAGS" == "" ]]; then
    cd terraform
    tofu apply -auto-approve || exit 1
    cd -
else
    echo "ANSIBLE_TAGS is not empty, skipping terraform config..."
fi

cd ./ansible
echo "Executing Ansible with tags: $TAGS"
ansible-playbook --connection=ssh --timeout=30 --private-key $SSH_KEY -v -i inventory.proxmox.yml -i hosts.yml playbook.yml $TAGS || exit 1
cd -

