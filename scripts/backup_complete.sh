#!/bin/bash

# Complete Backup Script for Docker Migration
# This script creates a backup of MongoDB data AND Metabase data/configuration

set -e  # Exit on any error

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BACKUP_DIR="$PROJECT_ROOT/backups"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="complete_backup_$DATE"
BACKUP_PATH="$BACKUP_DIR/$BACKUP_NAME"

# Load environment variables
if [ -f "$PROJECT_ROOT/.env" ]; then
    source "$PROJECT_ROOT/.env"
else
    echo "Error: .env file not found in $PROJECT_ROOT"
    exit 1
fi

# Default values if not set in .env
MONGO_HOST=${MONGO_HOST:-localhost}
MONGO_PORT=${MONGO_PORT:-27017}
MONGO_ROOT_USERNAME=${MONGO_ROOT_USERNAME:-admin}
MONGO_ROOT_PASSWORD=${MONGO_ROOT_PASSWORD:-mongo_pw}
MONGO_DATABASE=${MONGO_DATABASE:-controlling_db}

echo "=== Complete System Backup Script ==="
echo "Date: $(date)"
echo "Database: $MONGO_DATABASE"
echo "Backup location: $BACKUP_PATH"
echo

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Check if containers are running
echo "Checking container status..."
if ! docker compose ps | grep -q "Up"; then
    echo "Error: Docker containers are not running."
    echo "Run: docker compose up -d"
    exit 1
fi

# Check MongoDB connection
if ! docker exec controlling-mongodb mongosh --quiet --eval "db.adminCommand('ping')" >/dev/null 2>&1; then
    echo "Error: Cannot connect to MongoDB."
    exit 1
fi

echo "✓ All containers are running"

# 1. MONGODB BACKUP
echo
echo "=== MongoDB Backup ==="

# Create database dump using mongodump inside the container
echo "Creating MongoDB database dump..."
docker exec controlling-mongodb mongodump \
    --host localhost:27017 \
    --username "$MONGO_ROOT_USERNAME" \
    --password "$MONGO_ROOT_PASSWORD" \
    --authenticationDatabase admin \
    --db "$MONGO_DATABASE" \
    --out /tmp/backup

# Copy MongoDB backup from container to host
echo "Copying MongoDB backup from container..."
mkdir -p "$BACKUP_PATH/mongodb"
docker cp controlling-mongodb:/tmp/backup "$BACKUP_PATH/mongodb/"

# Create users backup
echo "Creating MongoDB users backup..."
mkdir -p "$BACKUP_PATH/mongodb/users"
docker exec controlling-mongodb mongosh \
    --quiet \
    --username "$MONGO_ROOT_USERNAME" \
    --password "$MONGO_ROOT_PASSWORD" \
    --authenticationDatabase admin \
    --eval "db.getSiblingDB('admin').getUsers()" > "$BACKUP_PATH/mongodb/users/users.json"

# Clean up MongoDB temporary files in container
docker exec controlling-mongodb rm -rf /tmp/backup

# 2. METABASE BACKUP
echo
echo "=== Metabase Backup ==="

# Get Metabase volume information
METABASE_VOLUME=$(docker volume ls | grep metabase | grep controlling | awk '{print $2}' | head -1)
if [ -z "$METABASE_VOLUME" ]; then
    echo "Warning: No Metabase volume found. Checking for volume in docker-compose..."
    METABASE_VOLUME="it-agile-controlling_metabase_data"
fi

echo "Backing up Metabase volume: $METABASE_VOLUME"

# Create a temporary container to access the volume
echo "Creating temporary container to backup Metabase data..."
docker run --rm \
    -v "$METABASE_VOLUME":/source:ro \
    -v "$BACKUP_PATH":/backup \
    alpine:latest \
    sh -c "cd /source && tar -czf /backup/metabase_data.tar.gz ."

# 3. DOCKER VOLUMES BACKUP (Alternative method)
echo
echo "=== Docker Volumes Information ==="
echo "Available volumes:"
docker volume ls | grep controlling

# Backup volume inspection data
docker volume inspect "$METABASE_VOLUME" > "$BACKUP_PATH/metabase_volume_info.json" 2>/dev/null || echo "Could not inspect Metabase volume"

# 4. CONFIGURATION BACKUP
echo
echo "=== Configuration Backup ==="

# Export environment configuration
echo "Backing up configuration files..."
cp "$PROJECT_ROOT/.env" "$BACKUP_PATH/env_backup"
cp "$PROJECT_ROOT/docker-compose.yml" "$BACKUP_PATH/docker-compose_backup.yml"

# Copy any additional config files if they exist
[ -f "$PROJECT_ROOT/metabase.env" ] && cp "$PROJECT_ROOT/metabase.env" "$BACKUP_PATH/"
[ -d "$PROJECT_ROOT/config" ] && cp -r "$PROJECT_ROOT/config" "$BACKUP_PATH/"

# 5. SYSTEM STATE BACKUP
echo "Backing up system state..."
mkdir -p "$BACKUP_PATH/system"

# Docker compose state
docker compose ps > "$BACKUP_PATH/system/container_status.txt"
docker compose config > "$BACKUP_PATH/system/resolved_compose.yml"

# Network information
docker network ls | grep controlling > "$BACKUP_PATH/system/networks.txt" || true

# Volume information
docker volume ls | grep controlling > "$BACKUP_PATH/system/volumes.txt" || true

# Container images
docker compose images > "$BACKUP_PATH/system/images.txt"

# 6. CREATE BACKUP INFO FILE
cat > "$BACKUP_PATH/backup_info.txt" << EOF
Complete System Backup Information
==================================
Created: $(date)
Database: $MONGO_DATABASE
MongoDB Version: $(docker exec controlling-mongodb mongod --version | head -1)
Metabase Volume: $METABASE_VOLUME
Host: $MONGO_HOST:$MONGO_PORT

Backup Contents:
================
mongodb/
  └── backup/$MONGO_DATABASE/     - Database collections and indexes
  └── users/                      - MongoDB users and permissions

metabase_data.tar.gz              - Complete Metabase application data
                                    (dashboards, questions, users, settings)

Configuration Files:
  └── env_backup                  - Environment variables
  └── docker-compose_backup.yml   - Docker compose configuration
  └── metabase_volume_info.json   - Volume metadata

system/
  └── container_status.txt        - Container runtime state
  └── resolved_compose.yml        - Resolved compose configuration
  └── networks.txt                - Docker networks
  └── volumes.txt                 - Docker volumes
  └── images.txt                  - Container images

Restore Instructions:
====================
Run the restore script: ./scripts/restore_complete.sh $BACKUP_NAME

IMPORTANT NOTES:
===============
- This backup contains ALL application data
- MongoDB data: Collections, indexes, users
- Metabase data: Dashboards, questions, users, database connections, settings
- Configuration: Environment and Docker setup
- Metabase will retain all dashboards and configured data sources
EOF

# Calculate sizes
MONGO_SIZE=$(du -sh "$BACKUP_PATH/mongodb" | cut -f1)
METABASE_SIZE=$(du -sh "$BACKUP_PATH/metabase_data.tar.gz" | cut -f1)

# Create compressed archive
echo
echo "Creating compressed archive..."
cd "$BACKUP_DIR"
tar -czf "${BACKUP_NAME}.tar.gz" "$BACKUP_NAME"
rm -rf "$BACKUP_NAME"

# Calculate and display backup size
TOTAL_SIZE=$(du -h "${BACKUP_NAME}.tar.gz" | cut -f1)

echo
echo "=== Backup Completed Successfully ==="
echo "Backup file: $BACKUP_DIR/${BACKUP_NAME}.tar.gz"
echo "Total backup size: $TOTAL_SIZE"
echo "  - MongoDB data: $MONGO_SIZE"
echo "  - Metabase data: $METABASE_SIZE"
echo
echo "Backup contains:"
echo "  ✓ MongoDB database: $MONGO_DATABASE"
echo "  ✓ MongoDB users and permissions"
echo "  ✓ Metabase application data (dashboards, users, settings)"
echo "  ✓ All configuration files"
echo "  ✓ Docker system state"
echo
echo "To restore on new server:"
echo "1. Copy the backup file to the new server"
echo "2. Extract: tar -xzf ${BACKUP_NAME}.tar.gz"
echo "3. Run: ./scripts/restore_complete.sh $BACKUP_NAME"
echo