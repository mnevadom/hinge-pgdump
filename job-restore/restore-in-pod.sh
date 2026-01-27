#!/bin/bash

# Restore script for Kubernetes Job
# Connects to PostgreSQL and triggers a server-side restore

set -e

PGHOST="${PGHOST:-main-dev-db}"
PGPORT="${PGPORT:-5432}"
PGUSER="${PGUSER:-postgres}"
PGDATABASE="${PGDATABASE:-mydatabase}"
DUMP_PATH="${DUMP_PATH_IN_PG_POD:-/var/lib/postgresql/data/pg_dump.sql}"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=== PostgreSQL Restore Job ===${NC}"
echo "Database: $PGDATABASE @ $PGHOST:$PGPORT"
echo "Dump file path (in PG pod): $DUMP_PATH"
echo ""

# Wait for PostgreSQL
echo "Waiting for PostgreSQL..."
until pg_isready -h $PGHOST -p $PGPORT -U $PGUSER; do
  sleep 5
done
echo -e "${GREEN}✓ PostgreSQL is ready${NC}"
echo ""

# Wait for dump file to be available
echo "Waiting for dump file to be available..."
WAIT_COUNT=0
MAX_WAIT=60
while [ ! -f "$DUMP_PATH" ] && [ $WAIT_COUNT -lt $MAX_WAIT ]; do
  echo "Dump file not found yet, waiting... ($WAIT_COUNT/$MAX_WAIT)"
  sleep 5
  WAIT_COUNT=$((WAIT_COUNT + 1))
done

if [ ! -f "$DUMP_PATH" ]; then
  echo -e "${RED}✗ Dump file not found after waiting${NC}"
  echo "Expected location: $DUMP_PATH"
  echo ""
  echo "Contents of /var/lib/postgresql/data:"
  ls -lah /var/lib/postgresql/data || echo "Cannot list directory"
  echo ""
  echo "Please ensure:"
  echo "1. Copy step completed successfully (check logs)"
  echo "2. Dump file was copied to the correct location"
  echo "3. PVC is properly mounted"
  exit 1
fi

echo -e "${GREEN}✓ Dump file found: $DUMP_PATH${NC}"
ls -lh "$DUMP_PATH"
echo ""

# Try custom format first with pg_restore
echo -e "${YELLOW}Attempting restore with pg_restore (custom format)...${NC}"
if pg_restore -h $PGHOST -p $PGPORT -U $PGUSER -d $PGDATABASE \
  --no-owner --no-acl --verbose "$DUMP_PATH" 2>&1; then
  
  echo -e "${GREEN}✓ Restore successful (custom format)${NC}"
else
  echo -e "${YELLOW}Custom format failed, trying plain SQL...${NC}"
  
  # Try plain SQL format
  if psql -h $PGHOST -p $PGPORT -U $PGUSER -d $PGDATABASE -f "$DUMP_PATH" 2>&1; then
    echo -e "${GREEN}✓ Restore successful (plain SQL)${NC}"
  else
    echo -e "${RED}✗ Both restore methods failed${NC}"
    echo "Ensure dump file exists at: $DUMP_PATH"
    exit 1
  fi
fi

echo ""
psql -h $PGHOST -p $PGPORT -U $PGUSER -d $PGDATABASE \
  -c "SELECT COUNT(*) as tables FROM information_schema.tables WHERE table_schema = 'public';"

echo -e "${GREEN}=== Restore Complete ===${NC}"
