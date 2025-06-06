# cert-manager

[cert-manager](https://cert-manager.io/docs/) is used to issue TLS certificates for all subdomains. By default, it uses the http challenge and LetsEncrypt staging.

## Configuration

```yaml
# config.libsonnet
'cert-manager': {
	email: 'you@example.com',
	staging: false, # Required to issue real certificates
}
```

## DNS01 and Route53

You'll need to create an AWS access key with the following policy. Make sure that you replace `$HOSTED_ZONE_ID` with the actual ID from Route 53. It looks like `Z08479911R6V57QW3SS8R`.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "route53:GetChange",
      "Resource": "arn:aws:route53:::change/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "route53:ChangeResourceRecordSets",
        "route53:ListResourceRecordSets"
      ],
      "Resource": "arn:aws:route53:::hostedzone/$HOSTED_ZONE_ID",
      "Condition": {
        "ForAllValues:StringEquals": {
          "route53:ChangeResourceRecordSetsRecordTypes": ["TXT"]
        }
      }
    }
  ]
}
```

Next add the AWS access key to a secret; use `secret.template.yml` as an example. Finally, set the top-level config key to enable wildcard certificates.

```yaml
# config.libsonnet
{
  domain: 'example.com',
  wildcardCertificate: true,
  workloads: {
    'cert-manager': {
	  email: 'you@example.com',
	  staging: false,
	  hostedZoneID: "$HOSTED_ZONE_ID"
	}
  }
}
```

