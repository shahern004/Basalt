# Open WebUI

## About

Open WebUI is an extensible, feature-rich, and user-friendly self-hosted WebUI designed to operate entirely offline. It supports various LLM runners, including Ollama and OpenAI-compatible APIs. For more information, be sure to check out our [Open WebUI Documentation](https://docs.openwebui.com/).

![Open WebUI Demo](./demo.gif)

## Deploy

**Docker**

Build locally __(Remember to update image tag to desired one before running this command)__:

```shell
sudo docker compose build open-webui
```

## Running Locally

### Configure environment variables

Copy a `.env.example` file to `.env`

### Run App

#### Production

The following command starts the UI in production mode:

```bash
sudo docker compose up -d
```

#### Development

```bash
sudo docker compose -f docker-compose.dev.yaml up -d
```
__Backend changes will be reflected immediately in this deployment mode but for frontend development you would need to run the following:__
```bash
# Select node version you prepared node modules for
nvm use <version>

# Build front end code
npm run build
```
__When running offline you would need to copy the corresponding node_modules folder into the project folder in order to have a successful build. This folder is then mounted to in the development deployment allowing to test recent changes__

## Configuration

When deploying the application, the following environment variables can be set (available in .env.example):

| Environment Variable              | Default value                  | Description                                                                                                                               |
| --------------------------------- | ------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------- |
| OLLAMA_BASE_URL                    | `http://localhost:11434`      | The base url for ollama backend                                                                                  |
| OPENAI_API_BASE_URL                  | ``       | The base url for the Open AI proxy server                                |
| OPENAI_API_KEY                   | ``                       | The Open AI API key.                                                                                             |
| CUSTOM_NAME                   | `The Boss`                       | Custom app name to overwrite the app for. Serves as a simple way to overwrite references to the original "Open WebUI" name key.                                                                                             |
| DEFAULT_MODELS                   | ``                       | Name of the default model to be used in conversations.                                                                                             |
| DEFAULT_USER_ROLE                   | `user`                       | Default user role when an account is created.                                                                                 |
| DEFAULT_MODELS                   | ``                       | Name of the default model to be used in conversations.                                                                                             |
| ENABLE_IMAGE_GENERATION                   | false                       | Enable image generation                                                                                             |
| AUTOMATIC1111_BASE_URL                   | `http://localhost:7860`                       | The base url for the image generation server.                                                                                             |