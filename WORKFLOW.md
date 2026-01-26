# Database Restore Workflow

## Overview

This document explains the complete workflow for restoring a large PostgreSQL dump (up to 100GB+) in Okteto.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Okteto Namespace                         │
│                                                              │
│  ┌────────────────────────────────────────────────────┐    │
│  │  StatefulSet: main-dev-db                          │    │
│  │                                                     │    │
│  │  ┌─────────────────────────────────────────┐      │    │
│  │  │  Pod: main-dev-db-0                     │      │    │
│  │  │                                          │      │    │
│  │  │  ┌────────────────────────────────┐    │      │    │
│  │  │  │   PostgreSQL 13                │    │      │    │
│  │  │  │   Port: 5432                   │    │      │    │
│  │  │  │   DB: mydatabase               │    │      │    │
│  │  │  └────────────────────────────────┘    │      │    │
│  │  │           ↓                             │      │    │
│  │  │  ┌────────────────────────────────┐    │      │    │
│  │  │  │   Persistent Volume            │    │      │    │
│  │  │  │   Size: 70Gi                   │    │      │    │
│  │  │  │   Path: /var/lib/postgresql/   │    │      │    │
│  │  │  └────────────────────────────────┘    │      │    │
│  │  └─────────────────────────────────────────┘      │    │
│  └────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

## Restore Process Flow

```
┌──────────────────────┐
│  1. Prepare Dump     │
│  Place pg_dump.sql   │
│  in project root     │
└──────┬───────────────┘
       │
       ↓
┌──────────────────────┐
│  2. Run Script       │
│  ./restore-dump.sh   │
└──────┬───────────────┘
       │
       ↓
┌──────────────────────────────────────────┐
│  3. Script Execution                     │
│  ┌────────────────────────────────┐     │
│  │ a) Find PostgreSQL pod         │     │
│  │    (auto-discovery via labels) │     │
│  └────────────┬───────────────────┘     │
│               ↓                          │
│  ┌────────────────────────────────┐     │
│  │ b) Copy dump to pod            │     │
│  │    Local → Volume:/var/lib/    │     │
│  │           postgresql/data      │     │
│  │    (may take 10-60 min for     │     │
│  │     100GB depending on network) │     │
│  └────────────┬───────────────────┘     │
│               ↓                          │
│  ┌────────────────────────────────┐     │
│  │ c) Restore database            │     │
│  │    psql < pg_dump.sql          │     │
│  │    (1-3+ hours for 100GB)      │     │
│  └────────────┬───────────────────┘     │
│               ↓                          │
│  ┌────────────────────────────────┐     │
│  │ d) Keep dump in volume         │     │
│  │    Stored in persistent volume │     │
│  │    for future reference        │     │
│  └────────────┬───────────────────┘     │
│               ↓                          │
│  ┌────────────────────────────────┐     │
│  │ e) Show statistics             │     │
│  │    Table count, sizes, etc.    │     │
│  └────────────────────────────────┘     │
└──────────────────────────────────────────┘
       │
       ↓
┌──────────────────────┐
│  4. Verify Data      │
│  Query database      │
│  Check table counts  │
└──────────────────────┘
```

## Detailed Steps

### Step 1: Initial Deployment

```bash
# Deploy PostgreSQL to Okteto
okteto deploy --wait

# Verify deployment
kubectl get pods -n ${OKTETO_NAMESPACE}
```

**Expected output:**
```
NAME              READY   STATUS    RESTARTS   AGE
main-dev-db-0     1/1     Running   0          2m
```

### Step 2: Prepare Database Dump

```bash
# If compressed, decompress first
gunzip your-dump.sql.gz

# Rename to expected filename
mv your-dump.sql pg_dump.sql

# Check file size
du -h pg_dump.sql
```

### Step 3: Run Restore Script

```bash
# Make script executable (if not already)
chmod +x restore-dump.sh

# Execute restore
./restore-dump.sh
```

**Script performs:**
1. ✓ Validates dump file exists locally
2. ✓ Discovers PostgreSQL pod automatically
3. ✓ Checks pod is in Running state
4. ✓ Copies dump file to pod (shows progress)
5. ✓ Verifies file copied successfully
6. ✓ Restores database using psql
7. ✓ Removes temporary files
8. ✓ Shows database statistics

### Step 4: Monitor Progress (Optional)

```bash
# In separate terminal, watch logs
kubectl logs -f -n ${OKTETO_NAMESPACE} main-dev-db-0

# Check resource usage
kubectl top pod -n ${OKTETO_NAMESPACE} main-dev-db-0

# Check disk usage inside pod
kubectl exec -n ${OKTETO_NAMESPACE} main-dev-db-0 -- df -h
```

### Step 5: Verify Restoration

```bash
# Test connection
./test-connection.sh

# Check table count
kubectl exec -n ${OKTETO_NAMESPACE} main-dev-db-0 -- \
  psql -U postgres -d mydatabase -c \
  "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';"

# Check database size
kubectl exec -n ${OKTETO_NAMESPACE} main-dev-db-0 -- \
  psql -U postgres -d mydatabase -c \
  "SELECT pg_size_pretty(pg_database_size('mydatabase'));"

# Interactive access
kubectl exec -it -n ${OKTETO_NAMESPACE} main-dev-db-0 -- \
  psql -U postgres -d mydatabase
```

## Time Estimates

| Dump Size | Network Copy | Database Restore | Total Time |
|-----------|--------------|------------------|------------|
| 1 GB      | 1-2 min      | 5-10 min         | ~15 min    |
| 10 GB     | 5-15 min     | 20-40 min        | ~1 hour    |
| 50 GB     | 20-40 min    | 1-2 hours        | ~2-3 hours |
| 100 GB    | 30-60 min    | 2-4 hours        | ~3-5 hours |

*Times vary based on:*
- Network speed (copy phase)
- Data complexity (restore phase)
- Number of indexes (restore phase)
- Cluster load (both phases)

## Data Flow Diagram

```
┌─────────────────┐
│  Local Machine  │
│                 │
│  pg_dump.sql    │
│  (100GB)        │
└────────┬────────┘
         │ kubectl cp
         │ (30-60 min)
         ↓
┌──────────────────────────────────────────┐
│  Kubernetes Pod: main-dev-db-0           │
│                                          │
│  ┌────────────────────────────────────┐ │
│  │  Persistent Volume (70Gi)          │ │
│  │  /var/lib/postgresql/data          │ │
│  │                                    │ │
│  │  ┌──────────────────────────────┐ │ │
│  │  │  pg_dump.sql (copied here)   │ │ │
│  │  │  (100GB - stored in volume)  │ │ │
│  │  └──────────┬───────────────────┘ │ │
│  │             │ psql < dump         │ │
│  │             │ (2-4 hours)         │ │
│  │             ↓                     │ │
│  │  ┌──────────────────────────────┐ │ │
│  │  │  PostgreSQL Database         │ │ │
│  │  │  Tables, Indexes, Data       │ │ │
│  │  └──────────────────────────────┘ │ │
│  │                                    │ │
│  │  Both dump and database data are  │ │
│  │  in the same persistent volume    │ │
│  └────────────────────────────────────┘ │
└──────────────────────────────────────────┘
```

## Script Architecture

```
restore-dump.sh
├── Configuration
│   ├── Read environment variables
│   ├── Set dump filename
│   └── Define colors for output
│
├── Validation
│   ├── Check dump file exists locally
│   ├── Get file size
│   └── Report to user
│
├── Pod Discovery
│   ├── Query Kubernetes for pod
│   ├── Use label selector
│   └── Verify pod is Running
│
├── File Copy
│   ├── kubectl cp to pod
│   ├── Target: /tmp directory
│   └── Verify copy success
│
├── Database Restore
│   ├── Execute psql in pod
│   ├── Redirect from dump file
│   └── Stream output to user
│
├── Cleanup
│   ├── Remove temp file from pod
│   └── Verify deletion
│
└── Reporting
    ├── Show table count
    ├── Display connection info
    └── Provide next steps
```

## Troubleshooting Flow

```
                    ┌─────────────┐
                    │   Issue?    │
                    └──────┬──────┘
                           │
         ┌─────────────────┼─────────────────┐
         │                 │                 │
    ┌────▼────┐       ┌────▼────┐      ┌────▼────┐
    │Pod not  │       │Copy     │      │Restore  │
    │found    │       │fails    │      │fails    │
    └────┬────┘       └────┬────┘      └────┬────┘
         │                 │                 │
         │                 │                 │
    ┌────▼──────────┐ ┌────▼──────────┐ ┌──▼────────────┐
    │Check:         │ │Check:         │ │Check:         │
    │- Deployment   │ │- Network      │ │- Disk space   │
    │- Pod status   │ │- Disk space   │ │- Dump format  │
    │- Labels       │ │- Permissions  │ │- PG version   │
    └───────────────┘ └───────────────┘ └───────────────┘
```

## Best Practices

### Before Restore
1. ✓ Ensure dump file is uncompressed (.sql not .sql.gz)
2. ✓ Check available disk space (70Gi available)
3. ✓ Verify PostgreSQL version compatibility (dump → PG 13)
4. ✓ Test with small sample first (optional)

### During Restore
1. ✓ Monitor logs for errors
2. ✓ Don't interrupt the process
3. ✓ Watch resource usage
4. ✓ Keep terminal session alive

### After Restore
1. ✓ Verify table counts match source
2. ✓ Check critical tables have data
3. ✓ Run sample queries
4. ✓ Validate foreign keys and constraints
5. ✓ Check database size matches expected

## Performance Optimization

The PostgreSQL instance is pre-configured with:

```sql
-- Already set in docker-compose.yml
max_wal_size = 4GB              -- Large transactions
checkpoint_timeout = 15min       -- Less frequent checkpoints
```

**Resources allocated:**
- CPU: 500m request, 2 cores limit
- Memory: 2Gi request, 8Gi limit
- Storage: 70Gi persistent volume

These settings optimize for bulk data loading operations.

## Recovery Scenarios

### If restore fails halfway:

```bash
# 1. Check what was restored
kubectl exec -n ${OKTETO_NAMESPACE} main-dev-db-0 -- \
  psql -U postgres -d mydatabase -c "\dt"

# 2. Drop and recreate database (if needed)
kubectl exec -n ${OKTETO_NAMESPACE} main-dev-db-0 -- \
  psql -U postgres -c "DROP DATABASE IF EXISTS mydatabase;"

kubectl exec -n ${OKTETO_NAMESPACE} main-dev-db-0 -- \
  psql -U postgres -c "CREATE DATABASE mydatabase;"

# 3. Re-run restore script
./restore-dump.sh
```

### If out of disk space:

```bash
# 1. Check current usage
kubectl exec -n ${OKTETO_NAMESPACE} main-dev-db-0 -- df -h

# 2. Increase volume size (edit docker-compose.yml)
# Update size under volumes.main-dev-data.driver_opts.size

# 3. Redeploy
okteto deploy --wait
```

## Security Considerations

1. **Dump files contain sensitive data**
   - .gitignore excludes pg_dump.sql
   - Don't commit dumps to version control
   - Delete after successful restore

2. **Database credentials**
   - Change default password in .env
   - Don't commit .env with real passwords
   - Use Okteto secrets for production

3. **Network access**
   - Database is internal only (ClusterIP)
   - Not exposed to public internet
   - Access via kubectl only

## Summary Checklist

- [ ] Deploy PostgreSQL: `okteto deploy --wait`
- [ ] Place dump file: `pg_dump.sql` in project root
- [ ] Run restore: `./restore-dump.sh`
- [ ] Monitor progress: `kubectl logs -f`
- [ ] Verify data: `./test-connection.sh`
- [ ] Test queries: Interactive psql session
- [ ] Clean up: Remove local dump file
- [ ] Document: Note any issues or customizations

---

**Need Help?** Check README.md for troubleshooting or consult the Okteto documentation.
