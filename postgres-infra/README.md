# PostgreSQL Infrastructure

This directory contains the PostgreSQL service configuration for deployment in Okteto.

## Directory Contents

```
postgres-infra/
├── docker-compose.yml              # PostgreSQL service definition
├── .env                            # Database configuration
└── test-connection.sh              # Test database connectivity
```

**Note**: The dump copy and restore scripts (`1-copy-dump.sh` and `2-restore-dump.sh`) are located in the project root for easier access.

## Quick Start

### Automated Deployment

From project root:
```bash
okteto deploy --wait
```

This will deploy PostgreSQL and automatically run copy/restore if `pg_dump.sql` exists in the root.

### Manual Steps

From project root:

1. **Deploy PostgreSQL:**
   ```bash
   okteto deploy --file postgres-infra/docker-compose.yml --wait
   ```

2. **Copy dump:**
   ```bash
   ./1-copy-dump.sh
   ```

3. **Restore database:**
   ```bash
   ./2-restore-dump.sh
   ```

## Configuration

Edit `.env` in this directory:

```bash
TARGET_DB=mydatabase           # Your database name
ROLE_PASSWORD=mysecretpassword # PostgreSQL password
```

After changing, redeploy:
```bash
cd .. && okteto deploy --wait
```

## Testing Connection

```bash
./test-connection.sh
```

## PostgreSQL Settings

Configured in `docker-compose.yml`:
- **max_wal_size**: 4GB (for large transactions)
- **checkpoint_timeout**: 15min (optimized for bulk operations)

## Resources

- **CPU**: 500m request, 2 cores limit
- **Memory**: 2Gi request, 8Gi limit
- **Storage**: 70Gi persistent volume (adjustable)

## Database Access

### Interactive shell:
```bash
kubectl exec -it -n ${OKTETO_NAMESPACE} -l stack.okteto.com/service=main-dev-db -- \
  psql -U postgres -d mydatabase
```

### Port forward for local access:
```bash
kubectl port-forward -n ${OKTETO_NAMESPACE} svc/main-dev-db 5432:5432
```

Then connect:
```bash
psql -h localhost -U postgres -d mydatabase
```

## See Also

- [Main README](../README.md) - Complete project documentation
- [1-copy-dump.sh](../1-copy-dump.sh) - Copy script in root
- [2-restore-dump.sh](../2-restore-dump.sh) - Restore script in root
