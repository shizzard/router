FROM erlang:25-slim
LABEL maintainer="Denis Fakhrtdinov <denis@spawnlink.eu>"

# Installing required tools
RUN apt-get update -y && apt-get install -y bash make gcc g++ git curl lsof netcat nano
RUN mkdir -p /tmp

# Running build
COPY . src
RUN rm -rf src/_build src/log/*
RUN cd src && make release-prod

# Copying release
RUN mkdir -p /opt/
RUN mkdir -p /tmp/erl_pipes/
RUN cp -R src/_build/prod/rel/router /opt/.
RUN mkdir -p /var/log/router/

# Cleanup
RUN rm -rf src

# Environment
ENV PATH="/opt/router/bin:$PATH"
ENV RELX_REPLACE_OS_VARS=true
# VMARGS
ENV ROUTER_VMARGS_SNAME=router
ENV ROUTER_VMARGS_COOKIE=router-cookie
ENV ROUTER_VMARGS_LIMIT_ETS=1024
ENV ROUTER_VMARGS_LIMIT_PROCESSES=64535
ENV ROUTER_VMARGS_LIMIT_PORTS=1024
ENV ROUTER_VMARGS_LIMIT_ATOMS=1048576
ENV ROUTER_VMARGS_ASYNC_THREADS=8
ENV ROUTER_VMARGS_KERNEL_POLL=true
# Configuration
ENV ROUTER_APP_LOGGER_LOG_ROOT=/var/log/router/
ENV ROUTER_APP_LOGGER_LOG_LEVEL=debug

## App-specific options
ENV ROUTER_APP_=value

# Runtime
EXPOSE ${ROUTER_APP_}
HEALTHCHECK --interval=10s --timeout=5s --start-period=1m --retries=5 CMD ["router", "help"]
ENTRYPOINT ["router"]
CMD ["foreground"]
