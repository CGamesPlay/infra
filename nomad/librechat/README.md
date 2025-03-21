# LibreChat

LibreChat is an open-source alternative to ChatGPT that supports multiple LLM providers.

## Deployment

This service includes:
- LibreChat API
- MongoDB database

## Configuration

```
vault kv put kv/librechat/env \
  OPENAI_API_KEY=$OPENAI_API_KEY \
  ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY \
  GOOGLE_SEARCH_API_KEY=$GOOGLE_SEARCH_API_KEY \
  GOOGLE_CSE_ID=$GOOGLE_CSE_ID \
  TAVILY_API_KEY=$TAVILY_API_KEY \
  CREDS_KEY=$(openssl rand -hex 32) \
  CREDS_IV=$(openssl rand -hex 16) \
  JWT_SECRET=$(openssl rand -base64 32) \
  JWT_REFRESH_SECRET=$(openssl rand -base64 32)
```
