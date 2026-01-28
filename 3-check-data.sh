#!/bin/bash

# Note: NOT using 'set -e' because we need to handle kubectl errors gracefully
# and check exit codes manually

# Configuration
POD_NAME=""
NAMESPACE="${OKTETO_NAMESPACE}"
DB_NAME="${TARGET_DB:-mydatabase}"
DB_USER="postgres"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== PostgreSQL Data Check Script ===${NC}"
echo ""

# Check if namespace is set
if [ -z "$NAMESPACE" ]; then
    echo -e "${RED}Error: OKTETO_NAMESPACE environment variable is not set!${NC}"
    echo ""
    echo "Please set it before running this script:"
    echo "  export OKTETO_NAMESPACE=your-namespace"
    echo "  ./3-check-data.sh"
    echo ""
    echo "Or run inline:"
    echo "  OKTETO_NAMESPACE=your-namespace ./3-check-data.sh"
    exit 1
fi

# Find the postgres pod
echo "Finding PostgreSQL pod..."
echo "Using namespace: $NAMESPACE"
echo "Looking for pods with label: stack.okteto.com/service=main-dev-db"
echo ""

# Capture kubectl output (both stdout and stderr)
POD_SEARCH_OUTPUT=$(kubectl get pods -n "$NAMESPACE" -l stack.okteto.com/service=main-dev-db -o jsonpath='{.items[0].metadata.name}' 2>&1)
KUBECTL_EXIT_CODE=$?

echo "kubectl command exit code: $KUBECTL_EXIT_CODE"
echo "kubectl raw output: '$POD_SEARCH_OUTPUT'"
echo ""

# Check if kubectl command failed
if [ $KUBECTL_EXIT_CODE -ne 0 ]; then
    echo -e "${RED}kubectl command failed!${NC}"
    echo "$POD_SEARCH_OUTPUT"
    echo ""
    echo "This is likely a permissions issue. Please ensure:"
    echo "1. You have access to namespace '$NAMESPACE'"
    echo "2. Your service account has permission to list pods in this namespace"
    echo "3. The namespace exists: kubectl get namespace $NAMESPACE"
    exit 1
fi

# Extract pod name (filter out any error strings that might be mixed in)
POD_NAME=$(echo "$POD_SEARCH_OUTPUT" | grep -v "Error" | grep -v "error" | grep -v "Forbidden" | xargs)

echo "Extracted pod name: '$POD_NAME'"

if [ -z "$POD_NAME" ]; then
    echo -e "${RED}Error: Could not find PostgreSQL pod with label 'stack.okteto.com/service=main-dev-db'${NC}"
    echo ""
    echo "Debugging information:"
    echo "- Namespace: $NAMESPACE"
    echo "- kubectl version:"
    kubectl version --client --short 2>/dev/null || echo "  Could not get kubectl version"
    echo ""
    echo "Checking all pods in namespace:"
    kubectl get pods -n "$NAMESPACE" 2>&1
    echo ""
    echo "Checking all services in namespace:"
    kubectl get svc -n "$NAMESPACE" 2>&1
    echo ""
    echo "Checking all statefulsets in namespace:"
    kubectl get statefulset -n "$NAMESPACE" 2>&1
    exit 1
fi

echo -e "${GREEN}Found pod: ${POD_NAME}${NC}"
echo ""

# Check if pod is ready
POD_STATUS=$(kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.status.phase}')
if [ "$POD_STATUS" != "Running" ]; then
    echo -e "${RED}Error: Pod is not running (status: ${POD_STATUS})${NC}"
    exit 1
fi

echo -e "${BLUE}=== Database Connection Info ===${NC}"
echo "Database: $DB_NAME"
echo "User: $DB_USER"
echo "Pod: $POD_NAME"
echo ""

# Check PostgreSQL version
echo -e "${BLUE}=== PostgreSQL Version ===${NC}"
kubectl exec -n "$NAMESPACE" "$POD_NAME" -- psql -U "$DB_USER" -c "SELECT version();" 2>/dev/null | grep -A 1 "version"

echo ""
echo -e "${BLUE}=== Database Size ===${NC}"
kubectl exec -n "$NAMESPACE" "$POD_NAME" -- psql -U "$DB_USER" -d "$DB_NAME" -c "
SELECT
    current_database() as database_name,
    pg_size_pretty(pg_database_size(current_database())) as database_size;
" 2>/dev/null

echo ""
echo -e "${BLUE}=== Table Count ===${NC}"
kubectl exec -n "$NAMESPACE" "$POD_NAME" -- psql -U "$DB_USER" -d "$DB_NAME" -c "
SELECT COUNT(*) as total_tables
FROM information_schema.tables
WHERE table_schema = 'public';
" 2>/dev/null

echo ""
echo -e "${BLUE}=== Top Tables by Size ===${NC}"
kubectl exec -n "$NAMESPACE" "$POD_NAME" -- psql -U "$DB_USER" -d "$DB_NAME" -c "
SELECT
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS total_size
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC
LIMIT 10;
" 2>/dev/null

echo ""
echo -e "${BLUE}=== Disk Usage ===${NC}"
kubectl exec -n "$NAMESPACE" "$POD_NAME" -- df -h /var/lib/postgresql/data 2>/dev/null

echo ""
echo -e "${GREEN}=== Data Check Complete ===${NC}"
echo ""
echo "To connect interactively:"
echo "  kubectl exec -it -n $NAMESPACE $POD_NAME -- psql -U $DB_USER -d $DB_NAME"
echo ""
echo "To run a custom query:"
echo "  kubectl exec -n $NAMESPACE $POD_NAME -- psql -U $DB_USER -d $DB_NAME -c \"YOUR QUERY\""
