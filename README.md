# PostgreSQL Okteto Project

This project deploys a PostgreSQL 13 database on Okteto with support for restoring large database dumps (up to 100GB+).

## Project Structure

```
.
├── okteto.yml                      # Okteto manifest deploying from docker-compose
├── pg_dump.sql                     # Your PostgreSQL dump file (place here)
├── postgres-infra/                 # PostgreSQL infrastructure directory
│   ├── docker-compose.yml          # PostgreSQL service definition
│   ├── .env                        # Environment variables
│   ├── 1-copy-dump.sh              # Step 1: Copy dump to volume
│   ├── 2-restore-dump.sh           # Step 2: Restore from volume
│   ├── restore-dump-all-in-one.sh  # Combined copy + restore
│   ├── test-connection.sh          # Test database connection
│   └── README.md                   # PostgreSQL-specific docs
└── README.md                       # This file
```

## Prerequisites

- Okteto CLI installed
- kubectl configured
- Your PostgreSQL dump file renamed to `pg_dump.sql` in the project root

## Configuration

Edit the `postgres-infra/.env` file to configure your database:

```bash
TARGET_DB=mydatabase           # Your database name
ROLE_PASSWORD=mysecretpassword # PostgreSQL password
```

## Deployment

Deploy the PostgreSQL service to Okteto:

```bash
okteto deploy --wait
```

This will:
- Create a PostgreSQL 13 instance
- Set up a 70GB persistent volume
- Configure optimized PostgreSQL settings for large databases
- Expose PostgreSQL on port 5432

## Restoring Your Database Dump

### 1. Prepare Your Dump File

Place your PostgreSQL dump file in the project root and name it `pg_dump.sql`:

```bash
# If your dump is compressed, decompress it first
gunzip your-dump.sql.gz

# Rename to pg_dump.sql
mv your-dump.sql pg_dump.sql
```

### 2. Run the Restore Scripts

**Option A: Two-Step Process (Recommended for Large Dumps)**

Step 1 - Copy the dump to the persistent volume:
```bash
cd postgres-infra
./1-copy-dump.sh
```

Step 2 - Restore the database:
```bash
./2-restore-dump.sh
```

**Option B: All-in-One Process**

For convenience, run both steps together:
```bash
cd postgres-infra
./restore-dump-all-in-one.sh
```

### Why Two Separate Scripts?

The two-step approach is recommended because:
- **Better progress tracking**: See when copy completes before restore starts
- **Error recovery**: Fix issues between steps without starting over
- **Verification**: Inspect dump in pod before restoring
- **Flexibility**: Re-run restore without re-copying if it fails
- **Time savings**: For 100GB dump, copy takes 30-60 min, restore takes 2-4 hours

**Important**: The dump file is copied directly to the persistent volume at `/var/lib/postgresql/data`, not to temporary storage. This ensures all operations use the volume resources instead of consuming node ephemeral storage.

### 3. Monitor Progress

For large dumps, you can monitor progress in another terminal:

```bash
# Watch pod logs
kubectl logs -f -n ${OKTETO_NAMESPACE} -l stack.okteto.com/service=main-dev-db

# Check resource usage
kubectl top pod -n ${OKTETO_NAMESPACE}
```

## Accessing the Database

### From within the cluster:

```bash
kubectl exec -it -n ${OKTETO_NAMESPACE} -l stack.okteto.com/service=main-dev-db -- psql -U postgres -d mydatabase
```

### Port forwarding to access locally:

```bash
kubectl port-forward -n ${OKTETO_NAMESPACE} svc/main-dev-db 5432:5432
```

Then connect with:
```bash
psql -h localhost -U postgres -d mydatabase
```

## Database Configuration

The PostgreSQL instance is configured with:
- **max_wal_size**: 4GB (for large transactions)
- **checkpoint_timeout**: 15min (optimized for bulk operations)
- **Storage**: 70GB persistent volume (adjustable based on your namespace quota)
- **Resources**:
  - Requests: 500m CPU, 2Gi memory
  - Limits: 2 CPU, 8Gi memory

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
kubectl exec -n ${OKTETO_NAMESPACE} -l stack.okteto.com/service=main-dev-db -- psql -U postgres -d mydatabase -c "\dt"
```

### Test connection:
```bash
cd postgres-infra
./test-connection.sh
```

## Performance Tips for Large Dumps

1. **Use the two-step process**: Allows you to verify copy completed before starting restore
2. **Monitor restore progress**: The restore process will show output in real-time
3. **Ensure sufficient memory**: The pod has up to 8Gi available
4. **Patience**: A 100GB dump can take 3-5 hours total (copy + restore)

## Time Estimates

| Dump Size | Copy Time | Restore Time | Total Time |
|-----------|-----------|--------------|------------|
| 1 GB      | 1-2 min   | 5-10 min     | ~15 min    |
| 10 GB     | 5-15 min  | 20-40 min    | ~1 hour    |
| 50 GB     | 20-40 min | 1-2 hours    | ~2-3 hours |
| 100 GB    | 30-60 min | 2-4 hours    | ~3-5 hours |

*Times vary based on network speed, data complexity, and cluster load*

## Cleaning Up

To destroy the environment and all data:

```bash
okteto destroy
```

⚠️ **Warning**: This will delete all data including the persistent volume.

## Environment Variables Available

- `OKTETO_NAMESPACE`: Your Okteto namespace (automatically set)
- `TARGET_DB`: Database name (set in postgres-infra/.env)
- `ROLE_PASSWORD`: PostgreSQL password (set in postgres-infra/.env)

## Additional Documentation

- **[postgres-infra/README.md](postgres-infra/README.md)** - Detailed PostgreSQL documentation
- **[QUICKSTART.md](QUICKSTART.md)** - Quick start guide
- **[WORKFLOW.md](WORKFLOW.md)** - Detailed workflow diagrams
- **[VOLUME_STORAGE.md](VOLUME_STORAGE.md)** - Storage strategy explanation

## Support

For issues with:
- **Okteto deployment**: Check [Okteto Documentation](https://www.okteto.com/docs)
- **PostgreSQL**: Check logs with `kubectl logs`
- **Dump restore**: See postgres-infra/README.md for detailed troubleshooting
