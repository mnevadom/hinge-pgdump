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

Place your SQL dump in the project root and rename it:

```bash
# If compressed, decompress first
gunzip your-dump.sql.gz

# Rename to pg_dump.sql
mv your-dump.sql pg_dump.sql
```

### 3. Deploy

```bash
okteto deploy --wait
```

This will:
- Clean any previous PostgreSQL deployment
- Deploy fresh PostgreSQL with 70GB storage
- Copy your dump to the database pod
- Restore the database automatically

**That's it!** Your database will be restored and ready to use.

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

## Manual Steps (Optional)

If you want to run steps manually instead of automatic deployment:

```bash
# 1. Deploy PostgreSQL only
okteto deploy --file postgres-infra/docker-compose.yml --wait

# 2. Copy dump
./1-copy-dump.sh

# 3. Restore database
./2-restore-dump.sh

# 4. Check data
./3-check-data.sh
```

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
- `okteto.yml` - Deployment automation
- `pg_dump.sql` - Your database dump (add this)
- `postgres-infra/docker-compose.yml` - PostgreSQL service
- `postgres-infra/.env` - Database configuration
- `1-copy-dump.sh` - Copy dump to pod
- `2-restore-dump.sh` - Restore database
- `3-check-data.sh` - Verify restored data

---

For more help: [Okteto Documentation](https://www.okteto.com/docs)
