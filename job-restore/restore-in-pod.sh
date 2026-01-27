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
