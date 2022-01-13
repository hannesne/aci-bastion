FROM debian:stable-slim

RUN apt-get update
RUN apt-get install openssh-server curl --yes

RUN curl -sL https://aka.ms/InstallAzureCLIDeb | bash

RUN mkdir /run/sshd
RUN echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config

RUN curl https://bin.equinox.io/c/4VmDzA7iaHb/ngrok-stable-linux-386.tgz | tar -xzC /usr/sbin

COPY ./startup.sh .

ENTRYPOINT [ "sh", "-c", "./startup.sh" ]
