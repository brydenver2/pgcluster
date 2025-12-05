FROM debian:12
MAINTAINER ptim007@yahoo.com
ENV PGVER=17
ENV PGPOOLMAJOR=4.6
ENV PGPOOLVER=4.6.0
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get upgrade -y && \
    apt-get install -y passwd sudo ca-certificates gnupg lsb-release curl && \
    apt-get clean && rm -rf /var/lib/apt/lists/*
RUN groupadd -g 50010 postgres && useradd -u 50010 -g postgres -m postgres 
RUN usermod -aG sudo postgres && echo "postgres:postgres" | chpasswd
# Install PostgreSQL repository
RUN install -d /usr/share/postgresql-common/pgdg && \
    curl -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc --fail https://www.postgresql.org/media/keys/ACCC4CF8.asc && \
    sh -c 'echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
RUN apt-get update && apt-get install -y \
    postgresql-client-${PGVER} postgresql-${PGVER}-pgpool2 pgpool2 \
    sudo openssh-client openssh-server iproute2 iputils-arping && \
    apt-get clean && rm -rf /var/lib/apt/lists/*
# postgres can do sudo
RUN echo "Defaults:postgres !requiretty" > /etc/sudoers.d/postgres && \
    echo "postgres ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers.d/postgres
RUN echo root:postgres | chpasswd
# Make ssh connection easier
RUN echo "StrictHostKeyChecking no" >> /etc/ssh/ssh_config && \
    echo "UserKnownHostsFile /dev/null" >> /etc/ssh/ssh_config && \
    echo "LogLevel QUIET" >> /etc/ssh/ssh_config
ADD ssh_keys /home/postgres/.ssh 
RUN mkdir -p /var/run/pgpool && \
    chown -R postgres:postgres /home/postgres/.ssh && chmod 700 /home/postgres/.ssh && \
    chmod 644 /home/postgres/.ssh/* && chmod 600 /home/postgres/.ssh/id_rsa && chmod 600 /home/postgres/.ssh/authorized_keys && \
    chown postgres:postgres /var/run/pgpool
ADD pool_hba.conf /etc/pgpool-II/
# pcp user is postgres and password is postgres (hard-coded)
# note that this user has nothing to do with postgres or linux, it is purely for pcp
RUN echo "postgres:e8a48653851e28c69d0506508fb27fc5" >> /etc/pgpool-II/pcp.conf
RUN echo "*:*:postgres:postgres" > /home/postgres/.pcppass && \
  chown postgres:postgres /home/postgres/.pcppass && \
  chmod 600 /home/postgres/.pcppass && \
  chown -R postgres:postgres /etc/pgpool-II && \
  chmod +s /usr/bin/arping /usr/sbin/ip
# put a file on /tmp so that we can determine if /tmp is host mounted or not (for pgpool_status file)
RUN touch /tmp/.not_host_mounted
ADD scripts /scripts
ADD bin/entrypoint.sh /
RUN chown postgres:postgres /entrypoint.sh /scripts/* && chmod +x /entrypoint.sh /scripts/*.sh
EXPOSE 9999
USER postgres
CMD ["/entrypoint.sh"]
