#!/bin/bash

# Restore script designed to run inside a Kubernetes Job
# This script runs in a separate container that connects to PostgreSQL remotely

set -e

# Configuration from environment variables
PGHOST="${PGHOST:-main-dev-db}"
PGPORT="${PGPORT:-5432}"
PGUSER="${PGUSER:-postgres}"
PGDATABASE="${PGDATABASE:-mydatabase}"
RESTORE_PATH="${RESTORE_PATH:-/var/lib/postgresql/data}"
DUMP_FILE="${DUMP_FILE:-pg_dump.sql}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== PostgreSQL Restore Job ===${NC}"
echo "Database: $PGDATABASE"
echo "Host: $PGHOST:$PGPORT"
echo "User: $PGUSER"
echo ""

# Wait for PostgreSQL to be ready
echo "Waiting for PostgreSQL to be ready..."
until pg_isready -h $PGHOST -p $PGPORT -U $PGUSER; do
  echo "Waiting for database connection..."
  sleep 5
done
echo -e "${GREEN}✓ PostgreSQL is ready${NC}"
echo ""

# Verify dump file exists
echo -e "${YELLOW}Step 1: Verifying dump file exists...${NC}"
if [ ! -f "$RESTORE_PATH/$DUMP_FILE" ]; then
  echo -e "${RED}ERROR: Dump file not found at $RESTORE_PATH/$DUMP_FILE${NC}"
  echo "Please ensure the copy step completed successfully."
  exit 1
fi

# Show file info
ls -lh "$RESTORE_PATH/$DUMP_FILE"
echo -e "${GREEN}✓ Dump file found${NC}"
echo ""

# Check disk space
echo -e "${YELLOW}Step 2: Checking available disk space...${NC}"
df -h "$RESTORE_PATH"
echo ""

# Detect dump format
echo -e "${YELLOW}Step 3: Detecting dump format...${NC}"
DUMP_HEADER=$(head -c 100 "$RESTORE_PATH/$DUMP_FILE" | head -1)

if echo "$DUMP_HEADER" | grep -q "PGDMP"; then
  DUMP_FORMAT="custom"
  echo -e "${GREEN}✓ Detected: PostgreSQL custom-format dump${NC}"
  echo "Will use: pg_restore"
  RESTORE_CMD="pg_restore"
else
  DUMP_FORMAT="plain"
  echo -e "${GREEN}✓ Detected: Plain SQL dump${NC}"
  echo "Will use: psql"
  RESTORE_CMD="psql"
fi
echo ""

# Start restore
echo -e "${YELLOW}Step 4: Starting database restore...${NC}"
echo "This process may take several minutes to hours depending on dump size"
echo "Format: $DUMP_FORMAT"
echo "Command: $RESTORE_CMD"
echo ""
echo "Restoring..."
echo ""

# Restore based on format
if [ "$DUMP_FORMAT" = "custom" ]; then
  pg_restore -h $PGHOST -p $PGPORT -U $PGUSER -d $PGDATABASE \
    --no-owner --no-acl --verbose \
    "$RESTORE_PATH/$DUMP_FILE"
else
  psql -h $PGHOST -p $PGPORT -U $PGUSER -d $PGDATABASE \
    < "$RESTORE_PATH/$DUMP_FILE"
fi

RESTORE_EXIT_CODE=$?

if [ $RESTORE_EXIT_CODE -eq 0 ]; then
  echo ""
  echo -e "${GREEN}✓ Database restored successfully!${NC}"
  echo ""

  # Show database info
  echo -e "${GREEN}=== Database Information ===${NC}"
  psql -h $PGHOST -p $PGPORT -U $PGUSER -d $PGDATABASE -c "SELECT COUNT(*) as table_count FROM information_schema.tables WHERE table_schema = 'public';"

  echo ""
  echo -e "${YELLOW}Step 5: Dump file remains in persistent volume${NC}"
  echo "File location: $RESTORE_PATH/$DUMP_FILE"
  echo "The dump is stored in the persistent volume."
  echo ""
  echo "To remove it (to free up space), run:"
  echo "  kubectl exec -n \${OKTETO_NAMESPACE} -l stack.okteto.com/service=main-dev-db -- rm $RESTORE_PATH/$DUMP_FILE"

  echo ""
  echo -e "${GREEN}=== Restore Complete ===${NC}"
  echo "Job completed successfully at $(date)"
  exit 0
else
  echo ""
  echo -e "${RED}✗ Failed to restore database${NC}"
  echo "Exit code: $RESTORE_EXIT_CODE"
  exit 1
fi
