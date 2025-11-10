#!/bin/bash
set -e

IDENTITY_XML="/home/wso2carbon/wso2is-7.2.0/repository/conf/identity/identity.xml"

# Wait for identity.xml to be generated
timeout=120
while [ ! -f "$IDENTITY_XML" ] && [ $timeout -gt 0 ]; do
    echo "Waiting for identity.xml generation..."
    sleep 3
    ((timeout-=3))
done

if [ -f "$IDENTITY_XML" ]; then
    echo "Fixing empty event listener attributes in identity.xml..."
    sed -i 's/orderId=""/orderId="50"/g' "$IDENTITY_XML"
    sed -i 's/priority=""/priority="50"/g' "$IDENTITY_XML"
    sed -i 's/order=""/order="50"/g' "$IDENTITY_XML"
    sed -i 's/enable=""/enable="true"/g' "$IDENTITY_XML"
    echo "identity.xml fixed successfully"
else
    echo "Warning: identity.xml not found at $IDENTITY_XML"
fi
