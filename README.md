# GitLab Runner Installer

> Built with [DevRail](https://devrail.dev) `v1` standards. See [STABILITY.md](STABILITY.md) for component status.

Interactive bash script to install and register a GitLab Runner with a Docker executor on Debian/Ubuntu VMs.

<!-- badges-start -->
[![DevRail compliant](https://devrail.dev/images/badge.svg)](https://devrail.dev)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
<!-- badges-end -->

## What it does

- Adds the official GitLab Runner apt repository
- Installs Docker CE from Docker's official repository (includes Compose v2)
- Installs `gitlab-runner`
- Adds the `gitlab-runner` user to the `docker` group
- Registers the runner with your GitLab instance (Docker executor, privileged mode, docker socket mounted)
- Enables and starts the `gitlab-runner` systemd service
- Verifies the runner is connected

The script is idempotent — it skips steps that have already been completed (existing apt repo, existing Docker install, existing registration).

## Prerequisites

- Debian or Ubuntu VM
- Root access (run with `sudo`)
- Network access to your GitLab instance, `packages.gitlab.com`, and `download.docker.com`
- A GitLab Runner registration token (from your GitLab project or group settings under **Settings > CI/CD > Runners**)

## Usage

All options can be passed as flags, prompted interactively, or mixed. Any option not provided via a flag will be prompted.

```
Usage: install-runner.sh [OPTIONS]

Options:
  -u, --url URL        GitLab instance URL (default: https://gitlab.example.com)
  -t, --token TOKEN    Runner registration token (required)
  -n, --name NAME      Runner description/name (default: <hostname>-runner)
  -T, --tags TAGS      Comma-separated runner tags (default: docker)
  -d, --debug          Enable debug/verbose output
  -y, --yes            Skip confirmation prompt
  -h, --help           Show help message
```

### Interactive mode

```bash
sudo ./install-runner.sh
```

### Non-interactive mode

```bash
sudo ./install-runner.sh \
  -u https://gitlab.mycompany.com \
  -t glrt-xxxxxxxxxxxx \
  -n my-runner \
  -T docker,deploy \
  -y
```

### Debug mode

```bash
sudo ./install-runner.sh -d
```

### Example session

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
