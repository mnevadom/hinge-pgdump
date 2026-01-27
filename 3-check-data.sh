#!/bin/bash

set -e

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

POD_NAME=$(kubectl get pods -n "$NAMESPACE" -l stack.okteto.com/service=main-dev-db -o jsonpath='{.items[0].metadata.name}' 2>&1)

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
echo -e "${BLUE}=== Tables with Row Counts ===${NC}"
kubectl exec -n "$NAMESPACE" "$POD_NAME" -- psql -U "$DB_USER" -d "$DB_NAME" -c "
SELECT
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS total_size,
    (SELECT COUNT(*) FROM information_schema.columns WHERE table_schema = schemaname AND table_name = tablename) as column_count
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC
LIMIT 20;
" 2>/dev/null

echo ""
echo -e "${BLUE}=== Row Counts for Top Tables ===${NC}"
echo "Getting row counts (this may take a moment for large tables)..."
echo ""

# Get row counts for each table
TABLES=$(kubectl exec -n "$NAMESPACE" "$POD_NAME" -- psql -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT tablename FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename LIMIT 20;" 2>/dev/null)

if [ -n "$TABLES" ]; then
    printf "%-40s %15s\n" "Table Name" "Row Count"
    printf "%-40s %15s\n" "----------------------------------------" "---------------"

    while IFS= read -r table; do
        # Trim whitespace
        table=$(echo "$table" | xargs)
        if [ -n "$table" ]; then
            ROW_COUNT=$(kubectl exec -n "$NAMESPACE" "$POD_NAME" -- psql -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT COUNT(*) FROM \"$table\";" 2>/dev/null | xargs)
            printf "%-40s %15s\n" "$table" "$ROW_COUNT"
        fi
    done <<< "$TABLES"
else
    echo "No tables found in public schema."
fi

echo ""
echo -e "${BLUE}=== Indexes ===${NC}"
kubectl exec -n "$NAMESPACE" "$POD_NAME" -- psql -U "$DB_USER" -d "$DB_NAME" -c "
SELECT
    schemaname,
    tablename,
    indexname,
    pg_size_pretty(pg_relation_size(indexname::regclass)) as index_size
FROM pg_indexes
WHERE schemaname = 'public'
ORDER BY pg_relation_size(indexname::regclass) DESC
LIMIT 15;
" 2>/dev/null

echo ""
echo -e "${BLUE}=== Sequences ===${NC}"
kubectl exec -n "$NAMESPACE" "$POD_NAME" -- psql -U "$DB_USER" -d "$DB_NAME" -c "
SELECT
    schemaname,
    sequencename,
    last_value
FROM pg_sequences
WHERE schemaname = 'public'
ORDER BY sequencename;
" 2>/dev/null

echo ""
echo -e "${BLUE}=== Views ===${NC}"
kubectl exec -n "$NAMESPACE" "$POD_NAME" -- psql -U "$DB_USER" -d "$DB_NAME" -c "
SELECT
    schemaname,
    viewname
FROM pg_views
WHERE schemaname = 'public'
ORDER BY viewname;
" 2>/dev/null

echo ""
echo -e "${BLUE}=== Foreign Keys ===${NC}"
kubectl exec -n "$NAMESPACE" "$POD_NAME" -- psql -U "$DB_USER" -d "$DB_NAME" -c "
SELECT
    tc.table_name,
    kcu.column_name,
    ccu.table_name AS foreign_table_name,
    ccu.column_name AS foreign_column_name
FROM information_schema.table_constraints AS tc
JOIN information_schema.key_column_usage AS kcu
    ON tc.constraint_name = kcu.constraint_name
    AND tc.table_schema = kcu.table_schema
JOIN information_schema.constraint_column_usage AS ccu
    ON ccu.constraint_name = tc.constraint_name
    AND ccu.table_schema = tc.table_schema
WHERE tc.constraint_type = 'FOREIGN KEY'
    AND tc.table_schema = 'public'
ORDER BY tc.table_name, kcu.column_name
LIMIT 20;
" 2>/dev/null

echo ""
echo -e "${BLUE}=== Disk Usage ===${NC}"
kubectl exec -n "$NAMESPACE" "$POD_NAME" -- df -h /var/lib/postgresql/data 2>/dev/null

echo ""
echo -e "${BLUE}=== Recent Activity ===${NC}"
kubectl exec -n "$NAMESPACE" "$POD_NAME" -- psql -U "$DB_USER" -d "$DB_NAME" -c "
SELECT
    datname,
    numbackends as connections,
    xact_commit as commits,
    xact_rollback as rollbacks,
    blks_read as disk_blocks_read,
    blks_hit as cache_hits,
    tup_returned as rows_returned,
    tup_fetched as rows_fetched,
    tup_inserted as rows_inserted,
    tup_updated as rows_updated,
    tup_deleted as rows_deleted
FROM pg_stat_database
WHERE datname = '$DB_NAME';
" 2>/dev/null

echo ""
echo -e "${GREEN}=== Data Check Complete ===${NC}"
echo ""
echo "To connect interactively:"
echo "  kubectl exec -it -n $NAMESPACE $POD_NAME -- psql -U $DB_USER -d $DB_NAME"
echo ""
echo "To run a custom query:"
echo "  kubectl exec -n $NAMESPACE $POD_NAME -- psql -U $DB_USER -d $DB_NAME -c \"YOUR QUERY\""
