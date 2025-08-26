# Debug deployment commands:
ansible-playbook -i inventories/production/hosts.yml playbooks/deploy-zabbix.yml --diff -vvv
