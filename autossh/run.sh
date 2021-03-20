#!/usr/bin/with-contenv bashio
set -e
# shellcheck disable=SC2034
__BASHIO_LOG_TIMESTAMP='%F %T'

bashio::log.info "Starting..."

HOSTNAME=$(bashio::config 'hostname')
SSH_PORT=$(bashio::config 'ssh_port')
USERNAME=$(bashio::config 'username')

REMOTE_FORWARDING=$(bashio::config 'remote_forwarding')
LOCAL_FORWARDING=$(bashio::config 'local_forwarding')

OTHER_SSH_OPTIONS=$(bashio::config 'other_ssh_options')
MONITOR_PORT=$(bashio::config 'monitor_port')
GATETIME=$(bashio::config 'gatetime')
INIT_LOCAL_COMMAND=$(bashio::config 'init_local_command')
INIT_REMOTE_COMMAND=$(bashio::config 'init_remote_command')
RETRY_INTERVAL=$(bashio::config 'retry_interval')

KEY_NAME=$(bashio::config 'key_name')
PRIVATE_KEY=$(bashio::config 'private_key')

export AUTOSSH_GATETIME=$GATETIME

KEY_PATH="/data/.ssh"

if bashio::config.true "share"; then
  mkdir -p "/data/share/.ssh"
  mount --bind "/share" "/data/share"
  KEY_PATH="/share/.ssh"
fi

# Generate SSH key or use the provided one
bashio::log.info "key_path is '${KEY_PATH}'"
bashio::log.info "key_name is '${KEY_NAME}'"
if [ -n "${PRIVATE_KEY}" ]; then
  bashio::log.info "Using private key from configuration"
  mkdir -p "${KEY_PATH}"
  echo -e "${PRIVATE_KEY}" > "${KEY_PATH}/${KEY_NAME}"
  chmod 600 "${KEY_PATH}/${KEY_NAME}"
else
  if [ ! -f "${KEY_PATH}/${KEY_NAME}" ]; then
    bashio::log.info "Generating private key"
    mkdir -p "${KEY_PATH}"
    ssh-keygen -b 4096 -t rsa -C "addon_autossh_${KEY_NAME}" -N "" -f "${KEY_PATH}/${KEY_NAME}"
    bashio::log.info "Public key is:"
    cat "${KEY_PATH}/${KEY_NAME}.pub"
  else
    bashio::log.info "Using existing private key"
  fi
fi

command_args="-M ${MONITOR_PORT} -N -q -o ServerAliveInterval=20 -o ServerAliveCountMax=3 -o ExitOnForwardFailure=yes ${USERNAME}@${HOSTNAME} -p ${SSH_PORT} -i ${KEY_PATH}/${KEY_NAME}"

if [ -n "$REMOTE_FORWARDING" ]; then
  bashio::log.info "Processing remote_forwarding argument '$REMOTE_FORWARDING'"
  while read -r line; do
    command_args="${command_args} -R $line"
  done <<< "$REMOTE_FORWARDING"
fi

if [ -n "$LOCAL_FORWARDING" ]; then
  bashio::log.info "Processing local_forwarding argument '$LOCAL_FORWARDING'"
  while read -r line; do
    command_args="${command_args} -L $line"
  done <<< "$LOCAL_FORWARDING"
fi

bashio::log.info "Listing host keys"
ssh-keyscan -p $SSH_PORT $HOSTNAME || true

command_args="${command_args} ${OTHER_SSH_OPTIONS}"

bashio::log.info "AUTOSSH_GATETIME=$AUTOSSH_GATETIME"
bashio::log.info "Command args: ${command_args}"

if [ -n "${INIT_LOCAL_COMMAND}" ] || [ -n "${INIT_REMOTE_COMMAND}" ] ; then
  bashio::log.info "Creating ssh wrapper for init local command '${INIT_LOCAL_COMMAND}' and init remote command '${INIT_REMOTE_COMMAND}'"
  echo -e "#!/bin/bash\n${INIT_LOCAL_COMMAND}\nssh ${OTHER_SSH_OPTIONS} ${USERNAME}@${HOSTNAME} -p ${SSH_PORT} -i ${KEY_PATH}/${KEY_NAME} ${INIT_REMOTE_COMMAND}\nssh \$@" > /data/ssh_wrapper.sh
  chmod +x /data/ssh_wrapper.sh
  export AUTOSSH_PATH="/data/ssh_wrapper.sh"
fi

# Start autossh
until /usr/bin/autossh ${command_args}
do
  bashio::log.error "Failed, retrying in ${RETRY_INTERVAL}s"
  sleep ${RETRY_INTERVAL}
done
