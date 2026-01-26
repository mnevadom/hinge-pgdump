#!/bin/bash

set -e

# Configuration
DUMP_FILE="pg_dump.sql"
POD_NAME="dump-stager"
NAMESPACE="${OKTETO_NAMESPACE}"
DUMP_PATH="/input/db.dump"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Dump Copy Script - Copy to dump-stager Pod ===${NC}"
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

# Check if dump-stager pod exists
echo "Finding dump-stager pod..."
if ! kubectl get pod "$POD_NAME" -n "$NAMESPACE" &>/dev/null; then
    echo -e "${RED}Error: dump-stager pod not found!${NC}"
    echo ""
    echo "Please deploy the dump-stager pod first:"
    echo "  kubectl apply -f ../rds-dump-pod/dumps-pvc.yaml -n $NAMESPACE"
    echo "  kubectl apply -f ../rds-dump-pod/dump-stager-pod.yaml -n $NAMESPACE"
    echo ""
    echo "Available pods:"
    kubectl get pods -n "$NAMESPACE"
    exit 1
fi

echo -e "${GREEN}Found pod: ${POD_NAME}${NC}"
echo ""

# Check if pod is ready
POD_STATUS=$(kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.status.phase}')
if [ "$POD_STATUS" == "Succeeded" ] || [ "$POD_STATUS" == "Failed" ]; then
    echo -e "${YELLOW}Warning: Pod already completed (status: ${POD_STATUS})${NC}"
    echo ""
    echo "You may need to delete and recreate the pod:"
    echo "  kubectl delete pod $POD_NAME -n $NAMESPACE"
    echo "  kubectl apply -f ../rds-dump-pod/dump-stager-pod.yaml -n $NAMESPACE"
    echo ""
    read -p "Do you want to continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 0
    fi
elif [ "$POD_STATUS" != "Running" ]; then
    echo -e "${YELLOW}Warning: Pod is not running (status: ${POD_STATUS})${NC}"
    echo "Waiting for pod to be ready..."
    kubectl wait --for=condition=ready pod/$POD_NAME -n "$NAMESPACE" --timeout=60s || true
fi

# Check if dump file already exists in pod
echo "Checking if dump file already exists in pod..."
if kubectl exec -n "$NAMESPACE" "$POD_NAME" -- test -f "$DUMP_PATH" 2>/dev/null; then
    echo -e "${YELLOW}Warning: Dump file already exists in pod!${NC}"
    echo "Location: $DUMP_PATH"
    echo ""
    read -p "Do you want to overwrite it? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Copy cancelled. Using existing dump file."
        echo ""
        echo "To verify the existing file:"
        echo "  kubectl exec -n $NAMESPACE $POD_NAME -- ls -lh $DUMP_PATH"
        exit 0
    fi
    echo "Overwriting existing dump file..."
    echo ""
fi

echo -e "${YELLOW}Step 1: Copying dump file to dump-stager pod...${NC}"
echo "This may take several minutes for large files (10-60 min for 100GB)"
echo "Destination: $POD_NAME:$DUMP_PATH"
echo ""

# Copy to the dump-stager pod's /input directory
kubectl cp "../$DUMP_FILE" "$NAMESPACE/$POD_NAME:$DUMP_PATH"

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
kubectl exec -n "$NAMESPACE" "$POD_NAME" -- ls -lh "$DUMP_PATH"

# Check available disk space
echo ""
echo -e "${YELLOW}Step 3: Checking disk space in /input...${NC}"
kubectl exec -n "$NAMESPACE" "$POD_NAME" -- df -h /input

echo ""
echo -e "${GREEN}=== Copy Complete ===${NC}"
echo "Dump file location: $POD_NAME:$DUMP_PATH"
echo ""
echo -e "${GREEN}Next step:${NC}"
echo "The dump-stager pod will now process the dump and copy it to the shared PVC."
echo "Your restore job should automatically pick it up from the shared volume."
echo ""
echo "To monitor the dump-stager pod:"
echo "  kubectl logs -f $POD_NAME -n $NAMESPACE"
