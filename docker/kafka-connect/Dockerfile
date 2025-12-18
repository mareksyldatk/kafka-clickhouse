FROM confluentinc/cp-kafka-connect:7.7.7

# Copy pre-downloaded connector plugins into the standard plugin path.
# Drop unpacked connector directories under ./docker/kafka-connect/plugins before building.
USER root
COPY plugins/ /usr/share/confluent-hub-components/
RUN chmod -R 755 /usr/share/confluent-hub-components
USER appuser
