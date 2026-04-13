set -a
source .env
set +a

terraform apply -auto-approve  || exit 1
cd ./ansible
ansible-playbook --connection=ssh --timeout=30 --private-key $SSH_KEY -v -i inventory.proxmox.yml playbook.yml -u root || exit 1
cd -
