#!/bin/bash
# WSO2 APIM & IS-KM Configuration - Automated Fix Script
# This script applies all identified fixes to your WSO2 deployment

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

echo "======================================"
echo " WSO2 Configuration Automated Fix"
echo "======================================"
echo ""

# Check if running from correct directory
if [ ! -f "docker-compose.yml" ] || [ ! -d "conf" ]; then
    log_error "Please run this script from the root of the WSO2 deployment directory"
    log_error "Expected structure: docker-compose.yml, conf/, dockerfiles/"
    exit 1
fi

log_info "Detected WSO2 deployment structure"
echo ""

# Step 1: Backup existing configurations
log_info "Step 1/6: Creating backups..."
BACKUP_DIR="backups/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

files_to_backup=(
    "conf/is-as-km/repository/conf/deployment.toml"
    "conf/apim/repository/conf/deployment.toml"
    "dockerfiles/is-as-km/fix-identity-xml.sh"
    "dockerfiles/apim/import-iskm-cert.sh"
    "docker-compose.yml"
    "README.md"
)

for file in "${files_to_backup[@]}"; do
    if [ -f "$file" ]; then
        cp "$file" "$BACKUP_DIR/"
        log_success "Backed up: $file"
    else
        log_warn "File not found (skipping): $file"
    fi
done

echo ""

# Step 2: Fix IS-KM password
log_info "Step 2/6: Fixing IS-KM super admin password..."
IS_KM_CONFIG="conf/is-as-km/repository/conf/deployment.toml"

if [ -f "$IS_KM_CONFIG" ]; then
    if grep -q 'password = "Admin123"' "$IS_KM_CONFIG"; then
        sed -i.bak 's/password = "Admin123"/password = "Admin@123"/' "$IS_KM_CONFIG"
        log_success "Updated IS-KM password from 'Admin123' to 'Admin@123'"
    else
        log_info "IS-KM password already correct or uses different format"
    fi
else
    log_error "IS-KM config not found: $IS_KM_CONFIG"
fi

echo ""

# Step 3: Update fix-identity-xml.sh
log_info "Step 3/6: Updating fix-identity-xml.sh with improved error handling..."
FIX_SCRIPT="dockerfiles/is-as-km/fix-identity-xml.sh"

cat > "$FIX_SCRIPT" << 'EOFSCRIPT'
#!/bin/bash
set -euo pipefail

IDENTITY_XML="/home/wso2carbon/wso2is-7.2.0/repository/conf/identity/identity.xml"
BACKUP_FILE="${IDENTITY_XML}.backup.$(date +%s)"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log "INFO: Starting identity.xml fix process"

# Wait for identity.xml generation
timeout=120
while [ ! -f "$IDENTITY_XML" ] && [ $timeout -gt 0 ]; do
    log "INFO: Waiting for identity.xml generation... ${timeout}s remaining"
    sleep 3
    ((timeout-=3))
done

if [ ! -f "$IDENTITY_XML" ]; then
    log "ERROR: identity.xml not found after timeout"
    exit 1
fi

log "INFO: Creating backup"
cp "$IDENTITY_XML" "$BACKUP_FILE" || exit 1

log "INFO: Fixing empty event listener attributes"
sed -i 's/orderId=""/orderId="50"/g' "$IDENTITY_XML"
sed -i 's/priority=""/priority="50"/g' "$IDENTITY_XML"
sed -i 's/order=""/order="50"/g' "$IDENTITY_XML"
sed -i 's/enable=""/enable="true"/g' "$IDENTITY_XML"

# Validate if xmllint available
if command -v xmllint &> /dev/null; then
    if xmllint --noout "$IDENTITY_XML" 2>/dev/null; then
        log "SUCCESS: XML validated"
    else
        log "ERROR: XML validation failed, restoring backup"
        mv "$BACKUP_FILE" "$IDENTITY_XML"
        exit 1
    fi
fi

log "SUCCESS: identity.xml fixed (backup: $BACKUP_FILE)"
EOFSCRIPT

chmod +x "$FIX_SCRIPT"
log_success "Updated fix-identity-xml.sh"

echo ""

# Step 4: Update import-iskm-cert.sh
log_info "Step 4/6: Updating import-iskm-cert.sh with improved error handling..."
CERT_SCRIPT="dockerfiles/apim/import-iskm-cert.sh"

cat > "$CERT_SCRIPT" << 'EOFSCRIPT'
#!/bin/bash
set -euo pipefail

TRUSTSTORE_PATH="/home/wso2carbon/wso2am-4.6.0/repository/resources/security/client-truststore.jks"
TRUSTSTORE_PASS="wso2carbon"
MAX_RETRIES=60
RETRY_INTERVAL=5

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log "INFO: Importing IS-KM certificate"

# Wait for IS-KM
for i in $(seq 1 $MAX_RETRIES); do
    if timeout 2 bash -c "echo > /dev/tcp/is-as-km/9443" 2>/dev/null; then
        log "SUCCESS: IS-KM reachable (attempt $i/$MAX_RETRIES)"
        sleep 2
        break
    fi
    [ $i -eq $MAX_RETRIES ] && { log "ERROR: IS-KM timeout"; exit 1; }
    [ $((i % 10)) -eq 0 ] && log "INFO: Waiting... $i/$MAX_RETRIES"
    sleep $RETRY_INTERVAL
done

# Fetch certificate
log "INFO: Fetching certificate"
if ! openssl s_client -connect is-as-km:9443 -showcerts </dev/null 2>/dev/null | \
    sed -n '/BEGIN CERTIFICATE/,/END CERTIFICATE/p' > /tmp/is-km-cert.pem; then
    log "ERROR: Certificate fetch failed"
    exit 1
fi

[ ! -s /tmp/is-km-cert.pem ] && { log "ERROR: Empty certificate"; exit 1; }

# Validate certificate
if ! openssl x509 -in /tmp/is-km-cert.pem -noout -text >/dev/null 2>&1; then
    log "ERROR: Invalid certificate"
    exit 1
fi

# Remove existing if present
keytool -delete -alias is-km-cert -keystore "$TRUSTSTORE_PATH" \
    -storepass "$TRUSTSTORE_PASS" -noprompt 2>/dev/null || true

# Import certificate
if keytool -import -alias is-km-cert -file /tmp/is-km-cert.pem \
    -keystore "$TRUSTSTORE_PATH" -storepass "$TRUSTSTORE_PASS" -noprompt 2>&1; then
    log "SUCCESS: Certificate imported"
else
    log "ERROR: Import failed"
    exit 1
fi

rm -f /tmp/is-km-cert.pem
log "INFO: Starting APIM"
exec /home/wso2carbon/docker-entrypoint.sh
EOFSCRIPT

chmod +x "$CERT_SCRIPT"
log_success "Updated import-iskm-cert.sh"

echo ""

# Step 5: Update docker-compose.yml
log_info "Step 5/6: Updating docker-compose.yml..."

if grep -q "restart:" docker-compose.yml; then
    log_info "docker-compose.yml already has restart policies"
else
    log_info "Adding restart policies to docker-compose.yml"
    
    # Add restart policy to is-as-km
    sed -i '/^  is-as-km:/a\    restart: on-failure:3' docker-compose.yml
    
    # Add restart policy to api-manager
    sed -i '/^  api-manager:/a\    restart: on-failure:3' docker-compose.yml
    
    # Add restart policy to mysql
    sed -i '/^  mysql:/a\    restart: on-failure:3' docker-compose.yml
    
    log_success "Added restart policies"
fi

echo ""

# Step 6: Update README.md
log_info "Step 6/6: Updating README.md documentation..."

if grep -q "Password: admin" README.md; then
    sed -i.bak 's/\* Password: admin/\* Password: Admin@123/' README.md
    
    # Add password policy note after the password line
    sed -i '/\* Password: Admin@123/a\
\
**Password Policy Requirements:**\
- Minimum 8 characters\
- Must contain lowercase (a-z), uppercase (A-Z), number (0-9), and special character\
- Default password: `Admin@123` (change immediately in production)' README.md
    
    log_success "Updated README.md with correct password and policy"
else
    log_info "README.md already updated or uses different format"
fi

echo ""
echo "======================================"
log_success "All fixes applied successfully!"
echo "======================================"
echo ""

echo "Summary of changes:"
echo "  ✓ IS-KM password updated to meet policy"
echo "  ✓ Shell scripts improved with error handling"
echo "  ✓ Docker restart policies added"
echo "  ✓ README.md documentation updated"
echo ""

echo "Backups saved in: $BACKUP_DIR"
echo ""

log_info "Next steps:"
echo "  1. Review the changes (check git diff)"
echo "  2. Rebuild containers: docker-compose down -v && docker-compose build --no-cache"
echo "  3. Start deployment: docker-compose up -d"
echo "  4. Monitor logs: docker-compose logs -f is-as-km"
echo ""

log_warn "IMPORTANT: Change default passwords in production!"
echo ""

exit 0
