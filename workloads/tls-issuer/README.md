# tls-issuer

A small, controller-free replacement for cert-manager. Instead of running the
cert-manager controller, cainjector, webhook and six CRDs, a **weekly CronJob**
runs [`lego`](https://go-acme.github.io/lego/) with the ACME **DNS-01** challenge
(Route53) to mint the certificates Traefik serves, and writes each into the
namespaces that consume it. A one-shot bootstrap Job of the same spec seeds the
secrets on first install.

The script is idempotent: any certificate whose serving secret still has more
than `renewDays` (30) of validity is skipped. It does not own the secrets
(no ownerReferences), so removing this workload never deletes a serving cert.

## Configuration

```jsonnet
// env/<env>/config.libsonnet
'tls-issuer': {
  email: 'you@example.com',
  staging: false,          // false -> LetsEncrypt production
  certificates: [
    {
      secretName: 'tls-' + config.domain,
      domains: [config.domain, '*.' + config.domain],
      hostedZoneID: 'Z...',
      namespaces: ['admin', 'default'],
    },
  ],
}
```

`selfSigned: true` skips ACME/Route53 entirely and emits self-signed certs
(handy for dev environments).

## Route53 credentials (SopsSecret)

DNS-01 needs an AWS access key in the `aws-access-key` secret (keys
`AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`) in the `tls-issuer` namespace,
delivered by the sops-secrets-operator. See `secret.template.yml`. Its IAM user
must be allowed to write TXT records in **every** hosted zone listed above:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    { "Effect": "Allow", "Action": "route53:GetChange", "Resource": "arn:aws:route53:::change/*" },
    {
      "Effect": "Allow",
      "Action": ["route53:ChangeResourceRecordSets", "route53:ListResourceRecordSets"],
      "Resource": [
        "arn:aws:route53:::hostedzone/$CGAMESPLAY_ZONE_ID",
        "arn:aws:route53:::hostedzone/$CHESS2ONLINE_ZONE_ID"
      ],
      "Condition": { "ForAllValues:StringEquals": { "route53:ChangeResourceRecordSetsRecordTypes": ["TXT"] } }
    }
  ]
}
```

## Bootstrapping

```
kubectl -n tls-issuer create job tls-issuer-bootstrap --from=cronjob/tls-issuer
kubectl -n tls-issuer logs -f job/tls-issuer-bootstrap
```
