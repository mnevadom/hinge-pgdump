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

# Check if dump file exists
if [ ! -f "$DUMP_FILE" ]; then
    echo -e "${RED}Error: Dump file '$DUMP_FILE' not found in current directory!${NC}"
    echo "Please ensure you have a file named 'pg_dump.sql' (or update DUMP_FILE variable)"
    exit 1
fi

# Get file size
DUMP_SIZE=$(du -h "$DUMP_FILE" | cut -f1)
echo -e "${YELLOW}Dump file size: ${DUMP_SIZE}${NC}"
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

echo -e "${YELLOW}Step 1: Copying dump file to pod (this may take several minutes for large files)...${NC}"
kubectl cp "$DUMP_FILE" "$NAMESPACE/$POD_NAME:$RESTORE_PATH/$DUMP_FILE"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Dump file copied successfully${NC}"
else
    echo -e "${RED}✗ Failed to copy dump file${NC}"
    exit 1
fi

echo ""
echo -e "${YELLOW}Step 2: Verifying file in pod...${NC}"
kubectl exec -n "$NAMESPACE" "$POD_NAME" -- ls -lh "$RESTORE_PATH/$DUMP_FILE"

echo ""
echo -e "${YELLOW}Step 3: Restoring database dump (this will take time for large dumps)...${NC}"
echo "This process may take several minutes to hours depending on dump size..."

# Restore the dump
kubectl exec -n "$NAMESPACE" "$POD_NAME" -- bash -c "psql -U $DB_USER -d $DB_NAME < $RESTORE_PATH/$DUMP_FILE"

if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✓ Database restored successfully!${NC}"

    # Keep dump in volume
    echo ""
    echo -e "${YELLOW}Step 4: Dump file kept in persistent volume for future reference${NC}"
    echo "File location: $RESTORE_PATH/$DUMP_FILE"
    echo "The dump is stored in the persistent volume, not consuming node resources."
    echo ""
    echo "To view the file later:"
    echo "  kubectl exec -n $NAMESPACE $POD_NAME -- ls -lh $RESTORE_PATH/$DUMP_FILE"
    echo ""
    echo "To remove it if needed:"
    echo "  kubectl exec -n $NAMESPACE $POD_NAME -- rm $RESTORE_PATH/$DUMP_FILE"

    # Show database info
    echo ""
    echo -e "${GREEN}=== Database Information ===${NC}"
    kubectl exec -n "$NAMESPACE" "$POD_NAME" -- psql -U "$DB_USER" -d "$DB_NAME" -c "SELECT COUNT(*) as table_count FROM information_schema.tables WHERE table_schema = 'public';"

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
