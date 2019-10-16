#!/bin/bash

#----------
# VARIABLES
#----------

LXC_HOST=$1
LXC_CONTAINER=$2
LXC_USER=$3

LXC_REMOTE=${LXC_USER}@${LXC_HOST}
LXC_CONFIG=/tmp/lxc-config/${LXC_CONTAINER}
KUBECONFIG=${LXC_CONFIG}/kubeconfig

#----------
# FUNCTIONS
#----------

log () {
  if [ -n "$1" ]; then
    echo `date -Ins`" $1"
  fi
}

# Create kubectl config file template
template () {
cat <<EOF > ${KUBECONFIG}
apiVersion: v1
clusters:
- cluster:
    insecure-skip-tls-verify: true
    server: https://__LXC_HOST__:__LXC_PORT__
  name: __LXC_CONTAINER__
contexts:
- context:
    cluster: __LXC_CONTAINER__
    user: kubeuser
  name: __LXC_CONTAINER__
current-context: __LXC_CONTAINER__
kind: Config
preferences: {}
users:
- name: kubeuser
  user:
    client-certificate: __LXC_CONFIG__/.minikube/client.crt
    client-key: __LXC_CONFIG__/.minikube/client.key
EOF
}

# Replace values in kubectl file template
replace () {
  sed -i 's/__LXC_HOST__/'"${LXC_HOST}"'/' ${KUBECONFIG}
  sed -i 's/__LXC_CONTAINER__/'"${LXC_CONTAINER}"'/' ${KUBECONFIG}
  sed -i 's/__LXC_CONFIG__/'"\/tmp\/lxc-config\/${LXC_CONTAINER}"'/' ${KUBECONFIG}
  sed -i 's/__LXC_PORT__/'"${LXC_PORT}"'/' ${KUBECONFIG}
}

#----------
# MAIN
#----------

log "### BEGIN ###"
log "# LXC / Launch container ${LXC_CONTAINER}"
ssh ${LXC_REMOTE} lxc launch -p default -p minikube bionic-minikube ${LXC_CONTAINER} -s containers

log "# LXC / Pending IP"
LXC_CONTAINER_IP=""
while [ "${LXC_CONTAINER_IP}" = "" ]; do
  echo -n '.'
  sleep 1
  LXC_CONTAINER_IP=$(ssh ${LXC_REMOTE} lxc list -c 4 ^${LXC_CONTAINER}$ --format csv | grep eth0 | awk '{ print $1 }')
done
log "# DEBUG: LXC_CONTAINER_IP ${LXC_CONTAINER_IP}"

log "# LXC / Minikube / Start"
ssh ${LXC_REMOTE} lxc exec ${LXC_CONTAINER} -- minikube start --apiserver-ips=${LXC_CONTAINER_IP} --apiserver-name=${LXC_CONTAINER} --vm-driver=none

log "# LXC / Add device proxy"
LXC_PORT="12"$(echo ${LXC_CONTAINER_IP} |cut -d. -f4)

log "# DEBUG: tcp:${LXC_HOST}:${LXC_PORT} => tcp:${LXC_CONTAINER_IP}:8443"
ssh ${LXC_REMOTE} lxc config device add ${LXC_CONTAINER} proxy-${LXC_CONTAINER} proxy listen=tcp:${LXC_HOST}:${LXC_PORT} connect=tcp:${LXC_CONTAINER_IP}:8443

log "# LXC / Minikube / Pull config"
mkdir -p ${LXC_CONFIG}
ssh ${LXC_REMOTE} mkdir -p ${LXC_CONFIG}
ssh ${LXC_REMOTE} lxc file pull --recursive ${LXC_CONTAINER}/root/.minikube ${LXC_CONFIG}/
scp -r ${LXC_REMOTE}:${LXC_CONFIG}/.minikube ${LXC_CONFIG}/

log "# Local / Setup kubectl config"
template
replace
echo "### END ###"
echo "# To finalize your local config run the following command:"
echo "export KUBECONFIG=${KUBECONFIG}"
export KUBECONFIG=${KUBECONFIG}

exit 0
