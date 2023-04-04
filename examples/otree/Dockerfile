FROM debian:bullseye-slim

RUN apt-get upgrade -y

RUN apt-get update && apt-get install -y python3-pip git
RUN apt-get update && apt-get install -y libpq-dev

WORKDIR /app

COPY . .

RUN pip3 install -r requirements.txt

CMD otree prodserver