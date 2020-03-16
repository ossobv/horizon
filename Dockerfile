FROM ossobv/uwsgi-python:3

# This rarely changes (moved to front)
ARG DEBIAN_FRONTEND=noninteractive
WORKDIR /app
EXPOSE 8080

# Get prerequisites
COPY requirements.txt /tmp/
COPY patches /tmp/patches
COPY venvpatch /tmp/venvpatch

RUN set -x && \
    build="python3-pip" && libs="" && tools="patch" && \
    ln -s /usr/bin/python3 /usr/bin/python && \
    apt-get -q update && \
    apt-get -qy dist-upgrade && \
    apt-get install -y $build $libs $tools && \
    pip3 install --ignore-installed --no-cache-dir -U pip idna six && \
    # Downloading pyScss-1.3.4.tar.gz (120 kB)
    #   ERROR: Command errored out with exit status 1:
    #   Complete output (5 lines):
    #   Traceback (most recent call last):
    #     File "<string>", line 1, in <module>
    #     File "/tmp/pip-install-3j0aeypn/pyScss/setup.py", line 9, in <module>
    #       from setuptools import setup, Extension, Feature
    #   ImportError: cannot import name 'Feature'
    # Apparently, the deprecated 'Feature' got removed from setuptools.
    pip3 install 'setuptools<46' && \
    # Don't forget the pip --constraints file; see tox.ini and
    # https://review.opendev.org/#/c/693000/ and
    # http://lists.openstack.org/pipermail/openstack-discuss/2019-November/011283.html
    pip3 install --no-cache-dir \
      --ignore-installed \
      -c https://releases.openstack.org/constraints/upper/train \
      -r /tmp/requirements.txt && \
    # We need a cache backend, one of these:
    # #django-redis>=4.10.0
    # #python-memcached>=1.59
    pip3 install --no-cache-dir \
      --ignore-installed \
      -c https://releases.openstack.org/constraints/upper/train \
      'django-redis>=4.10.0' && \
    # Apply custom patches.
    /tmp/venvpatch /tmp/patches --apply && \
    apt-get -qy remove --purge $build $tools && \
    apt-get -qy autoremove --purge && \
    apt-get clean && find /var/lib/apt/lists -delete && \
    # Double check =) should yield nothing, even after we autoremoved,
    # as we installed with --ignore-installed.
    pip3 install --no-cache-dir \
      -c https://releases.openstack.org/constraints/upper/train \
      -r /tmp/requirements.txt && \
    pip3 freeze

# TODO: automate this? git describe --always
# Fixes: "Error: Unable to retrieve version information."
# (pbr.version is picky, so we'll just put 16.1.0 in there)
ENV PBR_VERSION=16.2.0 PBR_VERSION_REMAINDER=osso22
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

# Example local docker run in _local.sh:
#
# docker run -d --rm --name horizon_redis redis
# trap 'docker stop horizon_redis' EXIT
# docker run --rm --name horizon --link horizon_redis \
#   -v `pwd`/_local.py:/app/openstack_dashboard/local/local_settings.d/local.py \
#   -p 8000:8080 -it tmp
