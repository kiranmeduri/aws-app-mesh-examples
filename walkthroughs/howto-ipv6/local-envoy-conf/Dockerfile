FROM amazonlinux:2

RUN yum -y update

COPY envoy /etc/envoy
RUN chmod +x /etc/envoy/wrapper.sh

VOLUME ["/etc/envoy"]

CMD ["/etc/envoy/wrapper.sh"]
