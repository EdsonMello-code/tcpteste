# Estágio de build
FROM dart:stable AS builder

WORKDIR /app
COPY bin/server.dart bin/

# Compilar para um executável nativo
RUN dart compile exe bin/server.dart -o server

# Estágio final com imagem mínima
FROM ubuntu:latest

WORKDIR /app
COPY --from=builder /app/server ./
EXPOSE 3000/udp

CMD ["./server"]