# Frequently Asked Questions

## Server Requirements

### Container Runtime

Your server must have Docker CLI or Podman installed. If your container runtime executable is not in your system PATH, you can specify a custom path in the app settings.

### User Permissions

The app executes Docker/Podman commands without `sudo`, so your user account must have the necessary permissions to run these commands without elevated privileges. This typically means adding your user to the `docker` group.

**Important**: NO docker daemon or docker API needs to be enabled for this app. The app simply connects via SSH. It is strongly recommended NOT to open unnecessary ports on your server (such as enabling the docker daemon) as it can expose your server to security threats (since docker.sock can technically mount any volume on your host hence being equivalent to root access).

## Platform-Specific Setup

### Linux Servers (Standard Docker)

Add your user to the docker group:
```bash
sudo usermod -aG docker $USER
sudo reboot
```

### Docker Desktop on macOS

1. Enable 'Remote Login' in System Preferences
2. If using a non-root user, add the user to the docker group

### Synology NAS

If using a non-root user, add the user to the docker group:
```bash
sudo synogroup --add docker
sudo synogroup --memberadd docker $USER
sudo chown root:docker /var/run/docker.sock
```

### QNAP NAS

If using a non-root user, add the user to the administrators group:
```bash
sudo addgroup $USER administrators
```

## Troubleshooting

### Cannot connect with non-root user

The docker commands are executed by the app without `sudo`, so you need to add your non-root user to the docker group. Follow the platform-specific instructions above for your server type.

## Support

Please open a Github issue here on the repository.
