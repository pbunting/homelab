# Home Lab

The Home Lab runs on MacOs. MacOs hosts several key services that the Home Lab is built upon.

The key services on MacOs are:
* Python
* Docker (or equivalent),
* BuildKite,
* Ollama,
* Open Telemetry observability stack,
* Virtual machines (provided by VMan).

BuildKite and OTel may be run on Docker.

The Virtual Machines will host a Kubernetes cluster.

To support the image repository for the kubernetes cluster being the Docker container, ensure the MacOS host has its hostname set to image-repo.local (Settings->General->Sharing->Local Hostname). 

## Install Notes

### BuildKite

```
brew install buildkite
```

Make sure the BUILDKITE_AGENT_TOKEN environment variable is set.

### Python

```
brew install pyenv
mkdir ~/.homelab
pyenv install 3.15
pyenv local 3.15
rm -rf .venv
python -m venv .venv
```

### VMan

Assumes Python already installed

```
cd ~/Code/vman
uv build

source ~/.homelab/.venv/bin/activate
pip install dist/vman-0.1.0-py3-none-any.whl
```

## Ollama

```
brew install ollama
```

## Running things

### Checking Ollama

```
ollama serve
curl http://localhost:11434/v1/chat/completions \
    -H "Content-Type: application/json" \
    -d '{
        "model": "llama2",
        "messages": [
            {
                "role": "system",
                "content": "You are a helpful assistant."
            },
            {
                "role": "user",
                "content": "Hello!"
            }
        ]
    }'
```

### Checking Homelab core logs

```
docker compose logs -f --tail=100
docker compose logs -f registry --since 30m
```

### Application Logs

Go to http://localhost:3000 to see Grafana
