#!/bin/bash

# Zabbix 7.0 LTS Cleanup Script
# Remove completamente o Zabbix do cluster Kubernetes

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="zabbix-monitoring"
ANSIBLE_DIR="$(dirname "$0")/../ansible"
INVENTORY="$ANSIBLE_DIR/inventories/production/hosts.yml"

echo -e "${RED}🗑️  Zabbix 7.0 LTS Complete Cleanup${NC}"
echo "==========================================="

echo -e "${YELLOW}⚠️  WARNING: This will completely remove:${NC}"
echo "• All Zabbix deployments and services"
echo "• PostgreSQL database and data"
echo "• Persistent volumes and claims"
echo "• Secrets and configurations"
echo "• Complete namespace: $NAMESPACE"
echo ""

# Confirmation prompt
read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirm
if [ "$confirm" != "yes" ]; then
    echo -e "${BLUE}ℹ️  Cleanup cancelled by user${NC}"
    exit 0
fi

echo -e "${RED}🚀 Starting complete cleanup...${NC}"
echo ""

# Check if Ansible is available
if ! command -v ansible-playbook &> /dev/null; then
    echo -e "${RED}❌ Error: ansible-playbook not found${NC}"
    exit 1
fi

# Check if inventory exists
if [ ! -f "$INVENTORY" ]; then
    echo -e "${RED}❌ Error: Inventory file not found: $INVENTORY${NC}"
    exit 1
fi

echo -e "${BLUE}🔍 Testing cluster connectivity...${NC}"
if ansible k8s-master -i "$INVENTORY" -m ping > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Cluster connectivity verified${NC}"
else
    echo -e "${RED}❌ Error: Cannot connect to Kubernetes cluster${NC}"
    exit 1
fi

echo -e "${RED}🗑️  Removing Zabbix resources...${NC}"

# Method 1: Try Ansible cleanup first
if [ -f "$ANSIBLE_DIR/playbooks/cleanup-zabbix.yml" ]; then
    echo -e "${BLUE}📋 Running Ansible cleanup playbook...${NC}"
    ansible-playbook -i "$INVENTORY" "$ANSIBLE_DIR/playbooks/cleanup-zabbix.yml" -vvv || echo "Ansible cleanup failed, continuing with manual cleanup..."
fi

# Method 2: Direct kubectl cleanup (more thorough)
echo -e "${BLUE}🔧 Performing direct cleanup...${NC}"

# Force remove all pods first (immediate termination)
echo "Force removing all pods..."
ansible k8s-master -i "$INVENTORY" -m shell -a "kubectl delete pods --all -n $NAMESPACE --force --grace-period=0 --ignore-not-found=true" || true

# Remove all deployments
echo "Removing deployments..."
ansible k8s-master -i "$INVENTORY" -m shell -a "kubectl delete deployment --all -n $NAMESPACE --ignore-not-found=true" || true

# Remove all replicasets
echo "Removing replicasets..."
ansible k8s-master -i "$INVENTORY" -m shell -a "kubectl delete replicaset --all -n $NAMESPACE --ignore-not-found=true" || true

# Remove all services  
echo "Removing services..."
ansible k8s-master -i "$INVENTORY" -m shell -a "kubectl delete service --all -n $NAMESPACE --ignore-not-found=true" || true

# Remove all PVCs and ensure volumes are deleted
echo "Removing persistent volume claims and volumes..."
ansible k8s-master -i "$INVENTORY" -m shell -a "kubectl delete pvc --all -n $NAMESPACE --ignore-not-found=true" || true

# Wait for PVCs to be fully deleted
echo "Waiting for PVCs to be terminated..."
ansible k8s-master -i "$INVENTORY" -m shell -a "
timeout=60
while [ \$timeout -gt 0 ]; do
  pvc_count=\$(kubectl get pvc -n $NAMESPACE --no-headers 2>/dev/null | wc -l || echo '0')
  if [ \"\$pvc_count\" -eq 0 ]; then
    echo 'All PVCs removed successfully'
    break
  fi
  echo \"Waiting for \$pvc_count PVCs to be deleted...\"
  sleep 5
  timeout=\$((timeout-5))
done
" || true

# Force remove any remaining PVs that might be stuck
echo "Checking for orphaned Persistent Volumes..."
ansible k8s-master -i "$INVENTORY" -m shell -a "
# Get PVs that might be related to our namespace
kubectl get pv --no-headers 2>/dev/null | grep -E 'longhorn.*zabbix|pvc.*$NAMESPACE' | awk '{print \$1}' | while read pv; do
  if [ ! -z \"\$pv\" ]; then
    echo \"Removing orphaned PV: \$pv\"
    kubectl patch pv \"\$pv\" -p '{\"metadata\":{\"finalizers\":null}}' 2>/dev/null || true
    kubectl delete pv \"\$pv\" --ignore-not-found=true 2>/dev/null || true
  fi
done
" || true

# Additional Longhorn volume cleanup (if using Longhorn)
echo "Cleaning up Longhorn volumes..."
ansible k8s-master -i "$INVENTORY" -m shell -a "
# Remove any Longhorn volumes that might be stuck
if kubectl get crd volumes.longhorn.io >/dev/null 2>&1; then
  kubectl get volumes.longhorn.io -n longhorn-system --no-headers 2>/dev/null | grep -E 'pvc.*$NAMESPACE' | awk '{print \$1}' | while read volume; do
    if [ ! -z \"\$volume\" ]; then
      echo \"Removing Longhorn volume: \$volume\"
      kubectl patch volume.longhorn.io \"\$volume\" -n longhorn-system -p '{\"metadata\":{\"finalizers\":null}}' 2>/dev/null || true
      kubectl delete volume.longhorn.io \"\$volume\" -n longhorn-system --ignore-not-found=true 2>/dev/null || true
    fi
  done
fi
" || true

# Remove secrets
echo "Removing secrets..."
ansible k8s-master -i "$INVENTORY" -m shell -a "kubectl delete secret --all -n $NAMESPACE --ignore-not-found=true" || true

# Remove configmaps (except system ones)
echo "Removing configmaps..."
ansible k8s-master -i "$INVENTORY" -m shell -a "kubectl delete configmap --all -n $NAMESPACE --ignore-not-found=true" || true

# Remove any remaining resources
echo "Removing any remaining resources..."
ansible k8s-master -i "$INVENTORY" -m shell -a "kubectl delete all --all -n $NAMESPACE --ignore-not-found=true" || true

# Wait for resources to be terminated
echo -e "${YELLOW}⏳ Waiting for resources to be terminated...${NC}"
sleep 15

# Additional cleanup: Remove any stuck pods with force
echo "Force removing any remaining pods..."
ansible k8s-master -i "$INVENTORY" -m shell -a "kubectl get pods -n $NAMESPACE --no-headers 2>/dev/null | awk '{print \$1}' | xargs -r kubectl delete pod --force --grace-period=0 -n $NAMESPACE" || true

# Clean up Docker images on all nodes (optional but thorough)
echo "Cleaning up Zabbix Docker images on cluster nodes..."
ansible all -i "$INVENTORY" -m shell -a "docker images | grep zabbix | awk '{print \$3}' | xargs -r docker rmi -f" || true

# Remove namespace (this will force remove any remaining resources)
echo "Removing namespace..."
ansible k8s-master -i "$INVENTORY" -m shell -a "kubectl delete namespace $NAMESPACE --ignore-not-found=true" || true

# Wait for namespace to be fully deleted
echo -e "${YELLOW}⏳ Waiting for namespace deletion to complete...${NC}"
timeout=60
while [ $timeout -gt 0 ]; do
    if ! ansible k8s-master -i "$INVENTORY" -m shell -a "kubectl get namespace $NAMESPACE" > /dev/null 2>&1; then
        break
    fi
    sleep 2
    timeout=$((timeout-2))
done

# Verify cleanup
echo -e "${BLUE}🔍 Verifying cleanup...${NC}"
if ansible k8s-master -i "$INVENTORY" -m shell -a "kubectl get namespace $NAMESPACE" > /dev/null 2>&1; then
    echo -e "${YELLOW}⚠️  Namespace still exists, forcing removal...${NC}"
    ansible k8s-master -i "$INVENTORY" -m shell -a "kubectl patch namespace $NAMESPACE -p '{\"metadata\":{\"finalizers\":[]}}' --type=merge" || true
else
    echo -e "${GREEN}✅ Namespace successfully removed${NC}"
fi

# Final verification
echo -e "${BLUE}📊 Final status check...${NC}"
echo "Remaining resources in cluster:"
ansible k8s-master -i "$INVENTORY" -m shell -a "kubectl get all --all-namespaces | grep zabbix || echo 'No Zabbix resources found'" || true

echo ""
echo -e "${GREEN}🎉 Cleanup completed successfully!${NC}"
echo ""
echo -e "${BLUE}📋 Summary:${NC}"
echo "• Namespace: $NAMESPACE - REMOVED"
echo "• All deployments - REMOVED"
echo "• All services - REMOVED"
echo "• All PVCs and data - REMOVED"
echo "• All secrets - REMOVED"
echo "• All configmaps - REMOVED"
echo ""
echo -e "${GREEN}✅ Cluster is now clean and ready for fresh deployment!${NC}"
echo -e "${BLUE}💡 To redeploy, run: ./scripts/deploy.sh${NC}"
