FROM amazonlinux

RUN yum install -y curl

COPY sleep-forever.sh /usr/bin/
RUN chmod +x /usr/bin/sleep-forever.sh

COPY curler.sh /usr/bin/
RUN chmod +x /usr/bin/curler.sh

ENTRYPOINT [ "/usr/bin/curler.sh"]