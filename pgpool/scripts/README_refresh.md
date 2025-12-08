# Pgpool Pool Password Refresh

This script refreshes the `pool_passwd` file from the backend PostgreSQL database without requiring a pgpool restart.

## When to Use

Run this script after:
- Creating new database users/roles in PostgreSQL
- Changing passwords for existing users
- Any time users can't authenticate through pgpool but can connect directly to PostgreSQL

## Usage Options

### Option 1: On-Demand (Manual)

Run the script manually whenever needed:

**Inside the pgpool container:**
```bash
docker exec <pgpool-container> /scripts/refresh_pool_passwd.sh
```

**With Docker Swarm:**
```bash
docker exec $(docker ps -q -f name=pgpool) /scripts/refresh_pool_passwd.sh
```

**Direct execution if you're inside the container:**
```bash
/scripts/refresh_pool_passwd.sh
```

### Option 2: Automatic (Cron Schedule)

Enable automatic refresh by setting the `POOL_PASSWD_REFRESH_CRON` environment variable in your docker-compose file:

```yaml
environment:
  POOL_PASSWD_REFRESH_CRON: "0 */6 * * *"  # Every 6 hours
```

**Cron Schedule Examples:**
- `"*/30 * * * *"` - Every 30 minutes
- `"0 */2 * * *"` - Every 2 hours  
- `"0 0 * * *"` - Daily at midnight
- `"0 */6 * * *"` - Every 6 hours (recommended)
- `"0 2 * * *"` - Daily at 2 AM

**View cron logs:**
```bash
docker exec <pgpool-container> tail -f /var/log/pgpool/pool_passwd_refresh.log
```

## What it does

1. Backs up the current `pool_passwd` file to `pool_passwd.bak`
2. Adds the postgres user with the password from `POSTGRES_PASSWORD` or `POSTGRES_PASSWORD_FILE`
3. Fetches all user passwords from the backend PostgreSQL database
4. Updates the `pool_passwd` file with all users that have md5 or SCRAM-SHA-256 passwords
5. Reloads pgpool configuration (non-disruptive - keeps existing connections)

## Output

The script shows:
- Which users are being added
- Total number of users in the pool_passwd file
- Confirmation that pgpool was reloaded

## Recommendations

- **For production**: Enable automatic refresh with a reasonable interval (e.g., every 6 hours)
- **For development**: Use on-demand refresh after creating users
- **For high-security environments**: Use on-demand only to have full control

## Troubleshooting

If the script fails:
- Check that SSH connection to backend nodes works
- Verify REPMGRPWD_FILE or REPMGRPWD environment variable is set correctly
- Check that the repmgr user has access to pg_authid table
- Review pgpool logs for any errors
- Check cron logs at `/var/log/pgpool/pool_passwd_refresh.log`
