FROM confluentinc/cp-kafka-connect:7.7.7

# Copy any locally provided plugins (drop jars under docker/kafka-connect/plugins/).
USER root
COPY plugins/ /usr/share/confluent-hub-components/
RUN chmod -R 755 /usr/share/confluent-hub-components
USER appuser
