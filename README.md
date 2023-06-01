# deploy-ducksoup

## Aim

This project provides documentation, configuration samples and tools to automate the deployment of an online experiment that relies on [DuckSoup](https://github.com/ducksouplab/ducksoup) for its videoconferencing part.

The main components of the stack are Linux, nginx and Docker (including a published image of DuckSoup).

We'll use the following terms below:

- *host*: the server that runs and exposes the app
- *service*: an independent Docker container (for instance DuckSoup or postgres) run on the host by Docker Compose
- *profile*: a group of dependent services which are jointly needed to provide a given utility (for instance the `monitoring` profile relies on the `grafana` and `prometheus` services, but the `ducksoup` profile only relies on the `ducksoup` service)
- *app*: the online experiment, an end-user application made of one or more profiles

As a by-product, a minimal oTree webapp is shipped in `examples/experiment` to complete the app. But more generally, the intent of this project is to provide enough information about DuckSoup and Docker so that you may enhance or replace parts/services to best fit your needs (using oTree, or not).

## Alternatives

Running the different services (oTree, the database, DuckSoup...) that make the overall application is managed by Docker Compose. Though this project heavily relies on Docker and Docker Compose, it's fine to [build DuckSoup](https://github.com/ducksouplab/ducksoup#build-from-source) from source and to prefer a different deployment method than the one described below.

Moreover, this project illustrates a contained approach by running all the services on the same host with a unique `docker-compose.yml` definition file. Relying on Docker or not, it's also fine to prefer an architecture where DuckSoup is run on its own host (possibly shipped with a GPU to help with video encoding) whereas one or more experiments use the DuckSoup instance as-a-service from other hosts/origins (in that case the origins have to be declared/granted by setting the `DUCKSOUP_ALLOWED_WS_ORIGINS` environment variable of DuckSoup, see more [here](#environment-variables)).

## Overview

The process of installing and running DuckSoup can be broken down as:

- [provisioning](#provisioning) the host: install software to deploy, run and manage DuckSoup on a server (or developer machine)
- [host configuration](#host-configuration): create needed (Linux) users and configuration software installed during the previous step
- [app configuration](#app-configuration): clone this project and a few binaries (additional GStreamer plugins to enhance DuckSoup processing options), set environment variables and edit DuckSoup configuration files
- [deployment](#deployment): update and run the app whenever a new version needs to be deployed
- [usage](#usage): how to use the app

This documentation showcases the deployment of an app made of three parts/profiles:

- [DuckSoup](https://github.com/ducksouplab/ducksoup), a videoconferencing tool for online social experiments
- a minimal experiment based on [oTree](https://otree.readthedocs.io/en/latest/) that uses DuckSoup (and a service called *mastok* that manages users before arrival in the experiment)
- a server monitoring tool based on Grafana and Prometheus

Please note that DuckSoup has no dependency on oTree: DuckSoup is called client-side by the experiment and thus has no prerequesites regarding the technologies involved to develop the experiment server-side. This example experiment is only provided to illustrate the deployment of a full app. 

## Provisioning

### Installation

These instructions apply to a Debian-based server, but can be adapted to other distributions.

Install the following dependencies on the host:

- [Docker](https://docs.docker.com/engine/install/ubuntu/)
- [Docker Compose V2](https://docs.docker.com/compose/cli-command/#install-on-linux)
- [nginx](https://docs.nginx.com/nginx/admin-guide/installing-nginx/installing-nginx-open-source/) to bind server blocks to services/apps managed by docker compose, and to handle SSL
- [certbot](https://certbot.eff.org/lets-encrypt/) if needed for SSL certificates
- optional (not documented): a firewall to control exposed ports (ufw for instance), a backup service, logrotate to rotate logs generated by DuckSoup and GStreamer

The app is installed and run by Docker Compose (see below).

### Optional: installation for NVIDIA GPU

*Skip this paragraph if you don't use a NVIDIA GPU for video encoding*

If you plan to use a GPU from a Docker container you'll need to follow these instructions:

1. NVIDIA driver: first check if it is already installed (try `nvidia-smi`), if not search for available versions (`apt-cache search nvidia-driver`) and install (for instance with `apt-get install nvidia-driver-460`)

2. NVIDIA and Docker: this [description](https://github.com/NVIDIA/nvidia-docker/issues/1268#issuecomment-632692949) explains installing `nvidia-container-runtime` is sufficient to have Docker containers benefit from NVIDIA GPUs. To do so, update your host repository configuration following [these instructions](https://nvidia.github.io/nvidia-container-runtime/) and `apt-get install nvidia-container-runtime`

3. Restart Docker (`systemctl restart docker`)

4. Check it worked following [this tutorial](https://docs.docker.com/compose/gpu-support/), trying to run `examples/docker-compose.nvidia-smi.yml` or try directly:

```
docker run -it --rm --gpus all ubuntu nvidia-smi
```

And check GPUs are listed.

## Host configuration

1. User

Create a `deploy` user that will run the app.

2. Security

Choose a ssh login policy and security settings (for instance using fail2ban) for the `deploy` user.

Ports need to be opened for SSH connections, nginx (80, 443) and UDP ephemeral ports. You may manage this through firewall settings (not documented).

3. Docker

You may change docker default network configuration if you don't want its default subnet to conflict with others (172.20.*). If so copy, paste and edit the contents of `examples/docker/daemon.json` to `/etc/docker/daemon.json` and then restart docker:

```
sudo systemctl daemon-reload
sudo systemctl restart docker
```

4. Nginx and Let's Encrypt

Declare a new nginx server block as `/etc/nginx/sites-available/ducksoup` from the `examples/nginx/ducksoup-host.com` file:

- edit `server_name` to match with your domain name

- the `upstream` servers declare services running on the host (matching their ports with the ones defined in `docker-compose.yml`)

- the `location` directives bind path prefixes to corresponding services (for instance binds `/otree` to the oTree application) and enable/configure a few options (for instance WebSockets)

- about the proxy timeout settings: by default WebSockets are closed after a default timeout of 1 minute if no message was exchanged during this period (resulting in DuckSoup user sessions to be terminated).

Enable this server block and run certbot to enable https (a DuckSoup requirement):

```
sudo rm /etc/nginx/sites-enabled/default
sudo ln -s /etc/nginx/sites-available/ducksoup-host.com /etc/nginx/sites-enabled/
sudo systemctl reload nginx
# run certbot
sudo certbot --nginx -d ducksoup-host.com
# test
sudo certbot renew --dry-run
```

Check modifications in `/etc/nginx/sites-available/ducksoup-host.com`, it should look like `examples/nginx/ducksoup-host.com.certbot`.

_Alternatively for local/development purposes only, you may:_

- edit your `/etc/hosts` file to declare a local domain name

- create locally-trusted certificates (for instance with [mkcert](https://github.com/FiloSottile/mkcert)) for this local domain name

- edit `/etc/nginx/sites-available/ducksoup` to use these certificates (check `examples/nginx/ducksoup-host.com.certbot` to see how)

And finally restart nginx:

```
sudo systemctl reload nginx
```


5. Monitoring and firewall

If you are using the `monitoring` profile, one of its services (`prometheus`) needs to access the host (since it regularly calls `node_exporter` which in turn needs to be run on the host network). If you use a firewall, networking from containers to host may be blocked and thus monitoring won't work (`prometheus` won't be able to call `node_exporter` on the host port 9100).

Here is an example to relax the firewall (ufw) to allow traffic coming from a given subnet (see configuration declared in `examples/docker/daemon.json`) where `prometheus` is run, towards port 9100 on the host:

```
sudo ufw allow from 172.80.0.1/16 to any port 9100
```

6. Rotating logs

You may check the `examples/logrotate/ducksoup` configuration file and adapt it to your needs before creating in the host folder `/etc/logrotate.d/`

In particular you may have to change the target location of logs to be rotated (`/home/deploy/deploy-ducksoup/app/log/ducksoup/*.log` in the example) depending on where the log volume is mounted on the host.

Then try a dry-run with:

```
sudo logrotate /etc/logrotate.conf --debug
```

## App configuration

This project comes with an `examples` folder to share a few example files, but when it comes to configuring and deploying the app, all commands are meant to be executed in the main `app` folder.

Switch to the `deploy` user, clone this repository and change directory:

```
su deploy
git clone https://github.com/ducksouplab/deploy-ducksoup.git
cd deploy-ducksoup
```

### Introducing docker-compose.yml

Since deployment and running is managed by Docker Compose, most of the configuration is done in `docker-compose.yml`. From a broad perspective this file:

- declares services and groups them in profiles, enabling to start/stop them individually or by profile
- for each service, it defines:

    - how to instantiate the service (from a prebuilt Docker image or following build instructions in a Dockerfile)
    - the port this service is running on (being publicy exposed or not depends on the nginx configuration, except for this famous [bug](https://github.com/docker/for-linux/issues/690))
    - how some folders on the host are mounted as volumes in the service/container
    - what environment variables are propagated from the host to the services (and renaming a few); some are required for the app to work (see [Environment variables](#environment-variables))

### app/ folder layout

The `app` folder contains the following files:

- a base `docker-compose.yml` that declares and configures services; you may edit this file or prefer using an override (see next bullet) to fit your needs
- `docker-compose.override-example.yml` can be used as an example to create a `docker-compose.override.yml` (to override existing services or even declare new ones, without editing `docker-compose.yml`)
- `env.example` can be used as an example to create a `.env` file that will be automatically loaded by Docker Compose to define environment variables (made available to `docker compose` commands, and also forwarded to containers depending the `environment:` section of each service)
- `appctl` is a helper script that shortens a few frequent Docker Compose commands

Then, by convention (of this project), `app` subfolders are meant to be mounted as Docker volumes:

- `config` contains configuration files
- `data` (needs to be writable by the `deploy` user) contains data created by the app that needs to be persisted between restarts
- `log` (needs to be writable by the `deploy` user) contains logs produced by services
- `plugins` (only for DuckSoup service) is used to enhance DuckSoup with additional GStreamer plugins (see how [here](#optional-gstreamer-plugins))

When cloning this repository the `config/prometheus` folder is created (and contains a prepared configuration file), but `config/ducksoup`, `plugins` and `data` needs to be created and owned by `deploy:deploy`:

```
cd app
mkdir -p config config/ducksoup data/db data/ducksoup data/grafana data/prometheus log/ducksoup plugins
chown -R deploy:deploy config data log plugins
chmod 770 -R data log
```

Old?: the bound `data/db` volume is chmoded as 700 due to https://github.com/docker-library/postgres/blob/master/docker-entrypoint.sh#L39

### Changing volume host folders

The previous layout (having folders under `app` being used as volume sources) provides with a simple working example. You may want to change this setup (check the [documentation](https://docs.docker.com/storage/volumes/) for more information) and use other locations, for instance under host-mounted hard drives. If you do, prefer overriding the default setup in `docker-compose.override.yml`.

### Enable experiment build

Create the `docker-compose.override.yml` file by copying `docker-compose.override-example.yml`: it specifies how to build the image needed for a default experiment service (the build option has not been defined in `docker-compose.yml`).

An alternative would be to define an `image:` property (in `docker-compose.override.yml`) to pull a published image.

### Environment variables

A `.env` file is **needed** to provide the different services with appropriate configuration. Create it (by copying `env.example`) and then edit it:

```
cp env.example .env
nano .env
```

You should at least:
1. define `DOCKER_UNAME`, `DOCKER_UID` and `DOCKER_GID`: they are used to define the user that launches the different services. If you follow this documentation setup, `DOCKER_UNAME` is `deploy`, `DOCKER_UID` is the output of `id deploy -u` and `DOCKER_GID` is the output of `id deploy -g`. If you prefer another user, it should own folders mounted as volumes to allow the containers to write to them (check [app/ folder layout](#app-folder-layout) and in particular the `chown` command)
2. change secrets

(regarding 1., please note it could be possible to define different users for different services by modifying the `user:` section of each service in `docker-compose.yml` or `docker-compose.override.yml`)

You may also change other variables, like ports (depending on your nginx configuration) or service settings. Indeed, when runnning the app (see below, through `docker compose` or `appctl`) the `.env` file is automatically loaded.

Here are the environment variables you may edit, grouped by service:

- `ducksoup` service (only relevant variables are described here, please refer to the [Ducksoup documentation](https://github.com/ducksouplab/ducksoup#environment-variables) for an exhaustive list):  
    - `DUCKSOUP_PORT`: port listened by DuckSoup (nginx proxies to this port)
    - `DUCKSOUP_WEB_PREFIX`, DuckSoup web server and signaling prefix:
        - leave empty if DuckSoup is available at `https://ducksoup-host`
        - `DUCKSOUP_WEB_PREFIX=/path` if  DuckSoup is available at `https://ducksoup-host/path` (the nginx configuration would then proxy DuckSoup in a `location /path {...}` block)
    - `DUCKSOUP_PUBLIC_IP` if set, will be used to add a Host candidate during signaling (not necessary if ICE servers are used)
    - `DUCKSOUP_ALLOWED_WS_ORIGINS`: origins trusted by DuckSoup (you need to add DuckSoup itself, for instance `https://ducksoup-host`, if you want to use test pages like https://ducksoup-host/test/mirror/, or other origins if experiments are served from other domains)
    - `DUCKSOUP_TEST_LOGIN`: basic auth login for DuckSoup test pages
    - `DUCKSOUP_TEST_PASSWORD`: basic auth password for DuckSoup test pages
    - `DUCKSOUP_NVCODEC`: use NVIDIA hardware for H264 encoding and decoding (only if GPU available on host)
    - `DUCKSOUP_NVCUDA`: use NVIDIA hardware for video *conversion* (only if NVIDIA GPU available on host)
    - `DUCKSOUP_GENERATE_TWCC=true` (default to false) enables RTCP TWCC reports generated by DuckSoup and sent to browser
    `DUCKSOUP_GCC=true` (default to false, meaning bandwith estimation is done relying on RTCP Receiver Reports) enables GCC bandwidth estimation
    - `DUCKSOUP_GST_TRACKING=true` (default to false) enabled GStreamer log processing (you are most likely not interested in that option)
    - `DUCKSOUP_LOG_STDOUT=true` (defaults to false, except when `DUCKSOUP_MODE=DEV`) to print logs to Stdout:
        - if `DUCKSOUP_LOG_FILE` is also set, logs are written to both
        - if neither are set, logs are written to Stderr 
    - `DUCKSOUP_LOG_FILE` declares a file to write logs to (fails silently if file can't be opened) (file path from container viewpoint)
    - `DUCKSOUP_LOG_LEVEL` (defaults to 2) selects log level display (see next section)
    - `DUCKSOUP_FORCE_OVERLAY` displays a time overlay in videos (recorded)
    - `DUCKSOUP_ICE_SERVERS=false` (defaults to `stun:stun.l.google.com:19302`) declares comma separated allowed STUN servers to be used to find ICE candidates (or false to disable STUN)
    - `GST_DEBUG` controls GStreamer debug output format as explained [here](https://gstreamer.freedesktop.org/documentation/tutorials/basic/debugging-tools.html?gi-language=c)
    - `PION_LOG_TRACE` (unset by default) logs pion debug messages (see [more](https://github.com/pion/webrtc/wiki/Debugging-WebRTC))
    - `DUCKSOUP_CONTAINER_STDERR_FILE` (not of interest to DuckSoup itself, but has an effect on its container's `CMD`) writes Stderr to the specified file
- `postgres` service:
    - `POSTGRES_PASSWORD` PostgreSQL password also known by the experiment service in `OTREE_DATABASE_URL`
- `otree` service:
    - `OTREE_PORT` oTree experiment running port as defined in nginx host proxy
    - `OTREE_DATABASE_URL` PostgreSQL connection URL
    - `OTREE_ADMIN_PASSWORD` password of the oTree admin web interface
    - `OTREE_DUCKSOUP_URL` DuckSoup root URL, for instance `https://ducksoup-host/` (with trailing slash)
    - these variables define DuckSoup interaction configuration as requested by oTree for all its experiments: `OTREE_DUCKSOUP_REQUEST_GPU` (defaults to false), `OTREE_DUCKSOUP_FRAMERATE` (deffault to 30), `OTREE_DUCKSOUP_WIDTH` (defaults to 800), `OTREE_DUCKSOUP_HEIGHT` (defaults to 600), `OTREE_DUCKSOUP_FORMAT` (defaults to H264, VP8 being the only other option)
- `mastok` service:
    - `MASTOK_PORT` to set the port Mastok listens to
    - `MASTOK_ORIGIN` to set what origin is trusted for WebSocket communication. If Mastok is running on port 8190 on localhost, but is served (thanks to a proxy) and reachable at https://mymastok.com, the valid `MASTOK_ORIGIN` value is `https://mymastok.com`
    - `MASTOK_WEB_PREFIX` if Mastok is served under a prefix path
    - `MASTOK_LOGIN` and `MASTOK_PASSWORD` to define login/password for HTTP basic authentication
    - `MASTOK_DATABASE_URL` to connect to the database 
    - `MASTOK_OTREE_PUBLIC_URL` (like `http://host.com/otree`) to reach oTree public pages
    - `MASTOK_OTREE_API_URL` (like `http://localhost:8180`) to reach oTree REST API
    - please note having two `MASTOK_OTREE_*_URL` may be useful if Mastok connects to the REST API in a different way than the clients (participants), but they should point to the same running oTree instance
    - `MASTOK_OTREE_API_KEY` to authenticate to oTree API
- `grafana` service:
    - `GF_PORT` grafana running port as defined in nginx host proxy
    - `GF_PATH` grafana path prefix as defined in nginx host (set to `/grafana` if entry point is `https://ducksoup-host/grafana`)
    - `GF_PASSWORD` grafana admin password to access web interface

*Caution*: `GF_PASSWORD` needs to be set before launching monitoring with `docker compose` or `appctl`. Indeed it is used as an initial value, and then stored in grafana mounted volume. If not set, the default grafana `password` will be used, and later use of `GF_PASSWORD` will be ignored until the mounted volume is persisted.

### Docker Compose commands

Docker Compose is used to run and manage (for instance update and automatically restart) the app. The app is broken down as `profiles` in `docker-compose.yml`:

- the `ducksoup` profile defines DuckSoup
- the `experiment` profile defines 3 services: `mastok` a service that routes users to `otree`, an example web app that uses DuckSoup (client-side) and relies on a `db`, a PostgreSQL database
- the `monitoring` profile defines a monitoring utility that relies on Grafana and Prometheus, to display information about the server state
- the `nvidia` profile extends the monitoring utility with GPU data exporter

You can run profiles independently from each other: you may for instance run only DuckSoup and the monitoring service if the experiment is hosted on another server.

Let's see a few available Docker and Docker Compose commands:

```
# nota bene: commands below are to be executed by the deploy user in the app/ folder
# and the .env file should specify this user as stated above

# retrieve the latest Docker images (used to instantiate services)
docker compose pull <service_name>

# run all profiles
docker compose up -d --build

# run a given profile
docker compose --profile ducksoup up -d --build

# clean/prune Docker images
docker image prune -f
```

### appctl commands

The `appctl` script is a helper script that shortens `docker compose` commands. To enable it:

```
chmod u+x appctl
export PATH="$PATH:`pwd`"
```

Usage by profile:

```
# nota bene: commands below are to be executed by the deploy user in the app/ folder
# and the .env file should specify this user as stated above

# (re)build and start services with given profile
appctl up ducksoup
appctl up monitoring
appctl up experiment

# if you want to enable nvidia metrics in monitoring
appctl up nvidia

# stop profiles
appctl stop <profile_name>

# reloading is enough (as opposed to `up`) if...
# ...only configuration files have changed, like .env or files in the config folder
appctl reload <profile_name>
```

Usage by service:

```
# pull latest ducksoup image (from docker hub)
appctl pull <service_name>

# enter a running container (to inspect/debug) by service name
appctl sh <service_name>
```

One special feature, only for `ducksoup`: when the service is launched the first time, the `config/ducksoup` folder of the host is populated with `/app/config` from the container, thanks to a Docker "named volume". It enables editing config files (for instance the minimal video bitrate for reencoded tracks, in `config/ducksoup/sfu.yml`) and reloading `ducksoup` with this new configuration:

```
nano config/ducksoup/gst.yml
appctl reload ducksoup
```

One caveat of this approach is that when a new image of DuckSoup is pulled (with `appctl pull ducksoup`) and the `ducksoup` service is rebuild and restarted (with `appctl up ducksoup`) the `config/ducksoup` already exists and won't be modified even if the new image contained modifications. That's why you have the choice between two deployment methods:

Method #1 (keep current `config/ducksoup` contents on the host and mount them in the `ducksoup` service):

```
appctl pull ducksoup
appctl up ducksoup
```

Method #2 (reset `config/ducksoup` contents with the latest DuckSoup image contents):

```
appctl pull ducksoup
# answer 'y' to delete `config\ducksoup` contents
appctl reset-config ducksoup
appctl up ducksoup
```

(one may finally save changes before `reset-config` and decide how to merge files)

### Optional: enabling NVIDIA GPU for DuckSoup

Ensure you've followed [Optional: installation for NVIDIA GPU](#optional-installation-for-nvidia-gpu), then two actions are needed:

- enable the GPU capability in Docker context: copy the contents of `examples/docker-compose.override-gpu-example.yml` in `app/docker-compose.override.yml` (to be created if not already)
- start DuckSoup with `DUCKSOUP_NVCODEC=true` in the `.env` file (see [Environment variables](#environment-variables))

### Optional: GStreamer plugins

Put any additional GStreamer plugins (or dynamic libraries, compiled for the DuckSoup debian target) in the `plugins` host folder, to have them available to DuckSoup.

Indeed this folder is mounted as `/app/plugins` in the container, which is listed in the image environment variables `GST_PLUGIN_PATH` and `LD_LIBRARY_PATH`.

## Deployment

### Release new versions

Some services are based on prebuilt/published Docker images (like `ducksouplab/ducksoup:latest` or `postgres:13`) and can only get latest developments when images are updated.

The experiment example image is built locally from the `examples/otree/Dockerfile` each time you `appctl up experiment` (but it won't be rebuilt by `appctl reload experiment`).

It is also possible to build an image by specifying the git repository and branch of a project (check `examples/docker-compose.ds-from-source.yml` to see how). In that case, push first to the aforementioned branch and repository, before rebuilding the image (which is done by `appctl up`). For private git repository, check the appropriate documentation (on github or gitlab for instance) about how to authenticate the `deploy` user to this service, typically by adding and using a SSH key when pulling (the pull being triggered silently by Docker Compose).

### Sum-up: deploy new versions

Once a new version of the targeted service has been published (be it a Docker image or a project with a Dockerfile), here is how to update and run the service:

```
ssh deploy@<server>
cd <path to app/>

# pull latest DuckSoup image and start service
appctl pull ducksoup
# resetting config is optional, see above
appctl reset-config ducksoup
appctl up ducksoup
```

## Usage

For each service listed below, two example links are given:

- if run on your developer machine, refer to the port declared in the `.env` file, for instance http://localhost:8180/ for otree
- if run on a server accessible at `ducksoup-host.com` and behind a nginx `location` as described [previously](#host-configuration), the link would be https://ducksoup-host.com/otree

### DuckSoup

Please refer to [DuckSoup documentation](https://github.com/ducksouplab/ducksoup).

A mirror test page is available at:

- developer machine: http://localhost:8100/test/mirror/
- server: https://ducksoup-host.com/test/mirror/

When asked to authenticate (HTTP basic auth), use the credentials defined in `.env`: `DUCKSOUP_TEST_LOGIN` and `DUCKSOUP_TEST_PASSWORD`.

### Mastok

Code to be open soon.

The demo is available at:

- developer machine: http://localhost:8190/
- server: https://ducksoup-host.com/mastok/

### Experiment

Please refer to [oTree documentation](https://otree.readthedocs.io/en/latest/index.html).

The demo is available at:

- developer machine: http://localhost:8180/
- server: https://ducksoup-host.com/otree/

Authenticate with the login `admin` and the password defined as `OTREE_ADMIN_PASSWORD` in `.env`, then:

- click `mirror` under `Demo`
- click the available singe-use link (it's possible to create new links with `New` in the tab bar)
- otree an app made of three steps: an introductory page that collects your name, a page embedding DuckSoup with a pitch audio effect that redirects automatically after 20 seconds to an ending page displaying your name

Gotcha regarding database migration:

The column `_created` on the table `otree_session` should be of type integer (and not timestamp without a timezone), if it happens, one solution could be to `otree resetdb` (but there will be data loss). Leaving a timestamp type for `_created` will prevent mastok from creating otree sessions through its API. This type seems to be dependent on oTree version, if not 5.10.3, this should be checked.

### Grafana

Please refer to [Grafana documentation](https://grafana.com/docs/).

Grafana is available at:

- developer machine: http://localhost:3000/
- server: https://ducksoup-host.com/grafana/

Once up and running, Grafana needs to be configured to collect and display data:

- under the `https://ducksoup-host.com/grafana/datasources` page, add prometheus as a data source. Since prometheus is running within a container, you need to use the service name as the host in the `HTTP>URL` field: if prometheus is running on port 9090, enter `http://prometheus:9090` and click `Save & Test`
- under the https://ducksoup-host.com/grafana/dashboards page, click `Import` and add the following ids in the field `Import via grafana.com`: 1860 (then click `Load` and choose `Prometheus` as the data source) and 12239 (then click `Load`)

For more information check [Node Exporter Full](https://grafana.com/grafana/dashboards/1860) and [NVIDIA DCGM Exporter Dashboard](https://grafana.com/grafana/dashboards/12239) documentation.

## Additional information

### Log files

Logs generated by DuckSoup (including errors, info... depending on log options set in environment variables, see above) are stored according to `DUCKSOUP_LOG_FILE`.

If a GStreamer crash happens, it won't be caught by DuckSoup but will be saved in `DUCKSOUP_CONTAINER_STDERR_FILE`. The format of this file is simply:

1. log datetime on a new line when DuckSoup starts
2. log whatever is printed to Stderr inside the container, including a possible crash

It means the datetime does not refer to the crash, but to the last time DuckSoup started.

### Live logs and debugging

List containers:

```
docker ps
```

Display latest/live logs:

```
docker logs <container_id>
# follow in real time
docker logs <container_id> -f
# show tail
docker logs <container_id> --tail N
```

Connect to a container:
```
appctl sh <service_name>
docker exec -it <container_id> sh
```

Create a special image to debug network issue (if any) between containers:

```
# from project root folder
docker build -f examples/docker/Dockerfile.inspect -t inspect:latest . 
docker run --rm -it --add-host=host:host-gateway inspect:latest sh
docker run --rm -it --network=host inspect:latest sh
```

### Services particularities

`dcgm` needs to be run as root and not restarted automatically (`docker-compose.yml` setting) in case there is no GPU or the GPU is not compatible with dcgm NVIDIA image.