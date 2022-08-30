# Automated backups with Restic

This job is designed to back up a single-node cluster to a remote [Restic](https://restic.net) repository.

## Installation

The single node needs to have restic installed on it manually:

```bash
apt install restic
```

The single node also needs to have the `raw_exec` task driver enabled, which is done through the node's config in `/etc/nomad.d/client.hcl`:

```hcl
plugin "raw_exec" {
  config {
    enabled = true
  }
}
```

You need to prepare the restic repository that you will be using. I am using an S3 bucket for this, so my process looks like this. You should probably create a limited IAM user who only has access to the configured bucket; see below for a sample IAM policy to use.

```bash
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
export RESTIC_REPOSITORY=s3:s3.amazonaws.com/$S3_BUCKET_NAME
export RESTIC_PASSWORD=$(openssl rand -base64 32)
restic init
```

Store the secret in Vault:

```bash
vault secrets enable -version=1 kv
vault kv put kv/backup/repository \
	aws_access_key_id=$AWS_ACCESS_KEY_ID \
	aws_secret_access_key=$AWS_SECRET_ACCESS_KEY \
	restic_repository=$RESTIC_REPOSITORY \
	restic_password=$RESTIC_PASSWORD
```

**Important:** you should save the RESTIC_PASSWORD in the same place that you store your Vault unseal key, because you will need both of them to recover from a server failure.

### Sample IAM Policy

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "VisualEditor0",
            "Effect": "Allow",
            "Action": [
                "s3:PutObject",
                "s3:GetObject",
                "s3:ListBucket",
                "s3:DeleteObject",
                "s3:GetBucketLocation"
            ],
            "Resource": [
                "arn:aws:s3:::MY_BUCKET/*",
                "arn:aws:s3:::MY_BUCKET"
            ]
        }
    ]
}
```

