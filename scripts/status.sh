#!/bin/bash
# Zabbix 7.0 LTS Status Check Script
# Corporate Monitoring Environment Status

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="zabbix-monitoring"
KUBECTL_CMD="kubectl"

echo -e "${BLUE}🔍 Zabbix 7.0 LTS Corporate Status Check${NC}"
echo "=========================================="
echo ""

# Check if kubectl is available locally, otherwise use SSH
if ! command -v $KUBECTL_CMD &> /dev/null; then
    SSH_KEY="$HOME/.ssh/k8s-cluster-key"
    if [ -f "$SSH_KEY" ]; then
        KUBECTL_CMD="ssh -i $SSH_KEY k8s-user@<K8S_NODE_IP> kubectl"
        echo -e "${YELLOW}🔗 Using remote kubectl via SSH${NC}"
    else
        echo -e "${RED}❌ kubectl not found and SSH key not available.${NC}"
        exit 1
    fi
fi

# Check if namespace exists
if ! $KUBECTL_CMD get namespace $NAMESPACE &> /dev/null; then
    echo -e "${RED}❌ Namespace '$NAMESPACE' not found. Zabbix is not deployed.${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Namespace: $NAMESPACE${NC}"
echo ""

# Check Pods Status
echo -e "${BLUE}📦 Pod Status:${NC}"
echo "----------------"
PODS_OUTPUT=$($KUBECTL_CMD get pods -n $NAMESPACE -o wide 2>/dev/null || echo "No pods found")
echo "$PODS_OUTPUT"

# Count pod statuses
RUNNING_PODS=$($KUBECTL_CMD get pods -n $NAMESPACE --field-selector=status.phase=Running -o name 2>/dev/null | wc -l)
PENDING_PODS=$($KUBECTL_CMD get pods -n $NAMESPACE --field-selector=status.phase=Pending -o name 2>/dev/null | wc -l)
FAILED_PODS=$($KUBECTL_CMD get pods -n $NAMESPACE --field-selector=status.phase=Failed -o name 2>/dev/null | wc -l)

echo ""
echo -e "${GREEN}Running: $RUNNING_PODS${NC} | ${YELLOW}Pending: $PENDING_PODS${NC} | ${RED}Failed: $FAILED_PODS${NC}"
echo ""

# Check Services
echo -e "${BLUE}🌐 Services:${NC}"
echo "-------------"
$KUBECTL_CMD get svc -n $NAMESPACE 2>/dev/null || echo "No services found"
echo ""

# Check PVC Status
echo -e "${BLUE}💾 Storage:${NC}"
echo "------------"
$KUBECTL_CMD get pvc -n $NAMESPACE 2>/dev/null || echo "No PVCs found"
echo ""

# Check ConfigMaps and Secrets
echo -e "${BLUE}🔐 Configuration:${NC}"
echo "------------------"
echo "Secrets:"
$KUBECTL_CMD get secrets -n $NAMESPACE 2>/dev/null | grep -v "default-token" || echo "No secrets found"
echo ""
echo "ConfigMaps:"
$KUBECTL_CMD get configmap -n $NAMESPACE 2>/dev/null | grep -v "kube-root-ca.crt" || echo "No configmaps found"
echo ""

# Access Information
echo -e "${BLUE}🌐 Access Information:${NC}"
echo "-----------------------"
# Extract IP from Ansible inventory
INVENTORY_FILE="./ansible/inventories/production/hosts.yml"
if [ -f "$INVENTORY_FILE" ]; then
    NODE_IP=$(grep "ansible_host:" "$INVENTORY_FILE" | head -1 | awk '{print $2}')
else
    # Fallback: For SSH kubectl access, extract from command
    if [[ "$KUBECTL_CMD" == *"ssh"* ]]; then
        NODE_IP=$(echo "$KUBECTL_CMD" | awk -F'@' '{print $2}' | awk '{print $1}')
    else
        NODE_IP=$($KUBECTL_CMD get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}' 2>/dev/null)
        if [ -z "$NODE_IP" ]; then
            NODE_IP=$($KUBECTL_CMD get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null)
        fi
    fi
fi

if [ -z "$NODE_IP" ]; then
    NODE_IP="<NODE_IP>"
fi

WEB_SERVICE=$($KUBECTL_CMD get svc -n $NAMESPACE zabbix-web-service -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "N/A")
WEB_SSL_SERVICE=$($KUBECTL_CMD get svc -n $NAMESPACE zabbix-web-service -o jsonpath='{.spec.ports[1].nodePort}' 2>/dev/null || echo "N/A")

echo -e "HTTP:  ${GREEN}http://$NODE_IP:$WEB_SERVICE${NC}"
echo -e "HTTPS: ${GREEN}https://$NODE_IP:$WEB_SSL_SERVICE${NC}"
echo -e "Default Login: ${YELLOW}Admin / zabbix${NC}"
echo ""

# Health Checks
echo -e "${BLUE}🏥 Health Checks:${NC}"
echo "-------------------"

# PostgreSQL Health
echo -n "PostgreSQL: "
if $KUBECTL_CMD exec -n $NAMESPACE deployment/postgresql -- pg_isready -U zabbix -d zabbix &>/dev/null; then
    echo -e "${GREEN}✅ Healthy${NC}"
else
    echo -e "${RED}❌ Issues detected${NC}"
fi

# Zabbix Server Health
echo -n "Zabbix Server: "
if $KUBECTL_CMD get pod -n $NAMESPACE -l app=zabbix-server -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q "Running"; then
    echo -e "${GREEN}✅ Running${NC}"
else
    echo -e "${RED}❌ Not running${NC}"
fi

# Zabbix Web Health
echo -n "Zabbix Web: "
if $KUBECTL_CMD get pod -n $NAMESPACE -l app=zabbix-web -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q "Running"; then
    echo -e "${GREEN}✅ Running${NC}"
else
    echo -e "${RED}❌ Not running${NC}"
fi

echo ""

# Overall Status
if [ "$FAILED_PODS" -eq 0 ] && [ "$RUNNING_PODS" -ge 3 ]; then
    echo -e "${GREEN}🎉 Overall Status: HEALTHY${NC}"
    echo -e "${GREEN}✅ Zabbix 7.0 LTS is running successfully!${NC}"
else
    echo -e "${YELLOW}⚠️  Overall Status: NEEDS ATTENTION${NC}"
    echo -e "${YELLOW}Some components may need investigation.${NC}"
fi

echo ""
echo -e "${BLUE}📊 For detailed logs, run: ./scripts/logs.sh${NC}"
echo -e "${BLUE}🧹 To cleanup deployment, run: ./scripts/cleanup.sh${NC}"
