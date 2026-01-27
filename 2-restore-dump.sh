#!/bin/bash

# Note: NOT using 'set -e' because we need to handle kubectl errors gracefully
# and check exit codes manually

# Configuration
DUMP_FILE="pg_dump.sql"
POD_NAME=""
NAMESPACE="${OKTETO_NAMESPACE}"
DB_NAME="${TARGET_DB:-mydatabase}"
DB_USER="postgres"
RESTORE_PATH="/var/lib/postgresql/data"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== PostgreSQL Dump Restore Script ===${NC}"
echo ""

# Check if namespace is set
if [ -z "$NAMESPACE" ]; then
    echo -e "${RED}Error: OKTETO_NAMESPACE environment variable is not set!${NC}"
    echo ""
    echo "Please set it before running this script:"
    echo "  export OKTETO_NAMESPACE=your-namespace"
    echo "  ./2-restore-dump.sh"
    exit 1
fi

echo "Using namespace: $NAMESPACE"
echo ""

# Find the postgres pod
echo "Finding PostgreSQL pod..."
echo "Looking for pods with label: stack.okteto.com/service=main-dev-db"

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
    echo "Checking all pods in namespace '$NAMESPACE':"
    kubectl get pods -n "$NAMESPACE" 2>&1
    echo ""
    echo "Please ensure:"
    echo "1. PostgreSQL is deployed: okteto deploy --wait"
    echo "2. Dump has been copied: ./1-copy-dump.sh"
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

# Verify dump file exists in pod
echo -e "${YELLOW}Step 1: Verifying dump file exists in pod...${NC}"
if ! kubectl exec -n "$NAMESPACE" "$POD_NAME" -- test -f "$RESTORE_PATH/$DUMP_FILE" 2>/dev/null; then
    echo -e "${RED}Error: Dump file not found in pod!${NC}"
    echo "Expected location: $RESTORE_PATH/$DUMP_FILE"
    echo ""
    echo "Please run the copy script first:"
    echo "  ./1-copy-dump.sh"
    exit 1
fi

# Show file info
kubectl exec -n "$NAMESPACE" "$POD_NAME" -- ls -lh "$RESTORE_PATH/$DUMP_FILE"
echo -e "${GREEN}✓ Dump file found${NC}"

# Check disk space
echo ""
echo -e "${YELLOW}Step 2: Checking available disk space...${NC}"
kubectl exec -n "$NAMESPACE" "$POD_NAME" -- df -h "$RESTORE_PATH"

# Detect dump format
echo ""
echo -e "${YELLOW}Step 3: Detecting dump format...${NC}"
DUMP_HEADER=$(kubectl exec -n "$NAMESPACE" "$POD_NAME" -- head -c 100 "$RESTORE_PATH/$DUMP_FILE" 2>/dev/null | head -1)

# Check if it's a custom format dump (starts with "PGDMP")
if echo "$DUMP_HEADER" | grep -q "PGDMP"; then
    DUMP_FORMAT="custom"
    RESTORE_COMMAND="pg_restore -U $DB_USER -d $DB_NAME --no-owner --no-acl --verbose $RESTORE_PATH/$DUMP_FILE"
    echo -e "${GREEN}✓ Detected: PostgreSQL custom-format dump${NC}"
    echo "Will use: pg_restore"
else
    DUMP_FORMAT="plain"
    RESTORE_COMMAND="psql -U $DB_USER -d $DB_NAME < $RESTORE_PATH/$DUMP_FILE"
    echo -e "${GREEN}✓ Detected: Plain SQL dump${NC}"
    echo "Will use: psql"
fi

echo ""
echo -e "${YELLOW}Step 4: Starting database restore...${NC}"
echo "This process may take several minutes to hours depending on dump size"
echo "Database: $DB_NAME"
echo "User: $DB_USER"
echo "Format: $DUMP_FORMAT"
echo ""
echo "Restoring..."

# Restore the dump using the appropriate method
kubectl exec -n "$NAMESPACE" "$POD_NAME" -- bash -c "$RESTORE_COMMAND"

if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✓ Database restored successfully!${NC}"

    # Show database info
    echo ""
    echo -e "${GREEN}=== Database Information ===${NC}"
    kubectl exec -n "$NAMESPACE" "$POD_NAME" -- psql -U "$DB_USER" -d "$DB_NAME" -c "SELECT COUNT(*) as table_count FROM information_schema.tables WHERE table_schema = 'public';"

    echo ""
    echo -e "${YELLOW}Step 5: Dump file remains in persistent volume${NC}"
    echo "File location: $RESTORE_PATH/$DUMP_FILE"
    echo "The dump is stored in the persistent volume, not consuming node resources."
    echo ""
    echo "To view the file:"
    echo "  kubectl exec -n $NAMESPACE $POD_NAME -- ls -lh $RESTORE_PATH/$DUMP_FILE"
    echo ""
    echo "To remove it if needed (to free up space):"
    echo "  kubectl exec -n $NAMESPACE $POD_NAME -- rm $RESTORE_PATH/$DUMP_FILE"

else
    echo -e "${RED}✗ Failed to restore database${NC}"
    echo "You can check the logs with:"
    echo "  kubectl logs -n $NAMESPACE $POD_NAME"
    exit 1
fi

echo ""
echo -e "${GREEN}=== Restore Complete ===${NC}"
echo "You can now access your database with:"
echo "  kubectl exec -it -n $NAMESPACE $POD_NAME -- psql -U $DB_USER -d $DB_NAME"
