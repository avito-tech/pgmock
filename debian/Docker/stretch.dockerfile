FROM debian:stretch

RUN apt-get update \
    && apt-get install -y git build-essential fakeroot devscripts debhelper wget autopkgtest \
    && echo "deb http://apt.postgresql.org/pub/repos/apt/ stretch-pgdg main" >> /etc/apt/sources.list \
    && wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add - \
    && apt-get update \
    && apt-get install -y postgresql-server-dev-all \
    && dpkg -l | grep -Po "postgresql-server-dev-([\d\.]{2,3})" | sed "s/server-dev-//" | xargs apt-get install -y

ADD run.sh /usr/local/

CMD ["/usr/local/run.sh"]

