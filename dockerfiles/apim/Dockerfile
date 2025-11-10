# set base Docker image to WSO2 API Manager Docker image with latest WSO2 Updates

FROM wso2/wso2am:4.6.0

ARG MYSQL_CONNECTOR_VERSION=8.0.30

# add MySQL JDBC connector to server home as a third party library
ADD --chown=wso2carbon:wso2 https://repo1.maven.org/maven2/mysql/mysql-connector-java/${MYSQL_CONNECTOR_VERSION}/mysql-connector-java-${MYSQL_CONNECTOR_VERSION}.jar ${WSO2_SERVER_HOME}/repository/components/dropins/

# Copy certificate import script
COPY --chown=wso2carbon:wso2 import-iskm-cert.sh /home/wso2carbon/
RUN chmod +x /home/wso2carbon/import-iskm-cert.sh

# Use custom entrypoint to import IS-KM certificate before starting
ENTRYPOINT ["/home/wso2carbon/import-iskm-cert.sh"]
