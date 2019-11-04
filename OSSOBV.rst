==========================
OSSO B.V. edits of Horizon
==========================

*This repository contains READMEs and changes to the Horizon codebase,
needed to make things work. Right now there are no plans for make PRs in
upstream. As I'm totally new to this project, and cannot yet determine
whether fixes are appropriate for upstream inclusion.*

That being said, let's dive in:


Logging
-------

Most important DEBUG logging for keystone, can be enabled in
``/etc/keystone/keystone.conf``:

.. code-block:: inifile

    [DEFAULT]
    log_dir = /var/log/keystone
    debug = true
    # ^- or false ;)

It will populate ``/var/log/keystone/keystone-wsgi-admin.log``.
Super-useful, for instance to switch to the new scope-enforced policies
(see later in this document).


Scope-enforced policies and policy.yaml
--------------------------------------

We can NOT set ``[oslo_policy] enforce_scope = true``, even though we've
taken the new defaults from  `<ossobv_policy.yaml>`_:

.. code-block:: inifile

    [oslo_policy]
    enforce_scope = false

See this comment bit::

    # Once keystone defaults ``keystone.conf [oslo_policy]
    # enforce_scope=True``, the ``system_scope:all`` bits of these check
    # strings can be removed since that will be handled automatically by
    # scope_types in oslo.policy's RuleDefault objects.

The problem is the role and the grants, for which we need domain scope::

    # Because scope=['system'], we must use enforce_scope=False :-(
    "identity:list_roles": "role:reader"

    # Here, the scope is okay, but the default reader perms are not
    # sufficient for domain admins.
    "identity:list_grants": "(role:reader and system_scope:all) or \
      (role:reader and token.domain.id:%(target.project.domain_id)s)"
    "identity:create_grant": "(role:admin and system_scope:all) or \
      (role:admin and token.domain.id:%(target.project.domain_id)s)"
    "identity:revoke_grant": "(role:admin and system_scope:all) or \
      (role:admin and token.domain.id:%(target.project.domain_id)s)"

So, we'll have to go with the provided (new-style default) policy.xml,
and add the above rules.

Also note that the policy-file filename is also set in ``keystone.conf``:

.. code-block:: inifile

    [oslo_policy]
    policy_file = policy.yaml


CLI setup and Permissions
-------------------------

Setup ``openstack(1)`` using virtualenv:

.. code-block:: console

    # virtualenv /usr/local/lib/python3.6-openstack --python=$(which python3)
    # . /usr/local/lib/python3.6-openstack/bin/activate && hash -r
    # pip3 install openstackclient
    # deactivate

    # ln -s /usr/local/lib/python3.6-openstack/bin/openstack \
        /usr/local/bin/openstack

With the new scope permissions, we require 3 kinds of os-cloud config,
because they decide the scope of the access tokens:

``~/.config/openstack/clouds.yaml``:

.. code-block:: yaml

    clouds:

      sysadmin:
        auth:
          auth_url: https://KEYSTONE/
          # system scope
          # list_projects->ok (system_scope:all)
          system_scope: all
          user_domain_name: DOMAIN
          username: USERNAME
          password: PASSWORD
        identity_api_version: 3
        region_name: REGION

      domadmin:
        auth:
          auth_url: https://KEYSTONE/
          # domain scope
          # list_projects->ok (domain_id:%(target.domain_id)s)
          domain_name: DOMAIN
          user_domain_name: DOMAIN
          username: USERNAME
          password: PASSWORD
        identity_api_version: 3
        region_name: REGION

      user:
        auth:
          auth_url: https://KEYSTONE/
          # domain scope, with project?
          # list_projects->fail, list_user_projects->ok
          domain_name: DOMAIN
          user_domain_name: DOMAIN
          username: USERNAME
          password: PASSWORD
          project_name: PROJECT
          project_domain_name: DOMAIN
        identity_api_version: 3
        region_name: REGION


Default roles
-------------

For the dashboard, we'll default to ``user`` being the lowest form of
being, less powerful than readers:

.. code-block:: console

    $ openstack --os-cloud sysadmin implied role create reader \
        --implied-role user
    +------------+------------+
    | Field      | Value      |
    +------------+------------+
    | implies    | dc90452... |
    | prior_role | 4061b60... |
    +------------+------------+

    $ openstack --os-cloud sysadmin implied role list
    +------------+------------+--------------+--------------+
    | Prior Role | Prior Name | Implied Role | Implied Name |
    +------------+------------+--------------+--------------+
    | 7931b42... | admin      | 5766f49...   | member       |
    | 5766f49... | member     | 4061b60...   | reader       |
    | 4061b60... | reader     | dc90452...   | user         |
    +------------+------------+--------------+--------------+

These implied roles have to be fixed if you happen to delete the
existing roles.


Creating cloud admins / superusers
----------------------------------

Give system scope to the ``sudomain-admins``, so all members get SU powers::

    $ openstack --os-cloud sysadmin role assignment list --names --system=all
    +-------+---------------+----------------------+------+-----+-----+
    | Role  | User          | Group                | Proj | Dom | Sys |
    +-------+---------------+----------------------+------+-----+-----+
    | admin | admin@Default |                      |      |     | all |
    | admin |               | sudomain-admins@acme |      |     | all |
    +-------+---------------+----------------------+------+-----+-----+

Others don't need system scope at this point.


Domain admin conventions
------------------------

* Create domain ``acme`` and group ``acme-admins``.
* Make the ``acme-admins`` a group admin, using the CLI::

    openstack --os-cloud sysadmin \
      role add admin --group acme-admins --group-domain acme \
      --domain acme

    # see: contrib/oio-openstack dagroup-assign

* Now, if you want *sysadmin* access from the Horizon dashboard to the
  containers, you'll need to give all sysadmins permissions to the
  ``acme-admins`` group::

    for su in sysadmin1 sysadmin2 sysadmin3; do
      openstack --os-cloud sysadmin group add user acme-admins $su
    done

    # see: contrib/oio-openstack dagroup-assign-su

* Users from the new domain can now be made domain admin by adding them
  to the ``acme-admins`` group.
* When creating projects in the ``acme`` domain, make sure all projects
  assign ``admin`` role to the ``acme-admins`` group.


Federation/IDP/OIDC and user mapping
------------------------------------

We don't use Federated users, as granting permissions to outside the
Federated domain did not work as we would like. Using type=local users
instead.

Adding domains/users to Kleides:

* See the eample user mapping config in: `<ossobv_kleides_mapping.yaml>`_
* Wipe passwords of Kleides users so they cannot log in the regular way::

    openstack --os-cloud sysadmin user set johndoe --password ''

* Add appropriate Team to user, and the right SSO-login perms.


Upgrading keystone
------------------

1. database backup
2. ``keystone-manage db_sync``
