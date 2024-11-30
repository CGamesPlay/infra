# Open WebUI

[Open WebUI](https://openwebui.com) is a self-hosted frontend for LLMs.

## Installation

Set up the necessary environment variables in Vault:

```bash
vault secrets enable -version=1 kv
vault kv put kv/open-webui/env \
	OPENAI_API_KEY=$OPENAI_API_KEY \
	ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY \
    SERPLY_API_KEY=$SERPLY_API_KEY \
    WEBUI_SECRET_KEY=$(openssl rand 32 | base32)
```
