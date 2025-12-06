#!/bin/bash

# Script to create Docker Swarm secrets for the PostgreSQL cluster
# Run this script before deploying the stack

set -e

echo "==================================="
echo "PostgreSQL Cluster - Setup Secrets"
echo "==================================="
echo ""

# Check if running in swarm mode
if ! docker info 2>/dev/null | grep -q "Swarm: active"; then
    echo "ERROR: Docker is not running in swarm mode."
    echo "Please initialize swarm first with: docker swarm init"
    exit 1
fi

# Function to create or update a secret
create_secret() {
    local secret_name=$1
    local secret_description=$2
    
    # Check if secret already exists
    if docker secret ls --format "{{.Name}}" | grep -q "^${secret_name}$"; then
        echo ""
        read -p "Secret '${secret_name}' already exists. Remove and recreate? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo "Removing existing secret '${secret_name}'..."
            docker secret rm ${secret_name} || {
                echo "ERROR: Could not remove secret. It may be in use by a service."
                echo "Please remove the service first, then run this script again."
                exit 1
            }
        else
            echo "Keeping existing secret '${secret_name}'"
            return 0
        fi
    fi
    
    # Prompt for password
    echo ""
    echo "Enter ${secret_description}:"
    read -s password
    echo ""
    echo "Confirm ${secret_description}:"
    read -s password_confirm
    echo ""
    
    if [ "$password" != "$password_confirm" ]; then
        echo "ERROR: Passwords do not match!"
        exit 1
    fi
    
    if [ -z "$password" ]; then
        echo "ERROR: Password cannot be empty!"
        exit 1
    fi
    
    # Create the secret
    echo "Creating secret '${secret_name}'..."
    echo -n "$password" | docker secret create ${secret_name} -
    
    if [ $? -eq 0 ]; then
        echo "✓ Secret '${secret_name}' created successfully"
    else
        echo "ERROR: Failed to create secret '${secret_name}'"
        exit 1
    fi
}

# Create secrets
echo "This script will create the following Docker secrets:"
echo "  - postgres_password: Password for the postgres superuser"
echo "  - repmgr_password: Password for replication manager"
echo ""
echo "NOTE: Use strong passwords for production deployments!"
echo ""

create_secret "postgres_password" "postgres superuser password"
create_secret "repmgr_password" "replication manager password"

echo ""
echo "==================================="
echo "✓ All secrets created successfully!"
echo "==================================="
echo ""
echo "You can now deploy your stack with:"
echo "  docker stack deploy -c docker-compose-portainer.yml pgcluster"
echo ""
echo "To view created secrets:"
echo "  docker secret ls"
echo ""
