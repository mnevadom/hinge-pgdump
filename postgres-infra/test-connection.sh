#!/bin/bash

# Simple script to test PostgreSQL connection and show database info

NAMESPACE="${OKTETO_NAMESPACE}"
DB_NAME="${TARGET_DB:-mydatabase}"

echo "=== Testing PostgreSQL Connection ==="
echo ""

# Find pod
POD_NAME=$(kubectl get pods -n "$NAMESPACE" -l stack.okteto.com/service=main-dev-db -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -z "$POD_NAME" ]; then
    echo "❌ Error: PostgreSQL pod not found"
    echo "Run 'okteto deploy --wait' first"
    exit 1
fi

echo "✓ Found pod: $POD_NAME"
echo ""

# Test connection
echo "Testing database connection..."
if kubectl exec -n "$NAMESPACE" "$POD_NAME" -- psql -U postgres -c "SELECT 1;" > /dev/null 2>&1; then
    echo "✓ Connection successful"
else
    echo "❌ Connection failed"
    exit 1
fi

echo ""
echo "=== Database Info ==="
kubectl exec -n "$NAMESPACE" "$POD_NAME" -- psql -U postgres -d "$DB_NAME" -c "
SELECT
    current_database() as database_name,
    pg_size_pretty(pg_database_size(current_database())) as database_size;
"

echo ""
echo "=== Tables ==="
kubectl exec -n "$NAMESPACE" "$POD_NAME" -- psql -U postgres -d "$DB_NAME" -c "
SELECT
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;
"

echo ""
echo "=== Connection String ==="
echo "Host: main-dev-db.${NAMESPACE}.svc.cluster.local"
echo "Port: 5432"
echo "Database: $DB_NAME"
echo "User: postgres"
echo ""
echo "To connect interactively:"
echo "  kubectl exec -it -n $NAMESPACE $POD_NAME -- psql -U postgres -d $DB_NAME"
