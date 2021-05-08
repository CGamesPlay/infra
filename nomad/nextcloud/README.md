# NextCloud

I very briefly evaluated using NextCloud, but ended up opting against it in favor of Seafile. This code remains here in case I ever reconsider.

**Why?** Nextcloud seems like a bloated security nightmare. It seems to want to keep all of its application code inside of the persistent volume, and keep its data directory in a subdirectory of that. Additionally, the default install comes with a ton of unnecessary features. The security features it does have are irrelevant to a setup behind a load balancer, but cannot be disabled.