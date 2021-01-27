# RabbitMQ

This is a basic deployment of RabbitMQ, probably not suitable for production use. I wanted a simple message broker that was exposed over HTTP, and this provides it.

For example, if you create a queue named "notifications", you can send a message and receive the message using these snippets:

```bash
http -v --check-status --auth guest:guest \
    http://rabbitmq.vcap.me/api/exchanges/%2F//publish \
    payload_encoding=string payload="test message" routing_key="notifications" properties:={}
http -v --check-status --auth guest:guest \
    http://rabbitmq.vcap.me/api/queues/%2F/notifications/get \
    encoding=auto count=100 ackmode=ack_requeue_false
```

Note that the HTTP API demonstrated here is not in the production code path for RabbitMQ. The documentation for both of these methods indicates that they do not provide the same level of reliability or performance that RabbitMQ is capable of.

## Installation

When the container is started for the first time, go to `rabbitmq.$BASE_DOMAIN` and log in with `guest` and `guest`. Documentation is available using the links in the management website footer once you're logged in. Use the admin screen to create a new admin user with a suitable password. Keycloak is not used for RabbitMQ since my goal is to enable scripts to access this and using a simple username/password pair is simpler for that use case.

