# PostgreSQL Database Restore on Okteto

Restore large PostgreSQL 13 database dumps (100GB+) on Okteto.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Okteto Deployment                        │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  Step 1: Deploy PostgreSQL                                   │
│  ┌────────────────────────────┐                              │
│  │   PostgreSQL 13 Pod        │                              │
│  │   - 2 CPU / 8GB RAM        │                              │
│  │   - Optimized settings     │                              │
│  └─────────┬──────────────────┘                              │
│            │                                                  │
│            ↓                                                  │
│  ┌────────────────────────────┐                              │
│  │   PVC (70GB)               │                              │
│  │   /var/lib/postgresql/data │                              │
│  └────────────────────────────┘                              │
│                                                               │
│  Step 2: Copy Dump File                                      │
│  ┌────────────────────────────┐                              │
│  │   Your Machine             │                              │
│  │   pg_dump.sql (100GB)      │                              │
│  └─────────┬──────────────────┘                              │
│            │ kubectl cp                                       │
│            ↓                                                  │
│  ┌────────────────────────────┐                              │
│  │   PVC (70GB)               │                              │
│  │   ├─ pg_dump.sql           │                              │
│  │   └─ postgres data/        │                              │
│  └────────────────────────────┘                              │
│                                                               │
│  Step 3: Restore Database (Kubernetes Job)                   │
│  ┌────────────────────────────┐                              │
│  │   Restore Job Pod          │                              │
│  │   - Mounts same PVC        │                              │
│  │   - Reads dump file        │                              │
│  │   - Connects to PostgreSQL │                              │
│  │   - Runs pg_restore/psql   │                              │
│  └─────────┬──────────────────┘                              │
│            │ SQL commands over network                        │
│            ↓                                                  │
│  ┌────────────────────────────┐                              │
│  │   PostgreSQL 13 Pod        │                              │
│  │   Writes restored data ────────→ PVC                      │
│  └────────────────────────────┘                              │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

## Quick Start

### 1. Add Environment Variables in Okteto

Go to Okteto admin panel → Variables:

| Variable | Description | Example |
|----------|-------------|---------|
| `TARGET_DB` | Database name | `mydatabase` |
| `ROLE_PASSWORD` | PostgreSQL password | `secure_password_123` |
| `LOCAL_DUMP_FILE` | Dump file path (optional) | `pg_dump.sql` |

### 2. Add Your Dump File

Place dump in project root:

```bash
# Rename to pg_dump.sql (or set LOCAL_DUMP_FILE in step 1)
mv your-dump.sql pg_dump.sql
```

### 3. Deploy

```bash
okteto deploy --wait
```

That's it! The process will:
1. Deploy PostgreSQL 13
2. Copy dump to PostgreSQL pod (via kubectl cp)
3. Create restore Job (runs in background)

### 4. Monitor Restore

```bash
# Watch restore progress
kubectl logs -f -n ${OKTETO_NAMESPACE} job/postgres-restore-job

# Check job status
kubectl get job -n ${OKTETO_NAMESPACE}
```

## Time Estimates

| Dump Size | Copy Time | Restore Time | Total |
|-----------|-----------|--------------|-------|
| 10GB      | 5-10 min  | 20-40 min    | ~1h   |
| 50GB      | 20-40 min | 1-2 hours    | ~3h   |
| 100GB     | 30-60 min | 2-4 hours    | ~5h   |

## Access Database

```bash
# Connect via kubectl
kubectl exec -it -n ${OKTETO_NAMESPACE} -l stack.okteto.com/service=main-dev-db -- \
  psql -U postgres -d ${TARGET_DB}

# Port forward
kubectl port-forward -n ${OKTETO_NAMESPACE} svc/main-dev-db 5432:5432

# Connect locally
psql -h localhost -U postgres -d ${TARGET_DB}
```

## Manual Scripts

If you prefer manual control:

```bash
# Copy dump
./1-copy-dump.sh

# Restore (uses kubectl exec - requires stable connection)
./2-restore-dump.sh

# Check restored data
./3-check-data.sh
```

## Configuration

**PostgreSQL Settings:**
- Version: 13
- Storage: 70GB PVC (csi-okteto)
- max_wal_size: 4GB
- checkpoint_timeout: 15min
- Resources: 2 CPU, 8GB RAM

**Supported Formats:**
- Plain SQL (`.sql`)
- Custom format (`pg_dump -Fc`)

## Troubleshooting

```bash
# Check pod status
kubectl get pods -n ${OKTETO_NAMESPACE}

# View PostgreSQL logs
kubectl logs -n ${OKTETO_NAMESPACE} -l stack.okteto.com/service=main-dev-db

# Check disk space
kubectl exec -n ${OKTETO_NAMESPACE} -l stack.okteto.com/service=main-dev-db -- df -h

# Debug restore job
kubectl describe job -n ${OKTETO_NAMESPACE} postgres-restore-job
```

## Clean Up

```bash
okteto destroy -v
```

⚠️ **Warning**: Deletes all data including PVC.

---

**Files:**
- `okteto.yml` - Deployment pipeline
- `postgres-infra/docker-compose.yml` - PostgreSQL service
- `job-restore/` - Restore Job (runs in cluster)
- `1-copy-dump.sh` - Manual copy script
- `2-restore-dump.sh` - Manual restore script
- `3-check-data.sh` - Verify restored data
