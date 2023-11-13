# LobeChat

[LobeChat](https://github.com/lobehub/lobe-chat) is a self-hosted frontend for LLMs.

## Installation

Set up the necessary environment variables in Vault:

```bash
vault secrets enable -version=1 kv
vault kv put kv/lobechat/env \
	OPENAI_API_KEY=$OPENAI_API_KEY \
	ACCESS_CODE=$ACCESS_CODE
```
