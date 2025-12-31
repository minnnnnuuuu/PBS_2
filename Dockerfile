FROM ollama/ollama
EXPOSE 11434
ENTRYPOINT ["/bin/ollama", "serve"]
