# Seafile

[Seafile](https://www.seafile.com/en/home/) is a self-hosted Dropbox alternative. This configuration uses the Pro version of Seafile, which is free for up to 3 users without a license. 

## Installation

After starting the container for the first time, you should be able to access the login page, but won't be able to log in. You need to create an admin user account, and make some changes to the configuration.

```bash
# Access the container
nomad alloc exec -i -t -task seafile -job seafile /bin/bash
# Create the admin user
/opt/seafile/seafile-server-latest/reset-admin.sh
# The server name of the memcached server is hard-coded, and must be updated
sed -i 's/memcached:11211/localhost:11211/' conf/seahub_settings.py
# This is optional, but it removes about 150MB of RAM usage in the container.
sed -i '/OFFICE CONVERTER/,/^$/s/enabled.*/enabled = false/' conf/seafevents.conf
```

After doing that, restart the seafile task (this is doable from the Nomad UI or using `nomad alloc restart`). Then you can log in normally and set up the instance the way you like. Make sure to do these two things:

- Set the `SERVICE_URL` and `FILE_SERVER_URL` in the system settings.
- Delete the empty default user.

