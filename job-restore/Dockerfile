FROM postgres:13

# Install additional tools if needed
RUN apt-get update && apt-get install -y \
    bash \
    coreutils \
    && rm -rf /var/lib/apt/lists/*

# Copy the restore script from current directory
COPY restore-in-pod.sh /usr/local/bin/restore-in-pod.sh
RUN chmod +x /usr/local/bin/restore-in-pod.sh

# Set working directory
WORKDIR /var/lib/postgresql/data

# Default command runs the restore script
CMD ["/usr/local/bin/restore-in-pod.sh"]
