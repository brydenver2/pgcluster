#!/bin/bash

###############################################################################
# SSH Key Generation Script for PGCluster
###############################################################################
#
# Purpose:
# --------
# This script generates new SSH key pairs for secure inter-node communication
# in the PostgreSQL cluster. SSH keys are essential for:
#
# 1. PostgreSQL Replication: Nodes use SSH to communicate during standby 
#    cloning and other replication operations
#
# 2. Pgpool Operations: Pgpool uses SSH to execute remote commands on 
#    PostgreSQL nodes during failover, switchover, and recovery operations
#
# 3. repmgr Cluster Management: repmgr uses SSH for cluster operations like
#    standby registration, promotion, and health checks
#
# Security Note:
# --------------
# SSH keys enable passwordless authentication between cluster nodes. The 
# private keys (id_rsa) should be kept secure. In production environments,
# consider using unique keys per environment and rotating them periodically.
#
# This script generates 4096-bit RSA keys for enhanced long-term security.
# For even better security with smaller key sizes, consider using Ed25519 keys
# by modifying the ssh-keygen command to use -t ed25519 instead of -t rsa.
#
# IMPORTANT SECURITY TRADE-OFFS:
# 1. Empty Passphrase: Keys are generated without a passphrase to enable
#    automated container startup. In production, consider using a secrets
#    management system (HashiCorp Vault, AWS Secrets Manager, etc.) to
#    manage keys with passphrases.
#
# 2. StrictHostKeyChecking=no: The cluster bypasses SSH host key verification
#    for convenience in dynamic container environments. This creates a 
#    vulnerability to man-in-the-middle attacks. For production with fixed
#    hostnames, enable host key checking and populate known_hosts file.
#
# 3. Keys in Repository: Generated keys are stored in the repository for
#    development convenience. Production deployments should generate unique
#    keys per environment and store them securely outside version control.
#
# Usage:
# ------
#   ./generate-ssh-keys.sh [--force]
#
# Options:
#   --force    Overwrite existing SSH keys without prompting
#
# What this script does:
# ----------------------
# 1. Generates a new RSA key pair (4096-bit for enhanced security)
# 2. Copies the keys to all required directories:
#    - postgres/ssh_keys/     (PostgreSQL nodes)
#    - pgpool/ssh_keys/       (Pgpool nodes)
#    - manager/build/ssh_keys/ (Manager container)
# 3. Creates authorized_keys file with the public key
# 4. Creates known_hosts file (with security warnings about StrictHostKeyChecking=no)
# 5. Sets appropriate file permissions (600 for private keys and authorized_keys)
#
# After running this script:
# --------------------------
# Rebuild the Docker images using ./build.sh to incorporate the new keys
#
###############################################################################

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Directories that need SSH keys
POSTGRES_SSH_DIR="postgres/ssh_keys"
PGPOOL_SSH_DIR="pgpool/ssh_keys"
MANAGER_SSH_DIR="manager/build/ssh_keys"

# Temporary directory for key generation
TEMP_DIR="/tmp/pgcluster_ssh_keys_$$"

# Check for force flag
FORCE=0
if [[ "$1" == "--force" ]]; then
  FORCE=1
fi

# Function to print colored messages
print_info() {
  echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
  echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if keys already exist
# Returns 0 (success) if keys exist, 1 if no keys found
check_existing_keys() {
  local keys_exist=1  # Assume no keys exist (will return 1 = failure)
  
  if [[ -f "$POSTGRES_SSH_DIR/id_rsa" ]]; then
    keys_exist=0  # Keys found (will return 0 = success)
    print_warning "Existing SSH keys found in $POSTGRES_SSH_DIR"
  fi
  
  if [[ -f "$PGPOOL_SSH_DIR/id_rsa" ]]; then
    keys_exist=0
    print_warning "Existing SSH keys found in $PGPOOL_SSH_DIR"
  fi
  
  if [[ -f "$MANAGER_SSH_DIR/id_rsa" ]]; then
    keys_exist=0
    print_warning "Existing SSH keys found in $MANAGER_SSH_DIR"
  fi
  
  return $keys_exist
}

# Function to backup existing keys
backup_existing_keys() {
  local backup_dir="ssh_keys_backup_$(date +%Y%m%d_%H%M%S)"
  
  print_info "Backing up existing SSH keys to $backup_dir/"
  mkdir -p "$backup_dir"
  
  if [[ -d "$POSTGRES_SSH_DIR" ]]; then
    cp -r "$POSTGRES_SSH_DIR" "$backup_dir/postgres_ssh_keys"
  fi
  
  if [[ -d "$PGPOOL_SSH_DIR" ]]; then
    cp -r "$PGPOOL_SSH_DIR" "$backup_dir/pgpool_ssh_keys"
  fi
  
  if [[ -d "$MANAGER_SSH_DIR" ]]; then
    cp -r "$MANAGER_SSH_DIR" "$backup_dir/manager_ssh_keys"
  fi
  
  print_info "Backup completed: $backup_dir/"
}

# Function to generate SSH keys
generate_keys() {
  print_info "Creating temporary directory: $TEMP_DIR"
  mkdir -p "$TEMP_DIR"
  
  print_info "Generating new RSA SSH key pair (4096-bit)..."
  # Note: Using empty passphrase (-N '') for containerized environments where:
  # - Keys are used for automated inter-node communication
  # - Passphrases would require manual intervention during container startup
  # - The containers run in a trusted network environment
  # - Keys should be rotated periodically and not used outside the cluster
  # Using 4096-bit RSA for better long-term security
  # Alternative: Consider Ed25519 (ssh-keygen -t ed25519) for better security with smaller keys
  if ! ssh-keygen -t rsa -b 4096 -f "$TEMP_DIR/id_rsa" -N '' -C "pgcluster-internode-communication"; then
    print_error "Failed to generate SSH keys"
    rm -rf "$TEMP_DIR"
    exit 1
  fi
  
  print_info "SSH keys generated successfully"
}

# Function to create authorized_keys file
create_authorized_keys() {
  print_info "Creating authorized_keys file..."
  cp "$TEMP_DIR/id_rsa.pub" "$TEMP_DIR/authorized_keys"
}

# Function to create known_hosts file
create_known_hosts() {
  print_info "Creating known_hosts file with common PostgreSQL hostnames..."
  
  # Create an empty known_hosts file
  # SECURITY NOTE: This cluster uses StrictHostKeyChecking=no in SSH configuration
  # to allow dynamic container hostnames. This creates a potential security vulnerability
  # by making the system susceptible to man-in-the-middle (MITM) attacks.
  # 
  # In production environments with fixed hostnames, you should:
  # 1. Disable StrictHostKeyChecking=no in the SSH configuration
  # 2. Populate this file with actual host keys for each node
  # 3. Use SSH host key verification to prevent MITM attacks
  # 
  # To populate with real host keys, run on each node after deployment:
  #   ssh-keyscan -p 222 -H <hostname> >> known_hosts
  #
  cat > "$TEMP_DIR/known_hosts" <<'EOF'
# PostgreSQL Cluster Known Hosts
# 
# SECURITY WARNING: This cluster uses StrictHostKeyChecking=no which bypasses
# SSH host key verification. This makes the cluster vulnerable to man-in-the-middle attacks.
# 
# For production deployments with static hostnames, populate this file with actual
# host keys and enable StrictHostKeyChecking in SSH configuration.
#
# Format: hostname ssh-rsa AAAAB3NzaC1yc2E...
#
# Example commands to populate (run after cluster deployment):
#   ssh-keyscan -p 222 -H pg01 >> known_hosts
#   ssh-keyscan -p 222 -H pg02 >> known_hosts
#   ssh-keyscan -p 222 -H pg03 >> known_hosts
EOF
}

# Function to copy keys to target directories
copy_keys_to_directories() {
  print_info "Copying SSH keys to target directories..."
  
  # Create directories if they don't exist
  mkdir -p "$POSTGRES_SSH_DIR"
  mkdir -p "$PGPOOL_SSH_DIR"
  mkdir -p "$MANAGER_SSH_DIR"
  
  # Copy to postgres directory
  print_info "  -> $POSTGRES_SSH_DIR/"
  cp "$TEMP_DIR/id_rsa" "$POSTGRES_SSH_DIR/"
  cp "$TEMP_DIR/id_rsa.pub" "$POSTGRES_SSH_DIR/"
  cp "$TEMP_DIR/authorized_keys" "$POSTGRES_SSH_DIR/"
  cp "$TEMP_DIR/known_hosts" "$POSTGRES_SSH_DIR/"
  
  # Copy to pgpool directory
  print_info "  -> $PGPOOL_SSH_DIR/"
  cp "$TEMP_DIR/id_rsa" "$PGPOOL_SSH_DIR/"
  cp "$TEMP_DIR/id_rsa.pub" "$PGPOOL_SSH_DIR/"
  cp "$TEMP_DIR/authorized_keys" "$PGPOOL_SSH_DIR/"
  cp "$TEMP_DIR/known_hosts" "$PGPOOL_SSH_DIR/"
  
  # Copy to manager directory (all files for consistency)
  print_info "  -> $MANAGER_SSH_DIR/"
  cp "$TEMP_DIR/id_rsa" "$MANAGER_SSH_DIR/"
  cp "$TEMP_DIR/id_rsa.pub" "$MANAGER_SSH_DIR/"
  cp "$TEMP_DIR/authorized_keys" "$MANAGER_SSH_DIR/"
  cp "$TEMP_DIR/known_hosts" "$MANAGER_SSH_DIR/"
  
  print_info "SSH keys copied successfully"
}

# Function to set proper permissions
set_permissions() {
  print_info "Setting appropriate file permissions..."
  
  # Private keys should be read-only for owner (600)
  chmod 600 "$POSTGRES_SSH_DIR/id_rsa"
  chmod 600 "$PGPOOL_SSH_DIR/id_rsa"
  chmod 600 "$MANAGER_SSH_DIR/id_rsa"
  
  # Public keys can be readable by all (644)
  chmod 644 "$POSTGRES_SSH_DIR/id_rsa.pub"
  chmod 644 "$PGPOOL_SSH_DIR/id_rsa.pub"
  chmod 644 "$MANAGER_SSH_DIR/id_rsa.pub"
  
  # authorized_keys should be read-only for owner (600) for security
  chmod 600 "$POSTGRES_SSH_DIR/authorized_keys"
  chmod 600 "$PGPOOL_SSH_DIR/authorized_keys"
  chmod 600 "$MANAGER_SSH_DIR/authorized_keys"
  
  # known_hosts should be 644
  chmod 644 "$POSTGRES_SSH_DIR/known_hosts"
  chmod 644 "$PGPOOL_SSH_DIR/known_hosts"
  chmod 644 "$MANAGER_SSH_DIR/known_hosts"
  
  # Directories should be 755
  chmod 755 "$POSTGRES_SSH_DIR"
  chmod 755 "$PGPOOL_SSH_DIR"
  chmod 755 "$MANAGER_SSH_DIR"
  
  print_info "Permissions set successfully"
}

# Function to cleanup
cleanup() {
  if [[ -d "$TEMP_DIR" ]]; then
    print_info "Cleaning up temporary directory..."
    rm -rf "$TEMP_DIR"
  fi
}

# Function to display summary
display_summary() {
  echo ""
  echo "=========================================="
  echo "SSH Key Generation Complete"
  echo "=========================================="
  echo ""
  print_info "New SSH keys have been generated and distributed to:"
  echo "  - $POSTGRES_SSH_DIR/"
  echo "  - $PGPOOL_SSH_DIR/"
  echo "  - $MANAGER_SSH_DIR/"
  echo ""
  print_info "Public key fingerprint:"
  if ssh-keygen -lf "$POSTGRES_SSH_DIR/id_rsa.pub" 2>/dev/null; then
    : # Fingerprint displayed successfully
  else
    print_warning "Could not display key fingerprint (key file may be corrupted)"
  fi
  echo ""
  print_warning "IMPORTANT: Rebuild Docker images to use the new keys:"
  echo "  ./build.sh"
  echo ""
  print_warning "SECURITY NOTE: The new private keys are stored in the repository."
  print_warning "Consider using different keys for production environments."
  echo ""
}

###############################################################################
# Main Script
###############################################################################

echo ""
echo "=========================================="
echo "PGCluster SSH Key Generator"
echo "=========================================="
echo ""

# Check if we're in the right directory
if [[ ! -f "build.sh" ]] || [[ ! -d "postgres" ]]; then
  print_error "This script must be run from the pgcluster root directory"
  exit 1
fi

# Check for existing keys
if check_existing_keys && [[ $FORCE -eq 0 ]]; then
  echo ""
  read -p "Existing SSH keys found. Overwrite? (y/N): " -n 1 -r
  echo ""
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_info "Operation cancelled"
    exit 0
  fi
  
  # Backup existing keys
  backup_existing_keys
fi

# Trap to ensure cleanup on exit
trap cleanup EXIT

# Generate new keys
generate_keys

# Create supporting files
create_authorized_keys
create_known_hosts

# Copy keys to all required directories
copy_keys_to_directories

# Set proper permissions
set_permissions

# Display summary
display_summary

print_info "Done!"
echo ""

exit 0
