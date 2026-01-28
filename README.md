# PostgreSQL Database Restore on Okteto

Simple project to deploy PostgreSQL 13 and restore your database dump on Okteto.

## Setup Steps

### 1. Configure Database Settings

Edit `postgres-infra/.env`:

```bash
TARGET_DB=your_database_name
ROLE_PASSWORD=your_secure_password
```

### 2. Add Your Database Dump

Place your database dump in the project root and rename it to `pg_dump.sql`:

```bash
# If compressed, decompress first
gunzip your-dump.sql.gz

# Rename to pg_dump.sql
mv your-dump.sql pg_dump.sql
```

**Supported formats:**
- Plain SQL dump (`.sql`)
- PostgreSQL custom-format dump (created with `pg_dump -Fc`)

The restore script automatically detects the format and uses the appropriate restore method (`psql` or `pg_restore`).

### 3. Deploy

```bash
okteto deploy --wait
```

This will:
- Clean any previous PostgreSQL deployment
- Deploy fresh PostgreSQL with 70GB storage
- Copy your dump to the database pod
- Start a Kubernetes Job to restore the database (runs in background)

**That's it!** The restore job will run unattended in the cluster. You can disconnect and check back later.

**How it works:**
1. Okteto builds a custom Docker image from `job-restore/` folder
2. The Job runs this image, which mounts the same PVC as PostgreSQL
3. The restore script connects to PostgreSQL remotely and restores the dump
4. All logic is self-contained in the `job-restore/` folder

### Monitor Restore Progress

```bash
# Watch restore job logs in real-time
kubectl logs -f -n ${OKTETO_NAMESPACE} job/postgres-restore-job

# Check job status
kubectl get job -n ${OKTETO_NAMESPACE} postgres-restore-job
```

The Job will automatically handle the restore even if you disconnect. Kubernetes will keep it running until completion.

## Verify Data

Check your restored database:

```bash
./3-check-data.sh
```

## Access Database

Connect to PostgreSQL:

```bash
kubectl exec -it -n ${OKTETO_NAMESPACE} -l stack.okteto.com/service=main-dev-db -- \
  psql -U postgres -d your_database_name
```

Or use port forwarding:

```bash
kubectl port-forward -n ${OKTETO_NAMESPACE} svc/main-dev-db 5432:5432
```

Then connect locally:

```bash
psql -h localhost -U postgres -d your_database_name
```

## Manual Steps (Alternative)

If you prefer to run steps manually with local scripts instead of the automated Job:

```bash
# 1. Deploy PostgreSQL only
okteto deploy --file postgres-infra/docker-compose.yml --wait

# 2. Copy dump
./1-copy-dump.sh

# 3. Restore database (runs locally, requires stable connection)
./2-restore-dump.sh

# 4. Check data
./3-check-data.sh
```

**Note**: Manual restore with `2-restore-dump.sh` requires your terminal to stay connected for the entire duration (potentially hours). The automated Job approach is more reliable for large dumps.

## Time Estimates

| Dump Size | Estimated Time |
|-----------|----------------|
| 1 GB      | ~15 minutes    |
| 10 GB     | ~1 hour        |
| 50 GB     | ~2-3 hours     |
| 100 GB    | ~3-5 hours     |

## Troubleshooting

**Check pod status:**
```bash
kubectl get pods -n ${OKTETO_NAMESPACE}
```

**View logs:**
```bash
kubectl logs -n ${OKTETO_NAMESPACE} -l stack.okteto.com/service=main-dev-db
```

**Check disk space:**
```bash
kubectl exec -n ${OKTETO_NAMESPACE} -l stack.okteto.com/service=main-dev-db -- df -h
```

## Clean Up

To remove everything:

```bash
okteto destroy
```

⚠️ **Warning**: This deletes all data including the persistent volume.

## Configuration Details

**PostgreSQL Settings:**
- Version: 13
- Storage: 70GB persistent volume
- max_wal_size: 4GB (optimized for large dumps)
- checkpoint_timeout: 15min
- Resources: 2 CPU cores, 8GB memory

**Files:**
- `okteto.yml` - Deployment automation with image build
- `job-restore/` - Restore Job self-contained folder
  - `Dockerfile` - Custom image definition
  - `restore-in-pod.sh` - Restore script (runs in cluster)
  - `restore-job.yaml` - Kubernetes Job manifest
- `pg_dump.sql` - Your database dump (add this)
- `postgres-infra/docker-compose.yml` - PostgreSQL service
- `postgres-infra/.env` - Database configuration
- `1-copy-dump.sh` - Copy dump to pod (manual)
- `2-restore-dump.sh` - Restore database (manual, uses kubectl exec)
- `3-check-data.sh` - Verify restored data

---

For more help: [Okteto Documentation](https://www.okteto.com/docs)
