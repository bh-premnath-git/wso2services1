# set base Docker image to WSO2 API Manager Docker image with latest WSO2 Updates
FROM wso2/wso2is:7.2.0
ARG MYSQL_CONNECTOR_VERSION=8.0.30
# copy extensions to the identity server home
COPY dropins ${WSO2_SERVER_HOME}/repository/components/dropins/
# copy customized webapps to the identity server home
COPY webapps ${WSO2_SERVER_HOME}/repository/deployment/server/webapps/

# add MySQL JDBC connector to server home as a third party library
ADD --chown=wso2carbon:wso2 https://repo1.maven.org/maven2/mysql/mysql-connector-java/${MYSQL_CONNECTOR_VERSION}/mysql-connector-java-${MYSQL_CONNECTOR_VERSION}.jar ${WSO2_SERVER_HOME}/repository/components/lib/

# Copy fix script for identity.xml NumberFormatException issue
COPY --chown=wso2carbon:wso2 fix-identity-xml.sh /home/wso2carbon/
RUN chmod +x /home/wso2carbon/fix-identity-xml.sh

# Create entrypoint wrapper to apply fix after identity.xml generation
RUN printf '#!/bin/bash\n/home/wso2carbon/fix-identity-xml.sh &\nexec ${WSO2_SERVER_HOME}/bin/wso2server.sh "$@"\n' > /home/wso2carbon/entrypoint.sh && \
    chmod +x /home/wso2carbon/entrypoint.sh

ENTRYPOINT ["/home/wso2carbon/entrypoint.sh"]
