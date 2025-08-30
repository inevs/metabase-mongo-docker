FROM openjdk:11-jre-slim

# Set environment variables
ENV MB_DB_TYPE=h2
ENV JAVA_TIMEZONE=UTC
ENV MB_JETTY_HOST=0.0.0.0
ENV MB_JETTY_PORT=3000

# Install required packages
RUN apt-get update && apt-get install -y \
    curl \
    bash \
    && rm -rf /var/lib/apt/lists/*

# Create metabase user
RUN groupadd -r metabase && useradd --no-log-init -r -g metabase metabase

# Download and install Metabase
RUN curl -o /metabase.jar https://downloads.metabase.com/v0.47.7/metabase.jar

# Create directories and set permissions
RUN mkdir -p /app/data && chown -R metabase:metabase /app

# Switch to metabase user
USER metabase

# Set working directory
WORKDIR /app

# Copy the jar file
COPY --chown=metabase:metabase /metabase.jar /app/metabase.jar

# Expose port
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:3000/api/health || exit 1

# Start Metabase
CMD ["java", "-jar", "/app/metabase.jar"]