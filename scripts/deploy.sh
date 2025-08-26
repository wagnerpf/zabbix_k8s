#!/bin/bash

# Zabbix 7.0 LTS Quick Deploy Script
# Deploy Zabbix using Ansible automation

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
ANSIBLE_DIR="ansible"
INVENTORY="inventories/production/hosts.yml"
PLAYBOOK="playbooks/deploy-zabbix.yml"

echo -e "${BLUE}🚀 Zabbix 7.0 LTS Corporate Deployment${NC}"
echo "=============================================="

# Check prerequisites
echo -e "${YELLOW}📋 Checking prerequisites...${NC}"

# Check if we're in the right directory
if [ ! -d "$ANSIBLE_DIR" ]; then
    echo -e "${RED}❌ Error: Run this script from the project root directory${NC}"
    echo -e "${YELLOW}Current directory: $(pwd)${NC}"
    exit 1
fi

# Check if Ansible is installed
if ! command -v ansible-playbook &> /dev/null; then
    echo -e "${RED}❌ Error: Ansible is not installed${NC}"
    echo -e "${YELLOW}Install with: pip install ansible${NC}"
    exit 1
fi

# Check SSH key
SSH_KEY="$HOME/.ssh/k8s-cluster-key"
if [ ! -f "$SSH_KEY" ]; then
    echo -e "${RED}❌ Error: SSH key not found: $SSH_KEY${NC}"
    echo -e "${YELLOW}Please ensure your SSH key is in the correct location${NC}"
    exit 1
fi

# Check SSH key permissions
if [ "$(stat -c %a "$SSH_KEY")" != "600" ]; then
    echo -e "${YELLOW}⚠️  Fixing SSH key permissions...${NC}"
    chmod 600 "$SSH_KEY"
fi

echo -e "${GREEN}✅ Prerequisites check passed${NC}"
echo ""

# Test connectivity
echo -e "${YELLOW}🔍 Testing cluster connectivity...${NC}"
cd "$ANSIBLE_DIR"

if ansible kubernetes_masters -i "$INVENTORY" -m ping; then
    echo -e "${GREEN}✅ Cluster connectivity verified${NC}"
else
    echo -e "${RED}❌ Error: Cannot connect to Kubernetes cluster${NC}"
    echo -e "${YELLOW}Please check:${NC}"
    echo "• SSH key permissions"
    echo "• Network connectivity to your Kubernetes master node"
    echo "• SSH service on target host"
    exit 1
fi

echo ""

# Deploy Zabbix
echo -e "${BLUE}🚀 Starting Zabbix 7.0 LTS deployment...${NC}"
echo "This will deploy:"
echo "• PostgreSQL database"
echo "• Zabbix Server 7.0 LTS"
echo "• Zabbix Web Interface"
echo "• Monitoring and observability"
echo ""

read -p "Continue with deployment? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Deployment cancelled."
    exit 0
fi

# Run deployment
echo -e "${YELLOW}⏳ Deploying Zabbix... (this may take 10-15 minutes)${NC}"
if ansible-playbook -i "$INVENTORY" "$PLAYBOOK"; then
    echo ""
    echo -e "${GREEN}🎉 Deployment completed successfully!${NC}"
    echo ""
    echo -e "${BLUE}📊 Access Information:${NC}"
    echo "• Web Interface (HTTP): http://<YOUR_K8S_NODE_IP>:30080"
    echo "• Web Interface (HTTPS): https://<YOUR_K8S_NODE_IP>:30443"
    echo "• Default Credentials: Admin / zabbix"
    echo ""
    echo -e "${YELLOW}🔧 Next Steps:${NC}"
    echo "1. Access web interface and change default password"
    echo "2. Configure first host monitoring"
    echo "3. Setup alerting and notifications"
    echo ""
    echo -e "${BLUE}📋 Management Commands:${NC}"
    echo "• Check status: ./scripts/status.sh"
    echo "• View logs: ./scripts/logs.sh"
    echo "• Cleanup: ./scripts/cleanup.sh"
else
    echo ""
    echo -e "${RED}❌ Deployment failed!${NC}"
    echo ""
    echo -e "${YELLOW}🔍 Troubleshooting:${NC}"
    echo "• Review output above for specific errors"
    echo "• Check Kubernetes resources: kubectl get all -n zabbix-monitoring"
    echo "• Check logs: ./scripts/logs.sh"
    echo "• Verify status: ./scripts/status.sh"
    echo "• Retry deployment: ./scripts/deploy.sh"
    exit 1
fi
