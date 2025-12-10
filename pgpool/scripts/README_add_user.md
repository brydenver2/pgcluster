# Adding New Users to Pgpool Authentication

## The Problem

When you create a new user in PostgreSQL, pgpool cannot automatically authenticate them because:

1. PostgreSQL uses SCRAM-SHA-256 authentication (default in modern PostgreSQL)
2. Pgpool's `pool_passwd` file needs **plain passwords** for SCRAM authentication
3. Once a password is hashed in PostgreSQL, you cannot retrieve the plain password

## Solutions

### Option 1: Add User to pool_passwd (Simple but requires plain password)

If you know the plain password for the user, use the helper script:

```bash
# Inside pgpool container
/scripts/add_user_to_pool_passwd.sh myuser mypassword

# Or from host
docker exec pgpool /scripts/add_user_to_pool_passwd.sh myuser mypassword
```

**Security Note:** This stores the password in plain text in `/etc/pgpool-II/pool_passwd`. Ensure proper file permissions (600).

### Option 2: Enable pool_hba Authentication (Recommended for Production)

Enable `pool_hba` to allow pgpool to pass authentication through to PostgreSQL:

1. **Edit pgpool configuration** (`/etc/pgpool-II/pgpool.conf`):
   ```
   enable_pool_hba = on
   ```

2. **Configure pool_hba.conf** (`/etc/pgpool-II/pool_hba.conf`):
   ```
   # TYPE  DATABASE    USER        ADDRESS                 METHOD
   host    all         all         0.0.0.0/0              scram-sha-256
   host    all         all         ::/0                   scram-sha-256
   ```

3. **Restart pgpool** (required for enable_pool_hba change):
   ```bash
   docker restart pgpool
   ```

With this setup:
- Pgpool forwards authentication to PostgreSQL
- You don't need to maintain `pool_passwd`
- New users work automatically
- More secure (no plain passwords stored)

### Option 3: Use pg_enc for AES Encryption (Advanced)

Pgpool can use AES-encrypted passwords instead of plain text:

1. **Create encryption key** (one time):
   ```bash
   pg_enc --gen-key
   ```

2. **Encrypt password**:
   ```bash
   pg_enc -m -u myuser -p
   # Enter password when prompted
   ```

3. **Add encrypted entry to pool_passwd**:
   Copy the output from pg_enc to `/etc/pgpool-II/pool_passwd`

4. **Reload pgpool**:
   ```bash
   pgpool reload
   ```

## Workflow for Creating New Users

### Current Setup (Plain Passwords in pool_passwd)

When creating a new PostgreSQL user:

```bash
# 1. Create user in PostgreSQL (on primary node)
docker exec pg01 psql -U postgres -c "CREATE USER myuser WITH PASSWORD 'mypassword';"

# 2. Add to pgpool authentication
docker exec pgpool /scripts/add_user_to_pool_passwd.sh myuser mypassword

# 3. Test connection through pgpool
psql -h 10.0.10.90 -p 9999 -U myuser -d postgres
```

### Recommended Setup (With pool_hba enabled)

Once you enable `pool_hba`:

```bash
# 1. Create user in PostgreSQL (on primary node)
docker exec pg01 psql -U postgres -c "CREATE USER myuser WITH PASSWORD 'mypassword';"

# 2. That's it! User can now connect through pgpool automatically
psql -h 10.0.10.90 -p 9999 -U myuser -d postgres
```

## Enabling pool_hba in Your Setup

To enable `pool_hba` authentication, you need to modify the entrypoint script:

**File:** `pgpool/bin/entrypoint.sh`

Find the line (around line 342):
```bash
enable_pool_hba = off
```

Change to:
```bash
enable_pool_hba = on
```

Then rebuild and restart the pgpool container:
```bash
cd /Users/bwallace/Documents/GitHub/pgcluster
docker-compose build pgpool
docker-compose up -d pgpool
```

## Security Considerations

| Method | Security | Ease of Use | Auto-sync |
|--------|----------|-------------|-----------|
| Plain passwords in pool_passwd | Low - passwords in clear text | Easy | Manual |
| AES encrypted in pool_passwd | Medium - encrypted but key on same server | Medium | Manual |
| pool_hba enabled | High - no passwords stored in pgpool | Very Easy | Automatic |

**Recommendation:** Use `enable_pool_hba = on` for production environments.

## Troubleshooting

### "valid password not found" error

This means pgpool doesn't have the user's password. Options:
1. Add user to pool_passwd with the script
2. Enable pool_hba authentication

### "password authentication failed" error

This means the password in pool_passwd doesn't match PostgreSQL:
1. Verify the password is correct
2. Re-add the user with the correct password
3. Or enable pool_hba to bypass pool_passwd

### Users created before pgpool restart work fine

The `entrypoint.sh` adds initial users (postgres, repmgr, hcuser, etc.) to pool_passwd at startup. These work because their plain passwords are known. New users created after startup need to be added manually or use pool_hba.
