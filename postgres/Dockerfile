FROM debian:12
ENV MAJORVER=17
ENV MINORVER=5
ENV PGVER=17
ENV REPMGRVER=5.5.0
ENV PGPOOLMAJOR=4.6
ENV PGPOOLVER=4.6.0
ENV docker=yes
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get upgrade -y && \
    apt-get install -y \
    libxslt1.1 sudo openssh-server openssh-client jq passwd rsync \
    systemd iproute2 python3 python3-pip hostname inotify-tools wget curl \
    ca-certificates gnupg lsb-release supervisor locales && \
    apt-get clean && rm -rf /var/lib/apt/lists/*
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
RUN mkdir /var/run/sshd
RUN [ -f /etc/ssh/ssh_host_rsa_key ] || ssh-keygen -t rsa -b 4096 -f /etc/ssh/ssh_host_rsa_key -N ''
RUN useradd -u 50010 -m postgres
# Install PostgreSQL repository
RUN install -d /usr/share/postgresql-common/pgdg && \
    curl -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc --fail https://www.postgresql.org/media/keys/ACCC4CF8.asc && \
    sh -c 'echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
# Install PostgreSQL Anonymizer repository
RUN curl -fsSL https://apt.dalibo.org/labs/debian_public_key.asc | gpg --dearmor -o /usr/share/keyrings/dalibo-archive-keyring.gpg && \
    sh -c 'echo "deb [signed-by=/usr/share/keyrings/dalibo-archive-keyring.gpg] https://apt.dalibo.org/labs $(lsb_release -cs)-dalibo main" > /etc/apt/sources.list.d/dalibo.list'
RUN apt-get update && apt-get install -y postgresql-${MAJORVER} postgresql-contrib-${MAJORVER} && apt-get clean && rm -rf /var/lib/apt/lists/*
# Install pgpool2 and extensions
RUN apt-get update && apt-get install -y postgresql-${MAJORVER}-pgpool2 pgpool2 && apt-get clean && rm -rf /var/lib/apt/lists/*
# Install repmgr
RUN apt-get update && apt-get install -y postgresql-${MAJORVER}-repmgr && apt-get clean && rm -rf /var/lib/apt/lists/*
# Install pgvector and anon extensions
RUN apt-get update && apt-get install -y postgresql-${MAJORVER}-pgvector postgresql-${MAJORVER}-pg-anonymizer && apt-get clean && rm -rf /var/lib/apt/lists/*
RUN mkdir -p /var/log/repmgr && chown postgres:postgres /var/log/repmgr
RUN mkdir -p /etc/repmgr/${PGVER} && chown postgres:postgres /etc/repmgr/${PGVER}
RUN mkdir -p /data /backup /archive && chown -R postgres:postgres /data /backup /archive && chmod 755 /data /archive
ENV PGDATA /data
ENV PATH=$PATH:/usr/lib/postgresql/${MAJORVER}/bin
ENV LANG=en_US.UTF-8
RUN usermod -aG sudo postgres 
RUN echo "Defaults:postgres !requiretty" > /etc/sudoers.d/postgres && \
    echo "postgres ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers.d/postgres
RUN echo postgres:postgres | chpasswd
RUN echo root:postgres | chpasswd
# .bashrc is needed for connections via ssh
RUN echo "export PATH=\$PATH:/usr/lib/postgresql/${MAJORVER}/bin" > /etc/profile.d/postgres.sh
RUN echo "[ -f /etc/profile ] && source /etc/profile" >> /home/postgres/.bashrc && \
    echo "export PGDATA=/data PGVER=${PGVER} " >> /home/postgres/.bashrc
RUN echo "*:*:postgres:postgres" > /home/postgres/.pcppass && chown postgres:postgres /home/postgres/.pcppass && chmod 600 /home/postgres/.pcppass
ADD scripts /scripts
ADD pgconfig /opt/pgconfig
RUN chown -R postgres:postgres /scripts 
#ADD ./bin/entrypoint.supervisor /entrypoint.sh
#RUN chmod +x /entrypoint.sh
ADD get_master.sh /home/postgres/get_master.sh
RUN chown postgres:postgres /home/postgres/get_master.sh && chmod 750 /home/postgres/get_master.sh
ADD supervisord.conf /etc/supervisor/supervisord.conf
# Make ssh connection easier
RUN echo "StrictHostKeyChecking no" >> /etc/ssh/ssh_config && \
    echo "UserKnownHostsFile /dev/null" >> /etc/ssh/ssh_config 
#    echo "LogLevel QUIET" >> /etc/ssh/ssh_config
# ssh listen on port 222
RUN sed -i -e "s/^#Port 22/Port 222/" /etc/ssh/sshd_config
ADD ssh_keys /home/postgres/.ssh 
RUN chown -R postgres:postgres /home/postgres/.ssh && chmod 700 /home/postgres/.ssh && chmod 644 /home/postgres/.ssh/* && chmod 600 /home/postgres/.ssh/id_rsa && chmod 600 /home/postgres/.ssh/authorized_keys
RUN rm -f /run/nologin
ENV PATH=$PATH:/usr/lib/postgresql/${MAJORVER}/bin
ADD initdb.sh /scripts/initdb.sh
EXPOSE 5432
EXPOSE 222
VOLUME ["/data","/archive","/backup"]
# if the file $PGDATA/postgres.conf does not exist initdb will initialize the cluster and create db phoenix
#  and db users (two per microservice)
CMD ["/usr/bin/supervisord","--configuration=/etc/supervisor/supervisord.conf"]
#CMD ["tail","-f","/etc/supervisor/supervisord.conf"]
