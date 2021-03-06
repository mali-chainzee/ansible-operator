#!/usr/bin/env bash

# The container image is derived from ansible-runner container image,
# so we also extend the image entrypoint script to add some tests.

# In OpenShift, containers are run as a random high number uid
# that doesn't exist in /etc/passwd, but Ansible module utils
# require a named user. So if we're in OpenShift, we need to make
# one before Ansible runs.
if [ `id -u` -ge 500 ] || [ -z "${CURRENT_UID}" ] ; then

  cat << EOF > /tmp/passwd
root:x:0:0:root:/root:/bin/bash
runner:x:`id -u`:`id -g`:,,,:/runner:/bin/bash
EOF

  cat /tmp/passwd > /etc/passwd
  rm /tmp/passwd
fi

# The RUNNER_PLAYBOOK variable is mandatory
if [ -z "RUNNER_PLAYBOOK" ] ; then
    echo "ERROR - RUNNER_PLAYBOOK not specified. Exiting."
    exit 1
fi

# We only support Git repository for project import. If the project type is
# not specified, we set it to 'local'.
if [ -z "${PROJECT_TYPE}" ] ; then
    echo "WARNING - PROJECT_TYPE not specified. Defaulting to 'local'."
    PROJECT_TYPE="local"
fi

# Collect extra vars from environment and add them to /runner/env/extravars.
# The file is created if it has not been mounted at runtime.
[[ ! -f /runner/env/extravars ]] && echo "---" > /runner/env/extravars
env | grep '^EXTRAVAR_' | while read EV ; do
    EV_KEY=$(echo "$EV" | awk -F '=' '{ print $1; }' | sed 's/^EXTRAVAR_//')
    EV_VALUE=$(echo "$EV" | awk -F '=' '{ print $2; }')
    echo "${EV_KEY}: ${EV_VALUE}" >> /runner/env/extravars
done

# Collect environment variabless from environment and add them to
# /runner/env/envvars. The file is created if it has not been mounted at
# runtime.
[[ ! -f /runner/env/ennvars ]] && echo "---" > /runner/env/envvars
env | grep '^ENVVAR_' | while read ENV ; do
    ENV_KEY=$(echo "$ENV" | awk -F '=' '{ print $1; }' | sed 's/^ENVVAR_//')
    ENV_VALUE=$(echo "$EV" | awk -F '=' '{ print $2; }')
    echo "${ENV_KEY}: ${ENV_VALUE}" >> /runner/env/envvars
done

# Check if the inventory file is present. If not, we create an empty inventory
# with only localhost
if [! -f /runner/inventory/hosts ] ; then
    echo "WARNING - Inventory file is absent. Creating one with localhost."
    echo -e "[all]\nlocalhost" > /runner/inventory/hosts
fi

# Check if the passwords or SSH private key have been provided. If none is
# present, we raise a warning, but continue as the SSH private could be shipped
# in the container image or overridden by the playbook/roles.
if [ ! -f /runner/env/passwords && ! -f /runner/env/ssh_key ] ; then
    echo "WARNING - Both passwords and SSH private key file are absent."
fi

# Handle Git project type
if [ "${PROJECT_TYPE}" == "git" ] ; then
    # Check if PROJECT_URI is present
    if [ -z ${PROJECT_URI} ] ; then
        echo "ERROR - PROJECT_URI not specified. It is mandatory for 'git'."
        exit 1
    fi

    # Clone the Git repository in /runner/project
    echo "INFO - Cloning Git repository: ${PROJECT_URI}"
    git clone ${PROJECT_URI} /runner/project
    if [ $? != 0 ] ; then
        echo "ERROR - Clone of ${PROJECT_URI} failed. Exiting."
        exit 1
    fi
fi

# Check if the specified playbook exists in /runner/project.
if [ ! -f /runner/project/${RUNNER_PLAYBOOK} ] ; then
    echo "ERROR - Playbook /runner/project/${RUNNER_PLAYBOOK} does not exist."
    exit 1
fi

exec tini -- "${@}"
