set -a
source .env
set +a

TAGS=""

if [[ "$ANSIBLE_TAGS" != "" ]]; then
    TAGS="--tags $ANSIBLE_TAGS"
fi

echo "$TAGS"
# terraform apply -auto-approve  || exit 1
cd ./ansible
ansible-playbook --connection=ssh --timeout=30 --private-key $SSH_KEY -v -i inventory.proxmox.yml playbook.yml -u root $TAGS || exit 1
cd -
