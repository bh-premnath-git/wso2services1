#!/bin/bash
set -e

echo "Importing IS-KM certificate into APIM truststore..."

TRUSTSTORE_PATH="/home/wso2carbon/wso2am-4.6.0/repository/resources/security/client-truststore.jks"
TRUSTSTORE_PASS="wso2carbon"

# Wait for IS-KM to be available
echo "Waiting for IS-KM to be available..."
for i in {1..30}; do
    if timeout 2 bash -c "echo > /dev/tcp/is-as-km/9443" 2>/dev/null; then
        echo "IS-KM is reachable"
        break
    fi
    echo "Waiting for IS-KM... attempt $i/30"
    sleep 5
done

# Get IS-KM certificate
echo "Fetching IS-KM certificate..."
openssl s_client -connect is-as-km:9443 -showcerts </dev/null 2>/dev/null | \
    sed -n '/BEGIN CERTIFICATE/,/END CERTIFICATE/p' > /tmp/is-km-cert.pem

# Import certificate into truststore
if [ -f /tmp/is-km-cert.pem ]; then
    echo "Importing certificate..."
    keytool -import -alias is-km-cert -file /tmp/is-km-cert.pem \
        -keystore "$TRUSTSTORE_PATH" -storepass "$TRUSTSTORE_PASS" -noprompt || true
    echo "Certificate imported successfully"
    rm /tmp/is-km-cert.pem
else
    echo "Failed to fetch certificate"
    exit 1
fi

echo "Starting WSO2 API Manager..."
exec /home/wso2carbon/docker-entrypoint.sh
