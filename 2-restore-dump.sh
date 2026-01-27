#!/bin/bash

set -e

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

# Find the postgres pod
echo "Finding PostgreSQL pod..."
POD_NAME=$(kubectl get pods -n "$NAMESPACE" -l stack.okteto.com/service=main-dev-db -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -z "$POD_NAME" ]; then
    echo -e "${RED}Error: Could not find PostgreSQL pod with label 'stack.okteto.com/service=main-dev-db'${NC}"
    echo "Available pods:"
    kubectl get pods -n "$NAMESPACE"
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

echo ""
echo -e "${YELLOW}Step 3: Starting database restore...${NC}"
echo "This process may take several minutes to hours depending on dump size"
echo "Database: $DB_NAME"
echo "User: $DB_USER"
echo ""
echo "Restoring..."

# Restore the dump
kubectl exec -n "$NAMESPACE" "$POD_NAME" -- bash -c "psql -U $DB_USER -d $DB_NAME < $RESTORE_PATH/$DUMP_FILE"

if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✓ Database restored successfully!${NC}"

    # Show database info
    echo ""
    echo -e "${GREEN}=== Database Information ===${NC}"
    kubectl exec -n "$NAMESPACE" "$POD_NAME" -- psql -U "$DB_USER" -d "$DB_NAME" -c "SELECT COUNT(*) as table_count FROM information_schema.tables WHERE table_schema = 'public';"

    echo ""
    echo -e "${YELLOW}Step 4: Dump file remains in persistent volume${NC}"
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
