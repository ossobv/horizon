"""
WSGI config for openstack_dashboard project.

It exposes the WSGI callable as a module-level variable named ``application``.

For more information on this file, see
https://docs.djangoproject.com/en/{{ docs_version }}/howto/deployment/wsgi/
"""

import os

from django.core.wsgi import get_wsgi_application

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "openstack_dashboard.settings")

application = get_wsgi_application()
