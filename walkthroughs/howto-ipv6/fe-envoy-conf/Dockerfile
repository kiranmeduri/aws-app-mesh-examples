FROM amazonlinux:2

RUN yum -y update

RUN yum -y install \
        awscli \
        jq

COPY envoy /etc/envoy
RUN chmod +x /etc/envoy/wrapper.sh

VOLUME ["/etc/envoy"]

CMD ["/etc/envoy/wrapper.sh"]
