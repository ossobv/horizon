FROM ossobv/uwsgi-python:3

# This rarely changes (moved to front)
ARG DEBIAN_FRONTEND=noninteractive
WORKDIR /app
EXPOSE 8080

# Get prerequisites
COPY requirements.txt /tmp/
RUN set -x && \
    build="python3-pip" && libs="" && tools="" && \
    apt-get -q update && \
    apt-get -qy dist-upgrade && \
    apt-get install -y $build $libs $tools && \
    pip3 install --no-cache-dir -U pip idna six && \
    pip3 install --no-cache-dir -r /tmp/requirements.txt && \
    pip3 install --no-cache-dir 'django-redis>=4.10.0' && \
    pip3 freeze && \
    apt-get -qy remove --purge $build && apt-get -qy autoremove --purge && \
    apt-get clean && find /var/lib/apt/lists -delete

# TODO: automate this? git describe --always
# Fixes: "Error: Unable to retrieve version information."
# (pbr.version is picky, so we'll just put 16.0.0 in there)
ENV PBR_VERSION=16.0.0 PBR_VERSION_REMAINDER=osso+9-g272e5ea9c
# Copy application and contrib scripts.
COPY . /app/

RUN set -x && \
    ! find /app/ -name '*.secret_key*' | grep '' && \
    python3 -m compileall . >/dev/null && \
    python3 manage.py collectstatic --noinput -v0 && \
    # (cannot run 'compress' here, as it requires communication with cache)
    # Not sure why these are created now. But we must make them writable.
    find /app/ -name '*.secret_key*' | xargs --no-run-if-empty ls -lda && \
    chown www-data /app/openstack_dashboard/local/.secret_key_store \
      /app/openstack_dashboard/local/_app_openstack_dashboard_local_.secret_key_store.lock && \
    # We require perms for .secret_key_store writing in the local dir.
    chown www-data /app/openstack_dashboard/local

# Run uwsgi as www-data, after some bootstrapping
CMD ["/app/dockrun"]
