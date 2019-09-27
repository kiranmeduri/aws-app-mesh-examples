FROM 111345817488.dkr.ecr.us-west-2.amazonaws.com/aws-appmesh-envoy:v1.11.1.1-prod

COPY envoy-wrapper-with-gateway.sh /usr/bin/envoy-wrapper-with-gateway.sh
RUN chmod +x /usr/bin/envoy-wrapper-with-gateway.sh

CMD /usr/bin/envoy-wrapper-with-gateway.sh