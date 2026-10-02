#!/usr/bin/env bash
# bin/server-bootstrap.sh: one-time hardening + Docker for a fresh Hatiwal VPS
# (Ubuntu 24.04). Idempotent: safe to run again. See docs/INFRASTRUCTURE.md §8.
#
#   ssh ubuntu@<ip> 'sudo bash -s' < bin/server-bootstrap.sh "<deploy public key>"
#
# Leaves the box with:
# - user `kamal` (sudo without password, docker group), deploy key only
# - SSH: keys only, no root login, no password/keyboard-interactive
# - ufw: only 22, 80, 443 open
# - Docker CE from Docker's apt repo; json-file logs capped at 10 MB x 3
# - fail2ban (sshd jail), unattended security upgrades
set -euo pipefail

DEPLOY_KEY="${1:?usage: server-bootstrap.sh '<ssh public key>'}"
export DEBIAN_FRONTEND=noninteractive

echo "== packages"
apt-get update -qq
apt-get -y -qq -o Dpkg::Options::=--force-confold upgrade
apt-get -y -qq install ca-certificates curl gnupg ufw fail2ban unattended-upgrades

echo "== docker"
if ! command -v docker >/dev/null; then
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  . /etc/os-release
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -qq
  apt-get -y -qq install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi
# Without a cap, container logs grow until the disk is full.
cat > /etc/docker/daemon.json <<'JSON'
{ "log-driver": "json-file", "log-opts": { "max-size": "10m", "max-file": "3" } }
JSON
systemctl enable --now docker
systemctl restart docker

echo "== user kamal"
id kamal >/dev/null 2>&1 || adduser --disabled-password --gecos "" kamal
usermod -aG sudo,docker kamal
echo "kamal ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/90-kamal
chmod 440 /etc/sudoers.d/90-kamal
install -d -m 700 -o kamal -g kamal /home/kamal/.ssh
grep -qxF "$DEPLOY_KEY" /home/kamal/.ssh/authorized_keys 2>/dev/null \
  || echo "$DEPLOY_KEY" >> /home/kamal/.ssh/authorized_keys
chown kamal:kamal /home/kamal/.ssh/authorized_keys
chmod 600 /home/kamal/.ssh/authorized_keys

echo "== ssh"
cat > /etc/ssh/sshd_config.d/10-hatiwal.conf <<'CONF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
PubkeyAuthentication yes
CONF
sshd -t
systemctl reload ssh

echo "== firewall"
ufw default deny incoming >/dev/null
ufw default allow outgoing >/dev/null
for p in 22/tcp 80/tcp 443/tcp; do ufw allow "$p" >/dev/null; done
ufw --force enable >/dev/null
ufw status | head -8

echo "== fail2ban + unattended upgrades"
cat > /etc/fail2ban/jail.d/sshd.local <<'CONF'
[sshd]
enabled = true
maxretry = 6
bantime = 1h
CONF
systemctl enable --now fail2ban
systemctl restart fail2ban
echo 'APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";' > /etc/apt/apt.conf.d/20auto-upgrades

echo "== done: $(docker --version)"
