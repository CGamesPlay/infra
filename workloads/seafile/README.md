# Seafile

[Seafile](https://www.seafile.com/en/home/) is a self-hosted Dropbox alternative. This configuration uses the Pro version of Seafile, which is free for up to 3 users without a license. 

## Installation

After starting the container for the first time, you should be able to access the login page, but won't be able to log in. You need to create an admin user account, and make some changes to the configuration.

```bash
# Access the container
kubectl exec -it deployment/seafile -- /bin/bash
# Create the admin user
/opt/seafile/seafile-server-latest/reset-admin.sh
# The server name of the memcached server is hard-coded, and must be updated
sed -i 's/memcached:11211/localhost:11211/' conf/seahub_settings.py
# I also choose to disable search. Note that ElasticSearch is not in the manifests.
sed -i '/\[INDEX FILES\]/,/\[.*\]/ s/^enabled = true/enabled = false/' conf/seafevents.conf
```

After doing that, restart the deployment using `kubectl rollout restart deployment seafile`. Then you can log in normally and set up the instance the way you like. Make sure to do these two things:

- Set the `SERVICE_URL` and `FILE_SERVER_URL` in the system settings.
- Delete the empty default user.

