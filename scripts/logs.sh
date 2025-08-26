#!/bin/bash

# Zabbix 7.0 LTS Logs Viewer Script
# View logs from all Zabbix components

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

echo -e "${BLUE}📋 Zabbix 7.0 LTS Logs Viewer${NC}"
echo "================================="

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}❌ Error: kubectl is not available${NC}"
    exit 1
fi

# Check if we can connect via SSH (for remote kubectl)
SSH_KEY="$HOME/.ssh/k8s-cluster-key"
if [ -f "$SSH_KEY" ]; then
    KUBECTL_CMD="ssh -i $SSH_KEY k8s-user@<K8S_NODE_IP> kubectl"
    echo -e "${YELLOW}🔗 Using remote kubectl via SSH${NC}"
fi

# Function to show logs
show_logs() {
    local component=$1
    local lines=${2:-50}
    
    echo -e "${YELLOW}📋 $component logs (last $lines lines):${NC}"
    if $KUBECTL_CMD get deployment "$component" -n "$NAMESPACE" >/dev/null 2>&1; then
        $KUBECTL_CMD logs -n "$NAMESPACE" "deployment/$component" --tail="$lines" --since=10m
        echo ""
    else
        echo -e "${RED}❌ $component not found or not running${NC}"
        echo ""
    fi
}

# Function to show pod status
show_pod_status() {
    echo -e "${YELLOW}🔍 Pod Status:${NC}"
    if $KUBECTL_CMD get namespace "$NAMESPACE" >/dev/null 2>&1; then
        $KUBECTL_CMD get pods -n "$NAMESPACE" -o wide
        echo ""
    else
        echo -e "${RED}❌ Namespace $NAMESPACE not found${NC}"
        echo ""
    fi
}

# Function to show events
show_events() {
    echo -e "${YELLOW}📋 Recent Events:${NC}"
    if $KUBECTL_CMD get namespace "$NAMESPACE" >/dev/null 2>&1; then
        $KUBECTL_CMD get events -n "$NAMESPACE" --sort-by=.metadata.creationTimestamp | tail -20
        echo ""
    else
        echo -e "${RED}❌ Namespace $NAMESPACE not found${NC}"
    fi
}

# Check arguments
case "${1:-all}" in
    "server"|"zabbix-server")
        show_pod_status
        show_logs "zabbix-server" 100
        ;;
    "web"|"zabbix-web")
        show_pod_status
        show_logs "zabbix-web" 100
        ;;
    "db"|"database"|"postgresql")
        show_pod_status
        show_logs "postgresql" 100
        ;;
    "events")
        show_events
        ;;
    "status")
        show_pod_status
        ;;
    "all"|*)
        echo -e "${BLUE}📊 Complete Zabbix Status Overview${NC}"
        echo ""
        
        show_pod_status
        
        echo -e "${BLUE}=== ZABBIX SERVER LOGS ===${NC}"
        show_logs "zabbix-server" 30
        
        echo -e "${BLUE}=== ZABBIX WEB LOGS ===${NC}"
        show_logs "zabbix-web" 20
        
        echo -e "${BLUE}=== POSTGRESQL LOGS ===${NC}"
        show_logs "postgresql" 20
        
        echo -e "${BLUE}=== RECENT EVENTS ===${NC}"
        show_events
        ;;
esac

echo -e "${GREEN}📋 Log viewing completed${NC}"
echo ""
echo -e "${BLUE}Usage examples:${NC}"
echo "• All logs: ./scripts/logs.sh"
echo "• Server only: ./scripts/logs.sh server"
echo "• Web only: ./scripts/logs.sh web"
echo "• Database only: ./scripts/logs.sh db"
echo "• Events only: ./scripts/logs.sh events"
echo "• Status only: ./scripts/logs.sh status"
