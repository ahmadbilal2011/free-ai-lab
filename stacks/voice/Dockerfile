# Lesson 11: Jarvis's voice. Piper text-to-speech + ffmpeg (for Telegram's OGG/Opus format).
FROM python:3.12-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends ffmpeg \
 && rm -rf /var/lib/apt/lists/* \
 && pip install --no-cache-dir piper-tts \
 && useradd --uid 1000 --create-home jarvis

WORKDIR /app
COPY server.py .
USER jarvis
EXPOSE 5000
CMD ["python", "-u", "server.py"]
