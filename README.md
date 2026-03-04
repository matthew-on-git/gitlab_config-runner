# GitLab Runner Installer

> Built with [DevRail](https://devrail.dev) `v1` standards. See [STABILITY.md](STABILITY.md) for component status.

Interactive bash script to install and register a GitLab Runner with a Docker executor on Debian/Ubuntu VMs.

<!-- badges-start -->
[![DevRail compliant](https://devrail.dev/images/badge.svg)](https://devrail.dev)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
<!-- badges-end -->

## What it does

- Adds the official GitLab Runner apt repository
- Installs `gitlab-runner`, `docker.io`, and `docker-compose`
- Adds the `gitlab-runner` user to the `docker` group
- Registers the runner with your GitLab instance (Docker executor, privileged mode, docker socket mounted)
- Enables and starts the `gitlab-runner` systemd service
- Verifies the runner is connected

The script is idempotent — it skips steps that have already been completed (existing apt repo, existing registration).

## Prerequisites

- Debian or Ubuntu VM
- Root access (run with `sudo`)
- Network access to your GitLab instance and `packages.gitlab.com`
- A GitLab Runner registration token (from your GitLab project or group settings under **Settings > CI/CD > Runners**)

## Usage

```bash
sudo ./install-runner.sh
```

The script will prompt for:

| Prompt | Default | Description |
|---|---|---|
| GitLab instance URL | `https://gitlab.example.com` | Your GitLab server URL |
| Registration token | *(none, required)* | Runner token from GitLab CI/CD settings |
| Runner name | `<hostname>-runner` | Description shown in GitLab UI |
| Runner tags | `docker` | Comma-separated tags for job matching |

A confirmation summary is shown before any changes are made.

### Example

```
$ sudo ./install-runner.sh
[INFO]  GitLab Runner installation and registration

GitLab instance URL [https://gitlab.example.com]: https://gitlab.mycompany.com
Runner registration token: ********
Runner description/name [web01-runner]:
Comma-separated tags [docker]: docker,deploy,production

[INFO]  Configuration summary:
[INFO]    GitLab URL:    https://gitlab.mycompany.com
[INFO]    Runner name:   web01-runner
[INFO]    Runner tags:   docker,deploy,production
[INFO]    Docker image:  alpine:latest

Proceed with installation? [Y/n]: y
```

### Help

```bash
./install-runner.sh --help
```

## Runner configuration

The runner is registered with the following defaults:

| Setting | Value |
|---|---|
| Executor | `docker` |
| Default image | `alpine:latest` |
| Privileged | `true` |
| Docker socket | Mounted (`/var/run/docker.sock`) |
| Run untagged | `false` |
| Locked | `false` |

To modify the runner after installation, edit `/etc/gitlab-runner/config.toml` and restart the service:

```bash
sudo systemctl restart gitlab-runner
```

## Development

See [DEVELOPMENT.md](DEVELOPMENT.md) for coding standards and conventions.

This project follows [Conventional Commits](https://www.conventionalcommits.org/). All commits use the `type(scope): description` format.

```bash
make check    # Run all linting, formatting, and security checks
make lint     # Run shellcheck
make format   # Run shfmt
```

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.
