# Seafile Community Edition

This folder contains the infrastructure necessary to run the community edition of [Seafile](https://www.seafile.com).

After starting the initial time, create the default user. If you plan to use OAuth, make the email match the user you will use for OAuth. The password you set here will be the one used for the Seafile Client as well (SSO does not seem to be supported here).

```bash
docker exec -it seafile /opt/seafile/seafile-server-latest/reset-admin.sh
```

Now log in and delete the default user from the system administration settings (`me@example.com`). You also need to use the system settings dialog to configure the critical URLs:

- `SERVICE_URL`: `https://seafile.${BASE_DOMAIN}/`
- `FILE_SERVER_ROOT`: `https://seafile.${BASE_DOMAIN}/seafhttp`

## Configuring OAuth

Log into Keycloak and create a new client for Seafile.

- Client ID: Seafile
- Client Protocol: openid-connect
- Root URL: http://seafile.${BASE_DOMAIN}/
- Access type: confidential
- Direct access grants: disabled
- Base URL: /accounts/login

While you are here, confirm that your user has all of the proper fields set. At least Email and First Name are required.

```bash
docker exec -it seafile pip install requests_oauthlib
```

Edit `$DATA_DIR/seafile/seafile/seafile/conf/seahub_settings.py` and add the OAuth settings to it. Note that you need to manually substitute `${BASE_DOMAIN}` and `${CLIENT_SECRET}`.

```python
ENABLE_OAUTH = True
OAUTH_ENABLE_INSECURE_TRANSPORT = True
OAUTH_CLIENT_ID = 'seafile'
OAUTH_CLIENT_SECRET = '${CLIENT_SECRET}'
OAUTH_REDIRECT_URL = 'http://seafile.${BASE_DOMAIN}/oauth/callback'
OAUTH_PROVIDER_DOMAIN = 'seafile.${BASE_DOMAIN}'
OAUTH_AUTHORIZATION_URL = 'http://keycloak.${BASE_DOMAIN}/auth/realms/master/protocol/openid-connect/auth'
OAUTH_TOKEN_URL =         'http://keycloak.${BASE_DOMAIN}/auth/realms/master/protocol/openid-connect/token'
OAUTH_USER_INFO_URL =     'http://keycloak.${BASE_DOMAIN}/auth/realms/master/protocol/openid-connect/userinfo'
OAUTH_SCOPE = ['profile','email']
OAUTH_ATTRIBUTE_MAP = {
        "id": (False, "not used"),
        "name": (False, "full name"),
        "email": (True, "email"),
        }
```

```bash
./compose.sh seafile restart seafile
```

Add a link to Heimdall: http://seafile.${BASE_DOMAIN}/sso/
