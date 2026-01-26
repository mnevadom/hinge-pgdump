# PostgreSQL Infrastructure

This directory contains all PostgreSQL-related infrastructure and scripts for deploying and managing a PostgreSQL database in Okteto.

## Directory Contents

```
postgres-infra/
├── docker-compose.yml              # PostgreSQL service definition
├── .env                            # Database configuration
├── 1-copy-dump.sh                  # Step 1: Copy dump to persistent volume
├── 2-restore-dump.sh               # Step 2: Restore dump from volume
├── restore-dump-all-in-one.sh     # Combined: Copy + Restore in one script
├── test-connection.sh              # Test database connectivity
└── README.md                       # This file
```

## Quick Start

### Option 1: Two-Step Process (Recommended for Large Dumps)

This approach separates copying and restoring, allowing you to verify the copy completed successfully before starting the restore.

**Step 1: Copy the dump file to the persistent volume**
```bash
cd postgres-infra
./1-copy-dump.sh
```

This script will:
- Find your PostgreSQL pod automatically
- Copy `pg_dump.sql` from project root to `/var/lib/postgresql/data` in the pod
- Verify the file was copied successfully
- Check available disk space
- Take 10-60 minutes for a 100GB dump

**Step 2: Restore the database from the volume**
```bash
./2-restore-dump.sh
```

This script will:
- Verify the dump file exists in the pod
- Check available disk space
- Restore the database using psql
- Show database statistics
- Take 1-3+ hours for a 100GB dump

### Option 2: All-in-One Process

For convenience, you can use the combined script:

```bash
cd postgres-infra
./restore-dump-all-in-one.sh
```

This runs both copy and restore in sequence.

## Prerequisites

1. **Deploy PostgreSQL first:**
   ```bash
   # From project root
   okteto deploy --wait
   ```

2. **Place your dump file in project root:**
   ```bash
   # From project root
   mv /path/to/your-database.sql pg_dump.sql
   ```

## Configuration

Edit `.env` in this directory to configure database settings:

```bash
TARGET_DB=mydatabase           # Your database name
ROLE_PASSWORD=mysecretpassword # PostgreSQL password
```

After changing configuration:
```bash
# From project root
okteto deploy --wait
```

## Testing Connection

To verify PostgreSQL is running and accessible:

```bash
./test-connection.sh
```

## File Locations

### On Your Local Machine:
- Dump file: `../pg_dump.sql` (project root)
- Scripts: `postgres-infra/*.sh`
- Config: `postgres-infra/.env`

### Inside the Pod:
- Dump file: `/var/lib/postgresql/data/pg_dump.sql`
- Database data: `/var/lib/postgresql/data/`
- All stored in persistent volume (70Gi)

## Important Notes

### Why Two Separate Scripts?

1. **Better Progress Tracking**: See when copy completes before restore starts
2. **Error Recovery**: If copy fails, fix issues before attempting restore
3. **Verification**: Inspect the dump file in the pod before restoring
4. **Flexibility**: Re-run restore without re-copying if it fails
5. **Resource Management**: Monitor disk space between steps

### Storage Strategy

The dump file is copied to the **persistent volume** at `/var/lib/postgresql/data`, not to `/tmp`:

✅ **Benefits:**
- Uses persistent volume storage (not node ephemeral storage)
- Dump remains available after restore for future reference
- No risk of consuming node disk space
- Better for 100GB+ dumps

### Managing the Dump File

**View the dump in pod:**
```bash
kubectl exec -n ${OKTETO_NAMESPACE} -l stack.okteto.com/service=main-dev-db -- \
  ls -lh /var/lib/postgresql/data/pg_dump.sql
```

**Check disk usage:**
```bash
kubectl exec -n ${OKTETO_NAMESPACE} -l stack.okteto.com/service=main-dev-db -- \
  df -h /var/lib/postgresql/data
```

**Remove dump to free space:**
```bash
kubectl exec -n ${OKTETO_NAMESPACE} -l stack.okteto.com/service=main-dev-db -- \
  rm /var/lib/postgresql/data/pg_dump.sql
```

## Time Estimates

### Step 1: Copy (1-copy-dump.sh)
| Dump Size | Copy Time |
|-----------|-----------|
| 1 GB      | 1-2 min   |
| 10 GB     | 5-15 min  |
| 50 GB     | 20-40 min |
| 100 GB    | 30-60 min |

### Step 2: Restore (2-restore-dump.sh)
| Dump Size | Restore Time |
|-----------|--------------|
| 1 GB      | 5-10 min     |
| 10 GB     | 20-40 min    |
| 50 GB     | 1-2 hours    |
| 100 GB    | 2-4 hours    |

*Times vary based on network speed, data complexity, and cluster load*

## Troubleshooting

### Script can't find dump file
```bash
# Ensure dump is in project root
ls -lh ../pg_dump.sql

# If not, copy it there
cp /path/to/your-dump.sql ../pg_dump.sql
```

### Script can't find pod
```bash
# Check if PostgreSQL is deployed
kubectl get pods -n ${OKTETO_NAMESPACE}

# If not deployed
cd .. && okteto deploy --wait
```

### Out of disk space
```bash
# Check current usage
kubectl exec -n ${OKTETO_NAMESPACE} -l stack.okteto.com/service=main-dev-db -- \
  df -h /var/lib/postgresql/data

# Increase volume size in docker-compose.yml
# Then redeploy
cd .. && okteto deploy --wait
```

### Copy completed but restore fails
```bash
# Verify dump file is in pod
kubectl exec -n ${OKTETO_NAMESPACE} -l stack.okteto.com/service=main-dev-db -- \
  ls -lh /var/lib/postgresql/data/pg_dump.sql

# Check PostgreSQL logs
kubectl logs -n ${OKTETO_NAMESPACE} -l stack.okteto.com/service=main-dev-db

# Re-run restore (no need to re-copy)
./2-restore-dump.sh
```

## Database Access

### Interactive shell:
```bash
kubectl exec -it -n ${OKTETO_NAMESPACE} -l stack.okteto.com/service=main-dev-db -- \
  psql -U postgres -d mydatabase
```

### Run a query:
```bash
kubectl exec -n ${OKTETO_NAMESPACE} -l stack.okteto.com/service=main-dev-db -- \
  psql -U postgres -d mydatabase -c "SELECT COUNT(*) FROM your_table;"
```

### Port forward for local access:
```bash
kubectl port-forward -n ${OKTETO_NAMESPACE} svc/main-dev-db 5432:5432
```

Then connect locally:
```bash
psql -h localhost -U postgres -d mydatabase
```

## Configuration Details

### PostgreSQL Settings (docker-compose.yml)

- **max_wal_size**: 4GB (for large transactions)
- **checkpoint_timeout**: 15min (optimized for bulk operations)

### Resources

- **CPU**: 500m request, 2 cores limit
- **Memory**: 2Gi request, 8Gi limit
- **Storage**: 70Gi persistent volume (adjustable)

### Volume Configuration

```yaml
volumes:
  main-dev-data:
    driver_opts:
      size: 70Gi          # Adjust based on your needs
      class: csi-okteto   # Okteto persistent storage
```

## Additional Resources

- [Parent README](../README.md) - Complete project documentation
- [Quickstart Guide](../QUICKSTART.md) - Fast setup instructions
- [Workflow Details](../WORKFLOW.md) - Detailed process diagrams
- [Volume Storage](../VOLUME_STORAGE.md) - Storage strategy explanation
- [Okteto Documentation](https://www.okteto.com/docs) - Official docs

## Summary

This directory contains everything needed to deploy and manage PostgreSQL in Okteto:

1. **Deploy**: PostgreSQL automatically deploys via Okteto manifest
2. **Copy**: Use `1-copy-dump.sh` to copy your dump to the persistent volume
3. **Restore**: Use `2-restore-dump.sh` to restore the database
4. **Access**: Use `test-connection.sh` or kubectl to access the database

All data is stored in a persistent 70Gi volume, ensuring durability and avoiding node resource consumption.
