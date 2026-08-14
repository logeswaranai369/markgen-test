#!/bin/bash
set -o pipefail

# --- persistent logging (Plan 20 M1) --------------------------------------------------------------
# Send every line to BOTH a dedicated markgen log AND cloud-init-output.log, so a failed deploy is
# always diagnosable — even when the CloudStack template's own cloud-init output capture is missing
# (seen live: deploys where cloud-init-output.log was empty and the root cause was unknowable).
exec > >(tee -a /var/log/markgen-install.log /var/log/cloud-init-output.log) 2>&1
echo "MARKGEN_DEPLOY_START ubuntu-24-04 ($(date -u +%FT%TZ))"

# --- stage files (fetch the playbook + shared assets from the published repo) ---------------------
mkdir -p {/usr/local/src/ubuntu-24-04/opt/cloudstack,/usr/local/src/ubuntu-24-04/}

cd /usr/local/src/ubuntu-24-04/opt/cloudstack && wget https://raw.githubusercontent.com/logeswaranai369/markgen-test/main/_common-files/opt/cloudstack/ubuntu-24-04_cleanup.sh
cd /usr/local/src/ubuntu-24-04/opt/cloudstack && wget https://raw.githubusercontent.com/logeswaranai369/markgen-test/main/_common-files/opt/cloudstack/ubuntu-24-04_update.sh
cd /usr/local/src/ubuntu-24-04/ && wget https://raw.githubusercontent.com/logeswaranai369/markgen-test/main/nginx/ubuntu-24-04/ubuntu-24-04.yaml

# --- ensure ansible (bare templates may not carry it), then run the playbook ----------------------
apt_retry() {
  local n=0
  until apt-get -o DPkg::Lock::Timeout=120 "$@"; do
    n=$((n+1))
    if [ $n -ge 20 ]; then return 1; fi
    echo "MARKGEN: apt busy (boot-time updates); retry $n in 15s..."
    sleep 15
  done
}
if ! command -v ansible-playbook >/dev/null 2>&1; then
  echo "MARKGEN: installing ansible + python3 (bare template)"
  if command -v apt-get >/dev/null 2>&1; then
    apt_retry update -y && apt_retry install -y python3 ansible
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y python3 ansible-core || dnf install -y python3 ansible
  elif command -v yum >/dev/null 2>&1; then
    yum install -y python3 ansible
  fi
fi
if ! command -v ansible-playbook >/dev/null 2>&1; then
  echo "MARKGEN: ERROR could not install ansible on this VM"
  echo "MARKGEN_DEPLOY_COMPLETE rc=127"
  exit 127
fi
if command -v ansible-galaxy >/dev/null 2>&1; then
  if ! ansible-galaxy collection list community.mysql 2>/dev/null | grep -qi community.mysql; then
    echo "MARKGEN: installing community.mysql collection (absent on this VM)"
    ansible-galaxy collection install community.mysql >/dev/null 2>&1 \
      || echo "MARKGEN: WARN could not install community.mysql (apps using raw mysql are unaffected)"
  fi
fi

cd /usr/local/src/ubuntu-24-04 && ansible-playbook ubuntu-24-04.yaml -c local
MARKGEN_RC=$?
echo "MARKGEN_DEPLOY_COMPLETE rc=$MARKGEN_RC"
exit $MARKGEN_RC
