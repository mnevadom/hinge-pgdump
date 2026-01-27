# RDS Dump Stager Pod

This folder contains Kubernetes manifests for staging database dumps into a shared persistent volume.

## Files

- **dumps-pvc.yaml** - 50Gi PersistentVolumeClaim for storing database dumps
- **dump-stager-pod.yaml** - Alpine-based pod that copies dumps to the shared PVC

## Purpose

This setup provides a way to stage database dumps into a persistent volume that can be shared with other pods (like PostgreSQL for restore operations).

## Usage

### 1. Create the PVC

First, create the persistent volume claim:

```bash
kubectl apply -f dumps-pvc.yaml -n ${OKTETO_NAMESPACE}
```

Verify the PVC is created:

```bash
kubectl get pvc pg-dumps -n ${OKTETO_NAMESPACE}
```

### 2. Prepare Your Dump

The current configuration uses an `emptyDir` for `/input`. You need to modify this based on your source:

**Option A: Mount from another PVC**
```yaml
- name: input
  persistentVolumeClaim:
    claimName: your-source-pvc
```

**Option B: Use an init container to download from S3/GCS**
```yaml
initContainers:
  - name: download
    image: amazon/aws-cli
    command: ["aws", "s3", "cp", "s3://bucket/db.dump", "/input/db.dump"]
    volumeMounts:
      - name: input
        mountPath: /input
```

**Option C: Build dump into a custom image**
```yaml
containers:
  - name: stager
    image: your-registry/dump-image:tag
```

### 3. Deploy the Stager Pod

```bash
kubectl apply -f dump-stager-pod.yaml -n ${OKTETO_NAMESPACE}
```

### 4. Monitor the Copy Process

Watch the pod logs:

```bash
kubectl logs -f dump-stager -n ${OKTETO_NAMESPACE}
```

Expected output:
```
Copying dump from /input/db.dump to /dumps/db.dump...
-rw-r--r-- 1 root root 100G Jan 26 10:00 /input/db.dump
Done. Dump now at /dumps/db.dump:
-rw-r--r-- 1 root root 100G Jan 26 10:30 /dumps/db.dump
```

### 5. Verify Completion

Check pod status:

```bash
kubectl get pod dump-stager -n ${OKTETO_NAMESPACE}
```

Should show `Completed` status.

### 6. Access Dump from Other Pods

Once the dump is in the `pg-dumps` PVC, you can mount it in other pods (like PostgreSQL):

```yaml
containers:
  - name: postgres
    volumeMounts:
      - name: dumps
        mountPath: /dumps
        readOnly: true
volumes:
  - name: dumps
    persistentVolumeClaim:
      claimName: pg-dumps
```

Then restore from `/dumps/db.dump`.

## Configuration

### PVC Settings

- **Name**: `pg-dumps`
- **Size**: 50Gi (adjust in dumps-pvc.yaml if needed)
- **Storage Class**: csi-okteto
- **Access Mode**: ReadWriteOnce

### Pod Settings

- **Name**: `dump-stager`
- **Restart Policy**: Never (runs once)
- **Image**: alpine:3.20 (lightweight)

## Integration with PostgreSQL

To use this with the PostgreSQL setup in `postgres-infra/`:

### Option 1: Modify docker-compose.yml

Add the pg-dumps volume to the PostgreSQL service:

```yaml
services:
  main-dev-db:
    volumes:
      - main-dev-data:/var/lib/postgresql/data
      - pg-dumps:/dumps:ro  # Read-only access to dumps
```

Then reference it in the volumes section:

```yaml
volumes:
  main-dev-data:
    driver_opts:
      size: 70Gi
      class: csi-okteto
  pg-dumps:
    name: pg-dumps
    external: true
```

### Option 2: Create a Restore Script

Create a script that copies from the shared PVC:

```bash
#!/bin/bash
# Copy from shared PVC to PostgreSQL data directory
kubectl exec -n ${OKTETO_NAMESPACE} main-dev-db-0 -- \
  cp /dumps/db.dump /var/lib/postgresql/data/db.dump

# Then restore
kubectl exec -n ${OKTETO_NAMESPACE} main-dev-db-0 -- \
  psql -U postgres -d mydatabase < /var/lib/postgresql/data/db.dump
```

## Cleanup

Remove the pod (keeps the PVC and data):

```bash
kubectl delete pod dump-stager -n ${OKTETO_NAMESPACE}
```

Remove everything including the data:

```bash
kubectl delete pod dump-stager -n ${OKTETO_NAMESPACE}
kubectl delete pvc pg-dumps -n ${OKTETO_NAMESPACE}
```

## Troubleshooting

### Pod stays in Pending state

Check PVC status:
```bash
kubectl describe pvc pg-dumps -n ${OKTETO_NAMESPACE}
```

### Pod fails with "file not found"

The `/input/db.dump` doesn't exist. You need to configure the input source (see step 2 above).

### Check available space

```bash
kubectl exec -n ${OKTETO_NAMESPACE} dump-stager -- df -h /dumps
```

### View pod events

```bash
kubectl describe pod dump-stager -n ${OKTETO_NAMESPACE}
```

## Notes

- The pod uses `restartPolicy: Never`, so it runs once and completes
- The `sync` command ensures data is flushed to disk before completion
- The PVC persists after the pod completes, allowing other pods to access the dump
- This is useful for scenarios where you need to stage dumps from external sources (RDS, S3, etc.)

## Example Workflow

```bash
# 1. Create PVC
kubectl apply -f dumps-pvc.yaml -n ${OKTETO_NAMESPACE}

# 2. Modify dump-stager-pod.yaml to add your dump source
# (e.g., download from S3, mount from another PVC, etc.)

# 3. Run the stager
kubectl apply -f dump-stager-pod.yaml -n ${OKTETO_NAMESPACE}

# 4. Wait for completion
kubectl wait --for=condition=complete pod/dump-stager -n ${OKTETO_NAMESPACE} --timeout=600s

# 5. Verify dump is available
kubectl run -n ${OKTETO_NAMESPACE} -it --rm debug --image=alpine:3.20 \
  --overrides='{"spec":{"volumes":[{"name":"dumps","persistentVolumeClaim":{"claimName":"pg-dumps"}}],"containers":[{"name":"debug","image":"alpine:3.20","command":["sh"],"volumeMounts":[{"name":"dumps","mountPath":"/dumps"}]}]}}' \
  -- ls -lh /dumps/

# 6. Use the dump in your PostgreSQL pod
```
