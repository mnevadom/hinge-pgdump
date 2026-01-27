# PostgreSQL Okteto Project

This project deploys a PostgreSQL 13 database on Okteto with support for restoring large database dumps (up to 100GB+).

## Project Structure

```
.
├── okteto.yml                      # Okteto manifest with automated deployment
├── pg_dump.sql                     # Your PostgreSQL dump file (place here)
├── 1-copy-dump.sh                  # Step 1: Copy dump to PostgreSQL pod
├── 2-restore-dump.sh               # Step 2: Restore database
├── 3-check-data.sh                 # Check restored data and statistics
├── postgres-infra/                 # PostgreSQL infrastructure
│   ├── docker-compose.yml          # PostgreSQL service definition
│   ├── .env                        # Environment variables
│   └── test-connection.sh          # Test database connection
└── README.md                       # This file
```

## Prerequisites

- Okteto CLI installed
- kubectl configured
- Your PostgreSQL dump file renamed to `pg_dump.sql` in the project root

## Quick Start

### 1. Place Your Dump File

```bash
# If your dump is compressed, decompress it first
gunzip your-dump.sql.gz

# Place in project root as pg_dump.sql
mv your-dump.sql pg_dump.sql
```

### 2. Deploy Everything

```bash
okteto deploy --wait
```

This single command will:
1. Deploy PostgreSQL with 70GB persistent volume
2. Copy `pg_dump.sql` to the PostgreSQL pod (if present)
3. Restore the database automatically

If `pg_dump.sql` is not present, only PostgreSQL will be deployed.

## Manual Step-by-Step Process

If you prefer to run steps manually:

### 1. Deploy PostgreSQL

```bash
okteto deploy --file postgres-infra/docker-compose.yml --wait
```

### 2. Copy Dump to Pod

```bash
./1-copy-dump.sh
```

This copies `pg_dump.sql` to `/var/lib/postgresql/data/` in the PostgreSQL pod.
Time estimate: 30-60 minutes for 100GB dump.

### 3. Restore Database

```bash
./2-restore-dump.sh
```

This restores the database from the dump in the PostgreSQL pod.
Time estimate: 2-4 hours for 100GB dump.

### 4. Check Restored Data

```bash
./3-check-data.sh
```

This displays comprehensive database statistics:
- Database size and version
- Table count and sizes
- Row counts for all tables
- Indexes, sequences, and views
- Foreign key relationships
- Disk usage and activity stats

## Configuration

Edit `postgres-infra/.env` to configure your database:

```bash
TARGET_DB=mydatabase           # Your database name
ROLE_PASSWORD=mysecretpassword # PostgreSQL password
```

After changing, redeploy:
```bash
okteto deploy --wait
```

## Database Configuration

The PostgreSQL instance is configured with:
- **max_wal_size**: 4GB (for large transactions)
- **checkpoint_timeout**: 15min (optimized for bulk operations)
- **Storage**: 70GB persistent volume
- **Resources**:
  - Requests: 500m CPU, 2Gi memory
  - Limits: 2 CPU, 8Gi memory

## Accessing the Database

### From within the cluster:

```bash
kubectl exec -it -n ${OKTETO_NAMESPACE} -l stack.okteto.com/service=main-dev-db -- \
  psql -U postgres -d mydatabase
```

### Port forwarding for local access:

```bash
kubectl port-forward -n ${OKTETO_NAMESPACE} svc/main-dev-db 5432:5432
```

Then connect with:
```bash
psql -h localhost -U postgres -d mydatabase
```

### Test connection:

```bash
cd postgres-infra
./test-connection.sh
```

## Storage Strategy

Dumps are copied to the **persistent volume** at `/var/lib/postgresql/data/`:

✅ **Benefits:**
- Uses persistent volume storage (not node ephemeral storage)
- Dump remains available after restore
- No risk of consuming node disk space
- Optimal for 100GB+ dumps

**Manage dump file:**
```bash
# View dump in pod
kubectl exec -n ${OKTETO_NAMESPACE} -l stack.okteto.com/service=main-dev-db -- \
  ls -lh /var/lib/postgresql/data/pg_dump.sql

# Check disk usage
kubectl exec -n ${OKTETO_NAMESPACE} -l stack.okteto.com/service=main-dev-db -- \
  df -h /var/lib/postgresql/data

# Remove dump to free space
kubectl exec -n ${OKTETO_NAMESPACE} -l stack.okteto.com/service=main-dev-db -- \
  rm /var/lib/postgresql/data/pg_dump.sql
```

## Time Estimates

| Dump Size | Copy Time | Restore Time | Total Time |
|-----------|-----------|--------------|------------|
| 1 GB      | 1-2 min   | 5-10 min     | ~15 min    |
| 10 GB     | 5-15 min  | 20-40 min    | ~1 hour    |
| 50 GB     | 20-40 min | 1-2 hours    | ~2-3 hours |
| 100 GB    | 30-60 min | 2-4 hours    | ~3-5 hours |

*Times vary based on network speed, data complexity, and cluster load*

## Troubleshooting

### Check pod status:
```bash
kubectl get pods -n ${OKTETO_NAMESPACE}
```

### View PostgreSQL logs:
```bash
kubectl logs -n ${OKTETO_NAMESPACE} -l stack.okteto.com/service=main-dev-db
```

### Check available disk space:
```bash
kubectl exec -n ${OKTETO_NAMESPACE} -l stack.okteto.com/service=main-dev-db -- df -h
```

### Verify database contents:
```bash
kubectl exec -n ${OKTETO_NAMESPACE} -l stack.okteto.com/service=main-dev-db -- \
  psql -U postgres -d mydatabase -c "\dt"
```

## Cleaning Up

To destroy the environment and all data:

```bash
okteto destroy
```

⚠️ **Warning**: This will delete all data including the persistent volume.

## Environment Variables

- `OKTETO_NAMESPACE`: Your Okteto namespace (automatically set)
- `TARGET_DB`: Database name (set in postgres-infra/.env)
- `ROLE_PASSWORD`: PostgreSQL password (set in postgres-infra/.env)

## Support

For issues with:
- **Okteto deployment**: Check [Okteto Documentation](https://www.okteto.com/docs)
- **PostgreSQL**: Check logs with `kubectl logs`
- **Dump restore**: Ensure dump format is compatible with PostgreSQL 13
