FROM debian:jessie

RUN echo 'Acquire::Check-Valid-Until false;' > /etc/apt/apt.conf.d/10no-check-valid-until

RUN apt-get update \
    && apt-get install -y git build-essential fakeroot devscripts debhelper wget \
    && echo "deb http://archive.debian.org/debian jessie-backports main" >> /etc/apt/sources.list \
    && echo "deb http://apt.postgresql.org/pub/repos/apt/ jessie-pgdg main" >> /etc/apt/sources.list \
    && wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add - \
    && apt-get update \
    && apt-get -t jessie-backports install -y autopkgtest \
    && apt-get install -y postgresql-server-dev-all \
    && dpkg -l | grep -Po "postgresql-server-dev-([\d\.]{2,3})" | sed "s/server-dev-//" | xargs apt-get install -y

ADD run.sh /usr/local/

CMD ["/usr/local/run.sh"]

