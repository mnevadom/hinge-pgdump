#!/bin/bash

set -e

# Configuration
DUMP_FILE="pg_dump.sql"
POD_NAME=""
NAMESPACE="${OKTETO_NAMESPACE}"
RESTORE_PATH="/var/lib/postgresql/data"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== PostgreSQL Dump Copy Script (Step 1/2) ===${NC}"
echo ""

# Check if dump file exists in parent directory
if [ ! -f "../$DUMP_FILE" ]; then
    echo -e "${RED}Error: Dump file '../$DUMP_FILE' not found!${NC}"
    echo "Please ensure you have a file named 'pg_dump.sql' in the project root directory"
    echo "Expected location: $(pwd)/../$DUMP_FILE"
    exit 1
fi

# Get file size
DUMP_SIZE=$(du -h "../$DUMP_FILE" | cut -f1)
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

# Check if dump file already exists in pod
echo "Checking if dump file already exists in pod..."
if kubectl exec -n "$NAMESPACE" "$POD_NAME" -- test -f "$RESTORE_PATH/$DUMP_FILE" 2>/dev/null; then
    echo -e "${YELLOW}Warning: Dump file already exists in pod!${NC}"
    echo "Location: $RESTORE_PATH/$DUMP_FILE"
    echo ""
    read -p "Do you want to overwrite it? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Copy cancelled. Using existing dump file."
        echo ""
        echo "To verify the existing file:"
        echo "  kubectl exec -n $NAMESPACE $POD_NAME -- ls -lh $RESTORE_PATH/$DUMP_FILE"
        echo ""
        echo "To proceed with restore, run: ./2-restore-dump.sh"
        exit 0
    fi
    echo "Overwriting existing dump file..."
    echo ""
fi

echo -e "${YELLOW}Step 1: Copying dump file to persistent volume...${NC}"
echo "This may take several minutes for large files (10-60 min for 100GB)"
echo "Destination: $RESTORE_PATH/$DUMP_FILE"
echo ""

# Copy with progress indication
kubectl cp "../$DUMP_FILE" "$NAMESPACE/$POD_NAME:$RESTORE_PATH/$DUMP_FILE"

if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✓ Dump file copied successfully!${NC}"
else
    echo ""
    echo -e "${RED}✗ Failed to copy dump file${NC}"
    exit 1
fi

echo ""
echo -e "${YELLOW}Step 2: Verifying file in pod...${NC}"
kubectl exec -n "$NAMESPACE" "$POD_NAME" -- ls -lh "$RESTORE_PATH/$DUMP_FILE"

# Check available disk space
echo ""
echo -e "${YELLOW}Step 3: Checking disk space...${NC}"
kubectl exec -n "$NAMESPACE" "$POD_NAME" -- df -h "$RESTORE_PATH"

echo ""
echo -e "${GREEN}=== Copy Complete ===${NC}"
echo "Dump file location: $RESTORE_PATH/$DUMP_FILE"
echo "File is stored in the persistent volume (not consuming node resources)"
echo ""
echo -e "${GREEN}Next step: Run the restore script${NC}"
echo "  cd postgres-infra"
echo "  ./2-restore-dump.sh"
