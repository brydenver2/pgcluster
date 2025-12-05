FROM debian:12
MAINTAINER ptim007@yahoo.com
ENV DEBIAN_FRONTEND=noninteractive

# Install Node.js
RUN apt-get update && apt-get upgrade -y && \
    apt-get install -y curl xz-utils && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

ADD https://nodejs.org/dist/v12.16.2/node-v12.16.2-linux-x64.tar.xz /opt
RUN cd /opt && tar xf node-v12.16.2-linux-x64.tar.xz && rm node-v12.16.2-linux-x64.tar.xz
ENV PATH=$PATH:/opt/node-v12.16.2-linux-x64/bin

