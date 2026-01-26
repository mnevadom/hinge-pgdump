# Volume Storage Strategy

## Why Copy to Persistent Volume?

The restore script copies your database dump to the **persistent volume** at `/var/lib/postgresql/data` instead of temporary storage (`/tmp`). This design choice has several important benefits:

## Benefits

### 1. **No Node Resource Consumption**
- `/tmp` uses the node's ephemeral storage
- Persistent volume uses dedicated storage resources
- For 100GB dumps, this prevents overwhelming the node's local disk

### 2. **Dump Remains Available**
- Stored in the persistent volume alongside the database data
- Available for future reference or re-restoration
- Survives pod restarts (stored in PVC, not pod filesystem)

### 3. **Better Resource Management**
- Persistent volume is provisioned with 70Gi specifically for this purpose
- Separate quota from node resources
- More predictable storage behavior

### 4. **Easier Troubleshooting**
- Can inspect the dump file later if needed
- No risk of cleanup removing evidence during debugging
- File location is permanent and predictable

## Storage Layout

```
Persistent Volume (70Gi)
/var/lib/postgresql/data/
├── base/                    # PostgreSQL database files
├── global/                  # Cluster-wide tables
├── pg_wal/                  # Write-Ahead Logging files
├── pg_dump.sql             # Your dump file (after restore)
└── [other PostgreSQL files]
```

## Disk Usage Example

For a 100GB dump with restored data:

```bash
# Check total volume usage
kubectl exec -n ${OKTETO_NAMESPACE} main-dev-db-0 -- df -h /var/lib/postgresql/data

# Expected output:
# Filesystem      Size  Used Avail Use% Mounted on
# /dev/sdX         69G   65G    4G  95% /var/lib/postgresql/data
#
# Used space includes:
# - pg_dump.sql: ~100GB (compressed in dump format)
# - Database data: ~50-70GB (expanded tables, indexes)
```

## Managing the Dump File

### View the dump file location:
```bash
kubectl exec -n ${OKTETO_NAMESPACE} main-dev-db-0 -- \
  ls -lh /var/lib/postgresql/data/pg_dump.sql
```

### Check its size:
```bash
kubectl exec -n ${OKTETO_NAMESPACE} main-dev-db-0 -- \
  du -h /var/lib/postgresql/data/pg_dump.sql
```

### Remove it when no longer needed:
```bash
kubectl exec -n ${OKTETO_NAMESPACE} main-dev-db-0 -- \
  rm /var/lib/postgresql/data/pg_dump.sql
```

### Check available space after removal:
```bash
kubectl exec -n ${OKTETO_NAMESPACE} main-dev-db-0 -- \
  df -h /var/lib/postgresql/data
```

## Space Planning

| Component | Size | Notes |
|-----------|------|-------|
| Dump file | 100GB | SQL dump (text format) |
| Restored data | 50-70GB | Actual database (binary) |
| WAL files | 4-8GB | Write-ahead logs |
| Temp files | 1-5GB | During operations |
| **Total Required** | **~160-180GB** | With dump kept |
| **After cleanup** | **~60-80GB** | Dump removed |

## Volume Size Recommendations

| Dump Size | Recommended Volume | With Headroom |
|-----------|-------------------|---------------|
| 10GB | 30Gi | 50Gi |
| 50GB | 120Gi | 150Gi |
| 100GB | 200Gi | 250Gi |
| 200GB | 400Gi | 500Gi |

**Formula**: `Volume Size = (Dump Size × 1.5) + (Dump Size × 0.5 buffer)`

## Current Configuration

Your project is configured with:
- **Volume Size**: 70Gi
- **Storage Class**: csi-okteto
- **Access Mode**: ReadWriteOnce (RWO)
- **Mount Path**: `/var/lib/postgresql/data`

### Adjusting Volume Size

Edit `docker-compose.yml`:

```yaml
volumes:
  main-dev-data:
    driver_opts:
      size: 200Gi  # Increase as needed
      class: csi-okteto
```

Then redeploy:
```bash
okteto deploy --wait
```

**Note**: Check your namespace quota before increasing:
```bash
kubectl describe quota -n ${OKTETO_NAMESPACE}
```

## Comparison: Volume vs Ephemeral Storage

### Using `/tmp` (Ephemeral) ❌

```
Node Disk
├── /tmp/pg_dump.sql (100GB) ← Uses node resources
├── Other pods' temp files
└── System files

Problems:
- Competes with other pods
- Node disk might be limited
- Lost on pod restart
- Can cause node instability
```

### Using `/var/lib/postgresql/data` (Volume) ✅

```
Persistent Volume (70Gi)
└── /var/lib/postgresql/data/
    ├── pg_dump.sql (100GB) ← Dedicated storage
    └── database files

Benefits:
- Isolated from node resources
- Dedicated quota
- Survives pod restarts
- Predictable performance
```

## Monitoring Storage

### Real-time monitoring during restore:

```bash
# Watch disk usage (run in separate terminal)
watch -n 5 'kubectl exec -n ${OKTETO_NAMESPACE} main-dev-db-0 -- df -h /var/lib/postgresql/data'
```

### Check what's using space:

```bash
kubectl exec -n ${OKTETO_NAMESPACE} main-dev-db-0 -- \
  du -h -d 1 /var/lib/postgresql/data | sort -h
```

## Troubleshooting Storage Issues

### "No space left on device"

```bash
# 1. Check current usage
kubectl exec -n ${OKTETO_NAMESPACE} main-dev-db-0 -- df -h

# 2. Find large files
kubectl exec -n ${OKTETO_NAMESPACE} main-dev-db-0 -- \
  du -h /var/lib/postgresql/data | sort -h | tail -20

# 3. Remove dump if needed
kubectl exec -n ${OKTETO_NAMESPACE} main-dev-db-0 -- \
  rm /var/lib/postgresql/data/pg_dump.sql

# 4. Or increase volume size in docker-compose.yml
```

### Verify volume is mounted correctly:

```bash
kubectl exec -n ${OKTETO_NAMESPACE} main-dev-db-0 -- mount | grep postgresql
```

Expected output:
```
/dev/sdX on /var/lib/postgresql/data type ext4 (rw,relatime)
```

## Best Practices

1. **Before Restore**:
   - Check available space: `df -h`
   - Ensure volume is large enough for dump + expanded data
   - Calculate: `Volume Size ≥ Dump Size × 2`

2. **During Restore**:
   - Monitor disk usage in real-time
   - Watch for "disk full" warnings in logs
   - Keep terminal session active

3. **After Restore**:
   - Verify restoration completed successfully
   - Check database size: `pg_database_size()`
   - Decide if dump should be kept or removed
   - Document space usage for future reference

4. **Space Management**:
   - Remove dump after successful verification
   - Set up regular database maintenance (VACUUM)
   - Monitor WAL file growth
   - Consider periodic backups to external storage

## Security Considerations

Since the dump file contains your complete database:

1. **Access Control**:
   - Only accessible via kubectl (no public exposure)
   - Requires namespace access permissions
   - File permissions set appropriately

2. **Cleanup Recommendations**:
   - Remove dump after verification if it contains sensitive data
   - Don't leave dumps indefinitely in production
   - Consider encrypted volumes for sensitive data

3. **Backup Strategy**:
   - Dump in volume is NOT a backup (same volume as database)
   - Create actual backups in separate storage
   - Use Okteto volumes with snapshot capabilities

## Summary

✅ **DO**: Copy to persistent volume (`/var/lib/postgresql/data`)
- Uses dedicated storage resources
- Survives pod restarts
- Better resource isolation
- Easier to manage

❌ **DON'T**: Copy to `/tmp`
- Consumes node ephemeral storage
- Can destabilize nodes
- Lost on pod restart
- Competes with system processes

---

**The restore script automatically handles this correctly!** Just run:
```bash
./restore-dump.sh
```
