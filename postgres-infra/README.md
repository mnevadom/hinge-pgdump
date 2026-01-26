# PostgreSQL Infrastructure

This directory contains all PostgreSQL-related infrastructure and scripts for deploying and managing a PostgreSQL database in Okteto.

## Directory Contents

```
postgres-infra/
├── docker-compose.yml              # PostgreSQL service definition
├── .env                            # Database configuration
├── 1-copy-dump.sh                  # Copy dump to dump-stager pod
├── test-connection.sh              # Test database connectivity
└── README.md                       # This file
```

## Quick Start

### 1. Deploy PostgreSQL

From project root:
```bash
okteto deploy --wait
```

### 2. Deploy Dump Stager Pod

The dump-stager pod is required to receive and stage the database dump:

```bash
kubectl apply -f rds-dump-pod/dumps-pvc.yaml -n ${OKTETO_NAMESPACE}
kubectl apply -f rds-dump-pod/dump-stager-pod.yaml -n ${OKTETO_NAMESPACE}
```

### 3. Copy Your Dump

Place your dump file in project root:
```bash
# From project root
mv /path/to/your-database.sql pg_dump.sql
```

Then copy it to the dump-stager pod:
```bash
cd postgres-infra
./1-copy-dump.sh
```

This script will:
- Find the dump-stager pod automatically
- Copy `pg_dump.sql` from project root to `/input/db.dump` in the pod
- Verify the file was copied successfully
- The dump-stager pod will then process it and copy to the shared PVC

### 4. Restore Happens Automatically

Your restore job (defined in docker-compose.yml) should automatically:
- Pick up the dump from the shared PVC
- Restore it into the PostgreSQL database

## Workflow

```
1. Place dump in project root (pg_dump.sql)
                ↓
2. Run ./1-copy-dump.sh
                ↓
3. Dump copied to dump-stager pod (/input/db.dump)
                ↓
4. dump-stager processes and stages to shared PVC (/dumps/db.dump)
                ↓
5. Your restore job picks it up and restores to PostgreSQL
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

### Inside dump-stager Pod:
- Input: `/input/db.dump` (where your dump is copied)
- Output: `/dumps/db.dump` (staged to shared PVC)

### Inside PostgreSQL Pod:
- Database data: `/var/lib/postgresql/data/`
- Shared dumps PVC: `/dumps/` (if mounted)

## Important Notes

### Script Updates

The `1-copy-dump.sh` script now:
- Copies to the **dump-stager pod** at `/input/db.dump`
- No longer copies directly to PostgreSQL pod
- The dump-stager pod handles staging to the shared PVC
- Your restore job handles the actual database restore

### Why This Approach?

1. **Separation of concerns**: Copy, staging, and restore are separate steps
2. **Shared PVC**: Multiple pods can access the same dump
3. **Automated restore**: Your job handles restore logic
4. **Reusable**: Can stage dumps from various sources (local, S3, RDS, etc.)

## Time Estimates

### Copy to dump-stager (1-copy-dump.sh)
| Dump Size | Copy Time |
|-----------|-----------|
| 1 GB      | 1-2 min   |
| 10 GB     | 5-15 min  |
| 50 GB     | 20-40 min |
| 100 GB    | 30-60 min |

### Staging & Restore
Time varies based on your restore job configuration.

## Troubleshooting

### Script can't find dump file
```bash
# Ensure dump is in project root
ls -lh ../pg_dump.sql

# If not, copy it there
cp /path/to/your-dump.sql ../pg_dump.sql
```

### Script can't find dump-stager pod
```bash
# Check if pod exists
kubectl get pods -n ${OKTETO_NAMESPACE}

# If not deployed, deploy it
kubectl apply -f ../rds-dump-pod/dumps-pvc.yaml -n ${OKTETO_NAMESPACE}
kubectl apply -f ../rds-dump-pod/dump-stager-pod.yaml -n ${OKTETO_NAMESPACE}
```

### dump-stager pod already completed
```bash
# Delete and recreate the pod
kubectl delete pod dump-stager -n ${OKTETO_NAMESPACE}
kubectl apply -f ../rds-dump-pod/dump-stager-pod.yaml -n ${OKTETO_NAMESPACE}

# Then run copy script again
./1-copy-dump.sh
```

### Out of disk space
```bash
# Check dump-stager storage
kubectl exec -n ${OKTETO_NAMESPACE} dump-stager -- df -h

# Check shared PVC
kubectl exec -n ${OKTETO_NAMESPACE} dump-stager -- df -h /dumps

# Increase volume size in rds-dump-pod/dumps-pvc.yaml if needed
```

### Monitor dump-stager processing
```bash
# Watch the dump-stager pod logs
kubectl logs -f dump-stager -n ${OKTETO_NAMESPACE}
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
- [RDS Dump Pod](../rds-dump-pod/README.md) - Dump stager documentation
- [Okteto Documentation](https://www.okteto.com/docs) - Official docs

## Summary

This directory contains the PostgreSQL service configuration. The workflow is:

1. **Deploy**: PostgreSQL automatically deploys via Okteto manifest
2. **Stage**: Deploy dump-stager pod to receive dumps
3. **Copy**: Use `1-copy-dump.sh` to copy your dump to dump-stager
4. **Restore**: Your restore job automatically restores the database

The dump flows through the dump-stager pod to a shared PVC, where your restore job picks it up and loads it into PostgreSQL.
