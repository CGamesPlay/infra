# WIP - Monica

A procedure like the following will get you set up with Monica. This worked on
2020-01-15, and using monica latest. At the time, v2.16.0 was the latest on
docker hub.

```bash
./compose monica up -d
./compose.sh monica exec db mysql -p
CREATE DATABASE monica;
./compose.sh monica exec app php artisan setup:production
```
