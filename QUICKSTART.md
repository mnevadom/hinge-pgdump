# Quick Start Guide

## 1. Deploy PostgreSQL to Okteto

```bash
okteto deploy --wait
```

Wait for the deployment to complete (usually 1-2 minutes).

## 2. Verify Deployment

```bash
# Check if pod is running
kubectl get pods -n ${OKTETO_NAMESPACE}

# Verify PostgreSQL is working
kubectl exec -n ${OKTETO_NAMESPACE} -l stack.okteto.com/service=main-dev-db -- psql -U postgres -c "SELECT version();"
```

## 3. Prepare Your Database Dump

Place your PostgreSQL dump file in the project root:

```bash
# Rename your dump file
mv your-database-dump.sql pg_dump.sql

# Or if it's compressed
gunzip your-dump.sql.gz
mv your-dump.sql pg_dump.sql
```

**Note**: For very large dumps (100GB), ensure:
- Dump file is uncompressed (for faster restore)
- You have enough local disk space
- Network connection is stable during copy

## 4. Restore Your Database

### Option A: Two-Step Process (Recommended)

**Step 1: Copy the dump to the persistent volume**
```bash
cd postgres-infra
./1-copy-dump.sh
```
*Time: 30-60 minutes for 100GB*

**Step 2: Restore the database**
```bash
./2-restore-dump.sh
```
*Time: 2-4 hours for 100GB*

### Option B: All-in-One

```bash
cd postgres-infra
./restore-dump-all-in-one.sh
```

The script will automatically:
- ✓ Find the PostgreSQL pod
- ✓ Copy the dump file to the persistent volume `/var/lib/postgresql/data` (progress shown)
- ✓ Restore the database from the volume
- ✓ Keep the dump in the persistent volume (not consuming node resources)
- ✓ Show database statistics

**Note**: The dump is stored in the persistent volume, so it doesn't consume node ephemeral storage and remains available for future reference.

## 5. Access Your Database

```bash
# Interactive shell
kubectl exec -it -n ${OKTETO_NAMESPACE} -l stack.okteto.com/service=main-dev-db -- psql -U postgres -d mydatabase

# Run a query
kubectl exec -n ${OKTETO_NAMESPACE} -l stack.okteto.com/service=main-dev-db -- psql -U postgres -d mydatabase -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';"
```

## Troubleshooting

### Script can't find dump file
```bash
# Ensure dump is in project root (not in postgres-infra)
ls -lh pg_dump.sql

# If you're in postgres-infra folder, the script looks in parent directory
ls -lh ../pg_dump.sql
```

### Script can't find pod
```bash
# List all pods
kubectl get pods -n ${OKTETO_NAMESPACE}

# Redeploy if needed
okteto deploy --wait
```

### Out of storage space
```bash
# Check available space
kubectl exec -n ${OKTETO_NAMESPACE} -l stack.okteto.com/service=main-dev-db -- df -h

# If needed, increase volume size in postgres-infra/docker-compose.yml (within quota limits)
# Then redeploy
okteto deploy --wait
```

### Restore is slow
- This is normal for large dumps (100GB can take 2-4+ hours for restore alone)
- Monitor progress: `kubectl logs -f -n ${OKTETO_NAMESPACE} -l stack.okteto.com/service=main-dev-db`
- PostgreSQL is configured with optimized settings for bulk operations

## Example: Testing with Sample Data

Try the example dump first:

```bash
# Use the example dump
cp pg_dump.sql.example pg_dump.sql

# Run restore (two-step)
cd postgres-infra
./1-copy-dump.sh
./2-restore-dump.sh

# Verify data
kubectl exec -n ${OKTETO_NAMESPACE} -l stack.okteto.com/service=main-dev-db -- psql -U postgres -d mydatabase -c "SELECT * FROM users;"
```

## Configuration

Edit `postgres-infra/.env` to change database settings:

```bash
TARGET_DB=mydatabase           # Your database name
ROLE_PASSWORD=mysecretpassword # PostgreSQL password (change this!)
```

After changing, redeploy:

```bash
okteto deploy --wait
```

## Time Estimates

| Dump Size | Copy (Step 1) | Restore (Step 2) | Total  |
|-----------|---------------|------------------|--------|
| 1 GB      | 1-2 min       | 5-10 min         | 15 min |
| 10 GB     | 5-15 min      | 20-40 min        | 1 hour |
| 50 GB     | 20-40 min     | 1-2 hours        | 3 hours|
| 100 GB    | 30-60 min     | 2-4 hours        | 5 hours|

## Why Use Two Scripts?

Separating copy and restore provides:
- ✅ Clear progress tracking for each phase
- ✅ Ability to verify copy before starting restore
- ✅ Resume from restore if it fails (no need to re-copy)
- ✅ Better error isolation and troubleshooting

For a 100GB dump, you'll wait 30-60 minutes for copy, then can start the 2-4 hour restore knowing the file is safely in the volume!
