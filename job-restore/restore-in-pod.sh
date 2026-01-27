#!/bin/bash

# Restore script designed to run inside a Kubernetes Job
# This script mounts the same PVC as PostgreSQL and reads the dump file from it

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
echo "Looking for dump file at: $RESTORE_PATH/$DUMP_FILE"
echo ""

# Wait for PostgreSQL to be ready
echo "Waiting for PostgreSQL to be ready..."
until pg_isready -h $PGHOST -p $PGPORT -U $PGUSER; do
  echo "Waiting for database connection..."
  sleep 5
done
echo -e "${GREEN}✓ PostgreSQL is ready${NC}"
echo ""

# Debug: Show what's in the mounted volume
echo -e "${YELLOW}Debug: Checking mounted volume contents...${NC}"
echo "Contents of $RESTORE_PATH:"
ls -lah "$RESTORE_PATH" || echo "Cannot list directory"
echo ""

# Try to find the dump file
DUMP_FULL_PATH="$RESTORE_PATH/$DUMP_FILE"

if [ ! -f "$DUMP_FULL_PATH" ]; then
  echo -e "${RED}ERROR: Dump file not found at $DUMP_FULL_PATH${NC}"
  echo ""
  echo "Searching for dump file in volume..."
  find "$RESTORE_PATH" -name "*.sql" -o -name "*.dump" 2>/dev/null || echo "No dump files found"
  echo ""
  echo "Please ensure:"
  echo "1. The copy step completed successfully (run ./1-copy-dump.sh)"
  echo "2. The dump file was copied to the correct location"
  echo "3. The PVC is correctly mounted"
  exit 1
fi

echo -e "${GREEN}✓ Dump file found!${NC}"
ls -lh "$DUMP_FULL_PATH"
echo ""

# Check disk space
echo -e "${YELLOW}Step 1: Checking available disk space...${NC}"
df -h "$RESTORE_PATH"
echo ""

# Detect dump format
echo -e "${YELLOW}Step 2: Detecting dump format...${NC}"
DUMP_HEADER=$(head -c 100 "$DUMP_FULL_PATH" | head -1)

if echo "$DUMP_HEADER" | grep -q "PGDMP"; then
  DUMP_FORMAT="custom"
  echo -e "${GREEN}✓ Detected: PostgreSQL custom-format dump${NC}"
  echo "Will use: pg_restore"
else
  DUMP_FORMAT="plain"
  echo -e "${GREEN}✓ Detected: Plain SQL dump${NC}"
  echo "Will use: psql"
fi
echo ""

# Start restore
echo -e "${YELLOW}Step 3: Starting database restore...${NC}"
echo "This process may take several minutes to hours depending on dump size"
echo "Format: $DUMP_FORMAT"
echo ""
echo "Restoring..."
echo ""

# Restore based on format
if [ "$DUMP_FORMAT" = "custom" ]; then
  pg_restore -h $PGHOST -p $PGPORT -U $PGUSER -d $PGDATABASE \
    --no-owner --no-acl --verbose \
    "$DUMP_FULL_PATH"
else
  psql -h $PGHOST -p $PGPORT -U $PGUSER -d $PGDATABASE \
    < "$DUMP_FULL_PATH"
fi

RESTORE_EXIT_CODE=$?

if [ $RESTORE_EXIT_CODE -eq 0 ]; then
  echo ""
  echo -e "${GREEN}✓ Database restored successfully!${NC}"
  echo ""

  # Show database info
  echo -e "${GREEN}=== Database Information ===${NC}"
  psql -h $PGHOST -p $PGPORT -U $PGUSER -d $PGDATABASE \
    -c "SELECT COUNT(*) as table_count FROM information_schema.tables WHERE table_schema = 'public';"

  echo ""
  echo -e "${YELLOW}Note: Dump file remains in persistent volume${NC}"
  echo "File location: $DUMP_FULL_PATH"
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
