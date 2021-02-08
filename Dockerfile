FROM ubuntu:bionic

ARG RESTIC_VERSION=0.9.6

RUN apt-get update && \
    apt-get install curl mariadb-client postgresql-client gnupg rsync -y && \
    rm -rf /var/lib/apt/lists/*

RUN curl -L https://github.com/restic/restic/releases/download/v${RESTIC_VERSION}/restic_${RESTIC_VERSION}_linux_amd64.bz2 \
        > /usr/local/sbin/restic-${RESTIC_VERSION}.bz2 && \
    bunzip2 /usr/local/sbin/restic-${RESTIC_VERSION}.bz2 && \
    mv /usr/local/sbin/restic-${RESTIC_VERSION} /usr/local/sbin/restic && \
    chmod +x /usr/local/sbin/restic && \
    echo "Using $(restic version)"

RUN apt-get update && \
    apt-get install -y apt-transport-https && \
    curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add - && \
    echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" > /etc/apt/sources.list.d/kubernetes.list && \
    apt-get update && \
    apt-get install -y kubectl jq && \
    rm -rf /var/lib/apt/lists/* && \
    echo "Using $(kubectl version --short)"

ADD usr/local/sbin/restic_backup.sh usr/local/sbin/restic_check.sh /usr/local/sbin/
ADD etc/restic/backup_exclude /etc/restic/backup_exclude
ADD docker/restic_config.sh /etc/restic/config
ADD docker/entrypoint.sh /docker-entrypoint.sh

RUN chmod +x /usr/local/sbin/restic_* /docker-entrypoint.sh && \
    mkdir -p /backup/scripts /backup/data

ENTRYPOINT ["/bin/bash"]
CMD ["/docker-entrypoint.sh"]
