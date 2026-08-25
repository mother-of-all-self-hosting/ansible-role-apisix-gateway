<!--
SPDX-FileCopyrightText: 2024 Slavi Pantaleev
SPDX-FileCopyrightText: 2026 Suguru Hirahara

SPDX-License-Identifier: AGPL-3.0-or-later
-->

# APISIX Gateway Ansible role

This is an [Ansible](https://www.ansible.com/) role which installs the [APISIX Gateway](https://apisix.apache.org/docs/apisix/getting-started/README/) to run as a [Docker](https://www.docker.com/) container wrapped in a systemd service.

This role *implicitly* depends on:

- [`com.devture.ansible.role.playbook_help`](https://github.com/devture/com.devture.ansible.role.playbook_help)
- [`com.devture.ansible.role.systemd_docker_base`](https://github.com/devture/com.devture.ansible.role.systemd_docker_base)

Check [`defaults/main.yml`](defaults/main.yml) for the full list of supported options.

💡 For an Ansible playbook which integrates this role and makes it easier to use, see the [Mother-of-All-Self-Hosting Ansible playbook](https://github.com/mother-of-all-self-hosting/mash-playbook).

## The bundled dashboard (web UI)

Since APISIX 3.13, the [APISIX Dashboard](https://github.com/apache/apisix-dashboard/releases/tag/notice) is no longer a separate project. It ships as a pure front-end inside the `apache/apisix` image this role installs, and APISIX's own nginx serves it — `/ui` redirects to `/ui/`, which serves the bundled assets.

There is nothing to install and nothing to enable: APISIX's `enable_admin_ui` setting defaults to `true` and this role keeps that default (see `apisix_gateway_config_deployment_admin_enable_admin_ui`). The only question is how you reach it.

> [!WARNING]
> **The bundled UI is served by the Admin API's listener, from inside the same nginx `server` block.** It shares that listener's port (`apisix_gateway_config_deployment_admin_admin_listen_port`, `9180` by default) and its `allow_admin` allowlist (`apisix_gateway_config_deployment_admin_allow_admin`, which this role defaults to `0.0.0.0/0`).
>
> **Making the UI reachable therefore makes the Admin API reachable.** There is no way to publish one without the other short of routing individual paths yourself.
>
> What protects each of them is different, and worth being clear about:
>
> - the Admin API rejects requests without a valid key (`apisix_gateway_config_deployment_admin_admin_key`, enforced by `apisix_gateway_config_deployment_admin_admin_key_required`, which defaults to `true`)
> - **the UI itself has no authentication at all.** It is static files. It asks the person using it for an Admin API key and talks to the Admin API from their browser
>
> So exposing this to the internet publishes an unauthenticated login-less admin console for your gateway, backed by a key-protected API. Anyone who finds it cannot change anything without a key, but they can see that you run APISIX and are handed the console to attack it with. Put an authenticating reverse-proxy in front of it (with Traefik, a [basicauth](https://doc.traefik.io/traefik/reference/routing-configuration/http/middlewares/basicauth/) middleware via `apisix_gateway_container_labels_admin_middlewares`), restrict `allow_admin` to addresses you trust, or do not publish it at all.

Reaching it, from least to most exposed:

- **An SSH tunnel** — the safest option, and it needs no configuration change to this role at all beyond publishing the port on the loopback interface. Set `apisix_gateway_container_admin_http_bind_port: "127.0.0.1:9180"`, then run `ssh -L 9180:127.0.0.1:9180 you@your-server` from your machine and open <http://127.0.0.1:9180/ui/>. Nothing is exposed to the network.
- **Through Traefik, with authentication** — set `apisix_gateway_container_labels_admin_enabled: true` and `apisix_gateway_container_labels_admin_hostname`, and put an authenticating middleware in front of the route. This role has no dedicated variable for that (unlike the metrics route, which has `apisix_gateway_container_labels_metrics_middleware_basic_auth_*`), so declare the middleware yourself and reference it by name:

  ```yaml
  apisix_gateway_container_labels_additional_labels_custom:
    # Generate the entry with `htpasswd -nb USERNAME PASSWORD`
    - "traefik.http.middlewares.apisix-gateway-admin-auth.basicauth.users=someone:$apr1$..."

  apisix_gateway_container_labels_admin_middlewares:
    - apisix-gateway-admin-auth
  ```

  Read the warning above before doing this.

If you expose the Admin API but do not want the console published along with it, set `apisix_gateway_config_deployment_admin_enable_admin_ui: false`. `/ui/` then returns a 404 while the Admin API keeps working on the same port.

## Development

### pre-commit

You can optionally install a Git pre-commit hook (via [mise](https://mise.jdx.dev/) + [prek](https://prek.j178.dev/)) that runs formatting and linting checks before each commit. See [`.pre-commit-config.yaml`](./.pre-commit-config.yaml) for which hooks are to be executed.

To install the hook, run the [`just`](https://github.com/casey/just) command below:

```sh
just prek-install-git-pre-commit-hook
```

### Molecule

This role supports [Molecule](https://docs.ansible.com/projects/molecule/), an Ansible testing framework designed for developing and testing Ansible collections, playbooks, and roles.

Refer to [this page](./molecule/README.md) for details about how to utilize it.
