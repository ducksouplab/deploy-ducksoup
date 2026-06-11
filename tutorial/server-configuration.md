# Server Configuration Tutorial for DuckSoup Deployment

**Note**: This tutorial is a living document based on real deployment scenarios. It covers setting up a new server to securely run DuckSoup and oTree-based experiments via Docker Compose and Nginx. If you follow this tutorial and find anything that can be improved, please let us know.

In this tutorial we will be setting up a server to run DuckSoup and the realted applications. To do this, we will use Docker, a containarisation application, designed to help developers build, share, and run "container" applications. This will enable you to run mutliparticipant social interaction experiments online with participants all over the world. 

We will be running these docker containers in the new server : 
- Mastok : This application handles mutliparticipant orechestration. It is great to manage otree experiments at scale, create and monitor dozens of data collection sessions in paralell.
- DuckSoup : A videonconference experimental platform which enables users to transform videoconference participant's voice and face in real time with Gstreamer algorithms.
- An Otree server : Otree is an incredible python package built to perform multiparticipant psychological experiments online. Coupled with DuckSoup, otree enables to perform social interaction experiments with several participants in parallel and in real time.
- Grafana : A service to monitor server usage, usefull when performing experiments with large amounts of participants.

If you want to learn how to code new experiments, please refer to the [Experiment template tutorials](https://github.com/ducksouplab/experiment_templates/tree/main/tutorial).

In this guide, you will learn how to:
- Set up a Debian-based server with the necessary software to run DuckSoup.
- Configure Nginx as a reverse proxy with SSL certificates so that your website is visible all over the world.
- Use a helper script called `appctl` to manage Docker images.
- Set up the application folders, user permissions, and environment variables for DuckSoup to work properly.
- Troubleshoot common Nginx, Docker, and permission issues. 

---

## Prerequisites

Before you begin, ensure you have:
- A Debian-based server (or compatible Linux system).
- SSH access to the server.
- Basic knowledge of the command line.
- Registered subdomains pointed to your server's public IP address (e.g., `ducksoup.yourdomain.edu` and `socialxp.yourdomain.edu`). 
  > **How to do this:** You (or your IT department) must log into where your domain is managed and create an **"A Record"** for each subdomain. This acts as a direct signpost linking the human-readable name to your server's exact mathematical public IP address (e.g., `130.209.87.29`). Nginx and SSL certificates rely entirely on this being correct.

---

## Step 1: Setting Up the Host OS

### 1. Install Required Software
Update your package list and install the core infrastructure:

```bash
sudo apt-get update
sudo apt-get install -y docker.io docker-compose nginx certbot

```

*(You may also want to install a firewall like `ufw` and tools to manage log files).*

### 2. (Optional) Install NVIDIA GPU Support

If you want to use an NVIDIA GPU for video encoding, verify your current drivers before updating:

```bash
# 1. See if the NVIDIA kernel module is loaded
lsmod | grep nvidia

# 2. Check which nvidia-driver package is installed
dpkg -l | grep nvidia-driver

# 3. Query the running driver via nvidia-smi
nvidia-smi

# 4. (Optional) List all NVIDIA kernel modules available
modinfo nvidia

```

If you have an NVIDIA GPU but the previous commands didn't show any correctly installed drivers, install them (ensure you choose a driver version compatible with your hardware, e.g., `460`):

```bash
# Add the NVIDIA apt repository
distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
curl -fsSL "[https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list](https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list)" | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-docker-archive-keyring.gpg] https://#g' | \
  sudo tee /etc/apt/sources.list.d/nvidia-docker.list

sudo apt-get update
sudo apt-get install -y nvidia-driver-460 nvidia-docker2
sudo systemctl restart docker

```

---

## Step 2: Configuring the Host Environment

### 1. Create a Deployment User

Create a dedicated user to run the application securely:

```bash
sudo adduser deploy
sudo usermod -aG docker deploy

```

### 2. Configure Docker Daemon

To prevent IP conflicts with your local network, restrict Docker's default IP range.

```bash
sudo nano /etc/docker/daemon.json

```

Add the following configuration:

```json
{
  "default-address-pools": [
    {"base":"172.80.0.0/16","size": 24}
  ]
}

```

Apply the changes:

```bash
sudo systemctl daemon-reload
sudo systemctl restart docker

```

---

## Step 3: Nginx & SSL Configuration (Reverse Proxy)

Because our applications run in Docker containers on different internal ports (e.g., DuckSoup on 8100, oTree on 8180), we use Nginx to catch standard web traffic and route it to the correct container securely. 

Choose **ONE** of the paths A or B below based on how your infrastructure handles SSL certificates.

### ──────────────────────────────────────────────────

### PATH A: Institution-Provided Certificates (e.g., Central IT)

### ──────────────────────────────────────────────────

*Use this path if your university IT department provides you with the `.key` and `.pem` certificate files directly. This is most often the case if you are working within a University*

**1. Secure Your Certificates**

```bash
# Create a secure folder for your certificates
sudo mkdir -p /etc/ssl/ducksoup

# Move your private key (.key) and full chain certificate (.pem) into this folder
# Restrict permissions so only the system can read the private key
sudo chmod 600 /etc/ssl/ducksoup/*.key

```

**2. Create the Nginx Configuration**

```bash
sudo nano /etc/nginx/sites-available/ducksoup.conf

```

Paste the following template. **Replace the `server_name` variables and ensure the `ssl_certificate` paths match where you saved your files in the previous step. Also change "yourdomain.com" string in line with your domain**.

```nginx
#-------------- helpers --------------------------------------------------------
map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      close;
}

upstream ducksoup   { server 127.0.0.1:8100; }
upstream experiment { server 127.0.0.1:8180; }
upstream mastok     { server 127.0.0.1:8190; }
upstream grafana    { server 127.0.0.1:3000; }

#-------------- Redirect HTTP to HTTPS -----------------------------------------
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name ducksoup.yourdomain.edu socialxp.yourdomain.edu;
    return 301 https://$host$request_uri;
}

#===============================================================================
# SERVER 1: DuckSoup
#===============================================================================
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ducksoup.yourdomain.edu;

    # MUST MATCH YOUR SAVED FILES
    ssl_certificate     /etc/ssl/ducksoup/ducksoup_chain.pem;
    ssl_certificate_key /etc/ssl/ducksoup/server.key;
    
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;

    location / { 
        proxy_pass http://ducksoup;   
        include snippets/proxy-params.conf; 
    }

    location /grafana/ { 
        proxy_pass http://grafana;    
        include snippets/proxy-params.conf; 
    }
}

#===============================================================================
# SERVER 2: SocialXP (oTree & Mastok)
#===============================================================================
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name socialxp.yourdomain.edu;

    # MUST MATCH YOUR SAVED FILES
    ssl_certificate     /etc/ssl/ducksoup/ducksoup_chain.pem;
    ssl_certificate_key /etc/ssl/ducksoup/server.key;

    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;

    location / { 
        proxy_pass http://experiment; 
        include snippets/proxy-params.conf; 
    }

    location /mastok/ { 
        proxy_pass http://mastok;     
        include snippets/proxy-params.conf; 
    }

    location = /experiment {
        return 301 $scheme://$host$uri/;
    }
    
    location /experiment/ { 
        proxy_pass [http://127.0.0.1:8180/](http://127.0.0.1:8180/); 
        include snippets/proxy-params.conf; 
        proxy_redirect default;

        proxy_set_header   SCRIPT_NAME         /experiment;
        proxy_set_header   X-Forwarded-Prefix  /experiment;
        proxy_redirect     off;
    }
}

```

**3. Enable and Restart**
If you manually typed in your certificate paths in Path A, activate your configuration:

```bash
sudo ln -s /etc/nginx/sites-available/ducksoup.conf /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl restart nginx

```

---

### ──────────────────────────────────────────────────

### PATH B: Free Certificates via Let's Encrypt (Certbot)

### ──────────────────────────────────────────────────

*Use this path if you are deploying on an independent server and not within e.g. a University. Note your DNS A-records must already point to this server.*

**1. Create the Base HTTP Configuration**
We will create a basic unencrypted routing file first, and allow Certbot to automatically upgrade it to HTTPS.

```bash
sudo nano /etc/nginx/sites-available/ducksoup.conf

```

Paste this base template (**Replace the `server_name` variables with your domains**):

```nginx
#-------------- helpers --------------------------------------------------------
map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      close;
}

upstream ducksoup   { server 127.0.0.1:8100; }
upstream experiment { server 127.0.0.1:8180; }
upstream mastok     { server 127.0.0.1:8190; }
upstream grafana    { server 127.0.0.1:3000; }

#===============================================================================
# SERVER 1: DuckSoup
#===============================================================================
server {
    listen 80;
    server_name ducksoup.yourdomain.edu;

    location / { 
        proxy_pass http://ducksoup;   
        include snippets/proxy-params.conf; 
    }

    location /grafana/ { 
        proxy_pass http://grafana;    
        include snippets/proxy-params.conf; 
    }
}

#===============================================================================
# SERVER 2: SocialXP (oTree & Mastok)
#===============================================================================
server {
    listen 80;
    server_name socialxp.yourdomain.edu;

    location / { 
        proxy_pass http://experiment; 
        include snippets/proxy-params.conf; 
    }

    location /mastok/ { 
        proxy_pass http://mastok;     
        include snippets/proxy-params.conf; 
    }

    location = /experiment {
        return 301 $scheme://$host$uri/;
    }
    
    location /experiment/ { 
        proxy_pass [http://127.0.0.1:8180/](http://127.0.0.1:8180/); 
        include snippets/proxy-params.conf; 
        proxy_redirect default;

        proxy_set_header   SCRIPT_NAME         /experiment;
        proxy_set_header   X-Forwarded-Prefix  /experiment;
        proxy_redirect     off;
    }
}

```

**2. Enable the Base Configuration**
Certbot needs the file to be active before it can modify it:

```bash
sudo ln -s /etc/nginx/sites-available/ducksoup.conf /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo systemctl reload nginx

```

**3. Run Certbot**
Let Certbot automatically install the certificates and upgrade your Nginx file:

```bash
sudo certbot --nginx -d ducksoup.yourdomain.edu -d socialxp.yourdomain.edu

```

* Follow the prompts.
* When asked, tell Certbot to **redirect all HTTP traffic to HTTPS**.
* Enable automatic 90-day renewals: `sudo systemctl enable certbot.timer`

*(Path B is complete)*


---

## Step 4: Configuring the Application

Switch to your `deploy` user to handle the application files.

```bash
su deploy
cd /home/deploy

```

### 1. Clone the Repository & Setup Appctl

```bash
git clone https://github.com/ducksouplab/deploy-ducksoup.git
cd deploy-ducksoup

chmod u+x app/appctl
echo 'export PATH="$HOME/deploy-ducksoup/app:$PATH"' >> ~/.bashrc
source ~/.bashrc

```

### 2. Configure Docker Compose Overrides

The production hosts **do not build** the experiment image locally. Instead, they run the pre-built image published on Docker Hub.

Copy the override file that pins the correct image:

```bash
cd app
cp docker-compose.override-example.build-experiment.yml docker-compose.override.yml

```

### 3. Configure Environment Variables

Copy the example environment file and edit it:

```bash
cp env.example .env
nano .env

```

Update the variables, particularly ensuring the UID/GID matches the permissions we will set in the next step:

* `DOCKER_UNAME=deploy`
* `DOCKER_UID=1003`
* `DOCKER_GID=1003`


The `.env` file is the master configuration file for your entire deployment. It tells the Docker containers how to talk to each other, what passwords to use, and where your server is located on the internet.

Open the file in the nano editor:

```bash
nano .env

```
You must update the following sections in the new .env carefully. Do not change the variables that are not listed below unless you know exactly what you are doing.

#### 1: Domain Names and Origins

This section controls where your services live and who is allowed to connect to them. **Replace all instances of `yourdomain.com` with your actual subdomains.**

* **`DUCKSOUP_ALLOWED_WS_ORIGINS`**: This is a security feature. It tells DuckSoup which websites are allowed to embed its video streams.
* *Change to:* `https://ducksoup.yourdomain.edu,https://socialxp.yourdomain.edu` (Use a comma, no spaces).


* **`OTREE_DUCKSOUP_URL`**: Where oTree looks for the DuckSoup video engine.
* *Change to:* `https://ducksoup.yourdomain.edu`


* **`OTREE_BASE_URL`**: The main URL where your participants will take the experiment.
* *Change to:* `https://socialxp.yourdomain.edu`


* **`MASTOK_ORIGIN`**: Where the Mastok lobby service lives.
* *Change to:* `https://socialxp.yourdomain.edu`


* **`MASTOK_OTREE_PUBLIC_URL`**: The public URL for oTree.
* *Change to:* `https://socialxp.yourdomain.edu`


* **`DUCKSOUP_TURN_ADDRESS`**: The domain handling complex video routing.
* *Change to:* `ducksoup.yourdomain.edu` (Note: No `https://` prefix here).


* **`GF_PATH`**: Where your Grafana monitoring dashboard lives.
* *Change to:* `https://ducksoup.yourdomain.edu/grafana`



#### 2: User IDs and Permissions

This is the most common cause of deployment failures. Docker containers need to write files (like logs and databases) to your host machine. They must use the correct user permissions to do so.

* **`DOCKER_UNAME`**: The username you created in Step 2.
* *Change to:* `deploy`


* **`DOCKER_UID` and `DOCKER_GID**`: These are the numerical IDs of the `deploy` user.
* **How to find them:** Save your `.env` file (`Ctrl+O`, `Enter`), exit nano (`Ctrl+X`), and run the command `id deploy`. You will see `uid=100X(deploy) gid=100X(deploy)`.
* *Change to:* The exact numbers output by that command (e.g., `1001`, `1002`, `1003`).



#### 3: The Public IP Address

DuckSoup handles real-time WebRTC video, which requires knowing the exact physical address of the server on the internet so it doesn't get blocked by strict firewalls.

* **`DUCKSOUP_PUBLIC_IP`**: The mathematical IP address of your server.
* **How to find it:** If you don't know it, run `curl ifconfig.me` in your server's terminal.
* *Change to:* Your IP address (e.g., `130.209.87.29`).


#### 4: Passwords and Security Keys
You **must** change every field that says `change_me` or has a default password. These secure your databases, admin panels, and API connections. You may use the same password for Mastok, grafana, otree and DuckSoup.

* **`DUCKSOUP_TEST_PASSWORD`**: Password to access the `https://ducksoup.../test/mirror/` page.
* **`POSTGRES_PASSWORD`**: The master password for your database. Make this a long, complex string (e.g., `sUp3rS3cr3tDBp4ss`).
* *Important:* Once you change this, you must also update the two database connection strings below it to match:
* `OTREE_DATABASE_URL="postgres://experiment:YOUR_NEW_PASSWORD@db/experiment"`
* `MASTOK_DATABASE_URL="postgres://experiment:YOUR_NEW_PASSWORD@db/mastok"`

* **`OTREE_ADMIN_PASSWORD`**: Password to log into the oTree admin dashboard.
* **`OTREE_REST_KEY`** and **`MASTOK_OTREE_API_KEY`**: These two fields are how Mastok securely talks to oTree in the background. **They must be identical.** Make up a random string of letters and numbers (e.g., `MyS3cr3tAP1K3y`) and paste it into both fields.
* **`MASTOK_PASSWORD`**: Password for the Mastok admin panel.
* **`GF_PASSWORD`**: Password to log into Grafana.


#### 5: Hardware Acceleration (Optional)

If you followed the optional step to install NVIDIA GPU drivers in Step 1, you can enable hardware acceleration for video encoding. This drastically improves performance.

* **`DUCKSOUP_NVCODEC`**: Change to `true` (if you have an NVIDIA GPU) or `false` (if you are running on standard CPU hardware).
* **`DUCKSOUP_NVCUDA`**: Change to `true` (if GPU) or `false` (if CPU).
* **`OTREE_DUCKSOUP_REQUEST_GPU`**: Change to `true` (if GPU) or `false` (if CPU).

Once you have updated all of these fields, save the file (`Ctrl+O`, `Enter`) and exit nano (`Ctrl+X`).

### 4. Create Folders and Set Permissions

Docker containers need persistent host folders. These **must** match the UID/GID defined in your `.env` file (usually `1003`) and specific container requirements (like `472` for Grafana).

Run these commands sequentially:

```bash
# Create directories
mkdir -p config/ducksoup config/prometheus
mkdir -p data/db data/ducksoup data/grafana/plugins data/prometheus
mkdir -p log/ducksoup plugins

# Apply broad ownership to deploy user
sudo chown -R deploy:deploy config data log plugins

# DuckSoup & General Permissions (UID 1003)
sudo chown -R 1003:1003 data/db data/ducksoup log/ducksoup log
sudo chmod -R u+rwX log/ducksoup

# Grafana Permissions (UID 472)
sudo chown -R 472:472 data/grafana/plugins
sudo chmod -R u+rwX data/grafana

# Prometheus Permissions (UID 1003)
sudo chown 1003:1003 config/prometheus/prometheus.yml
sudo chmod 644 config/prometheus/prometheus.yml
sudo chown -R 1003:1003 data/prometheus
sudo chmod -R u+rwX data/prometheus

```

---

## Step 5: Running the Application

### 1. Pull the Images

Use the `appctl` script to pull the latest Docker images:

```bash
appctl pull ducksoup
appctl pull db
appctl pull experiment
appctl pull mastok
appctl pull grafana

```

### 2. Build and Start Services

Start the main profiles, and ensure the database and experiment containers are running:

```bash
docker compose --profile ducksoup up -d --build
docker compose --profile social up -d --build

# Ensure specific backing services are up
docker compose up -d db
docker compose up -d experiment

```

### 3. Test the Deployment

Navigate to your instance in a browser to verify the service is running (replace the domain with your actual URL):

```bash
https://ducksoup.yourdomain.com/test/mirror/
https://socialxp.yourdomain.com/demo
https://socialxp.psy.gla.ac.uk/mastok/
```

Also check docker status
```bash
docker ps
```

Are all the services showing up and running? If not, check the troubleshooting documentation below. If everything is up and running, you may now start coding your own experiments, please refer to the [Experiment template tutorials](https://github.com/ducksouplab/experiment_templates/tree/main/tutorial), which explains how to do this.

---

## Step 6: Troubleshooting

### 1. Check which images are used

To verify you are using the correct image tags (`prod` for DuckSoup, `latest` for others):

```bash
docker compose images

```

### 2. Nvidia Error (`could not select device driver "nvidia"`)

If you see an error stating `could not select device driver "nvidia" with capabilities: [[gpu]]`, it means the NVIDIA container runtime isn't installed properly. Revisit Step 1 to install `nvidia-docker2` and restart the Docker daemon.

### 3. Service Keeps Restarting (Permission Denied)

If `docker ps` shows a container continuously restarting, check its logs:

```bash
docker compose logs ducksoup

```

If you see `/bin/bash: line 1: log/ducksoup.stderr.log: Permission denied`, ensure the log folder is owned by the UID used by Docker.

```bash
grep -E '^DOCKER_(UID|GID)=' .env
# Then apply the chown command from Step 4 using that ID.

```

### 4. See why a service is crashing

To isolate a crashing service (e.g., `app-experiment-1`, `app-db-1`, `app-mastok-1`) without it looping:

```bash
docker update --restart=no app-experiment-1 \
  && docker start app-experiment-1 \
  && sleep 2 \
  && docker logs app-experiment-1

```

### 5. Browser Shows "Not Secure" / Nginx Duplicate Upstream Error

* **Nginx Error:** If Nginx fails to boot complaining about `duplicate upstream`, check `/etc/nginx/sites-enabled/` and delete any old `.bak` files.
* **Browser Error:** If the server is correctly configured but Chrome shows "Not Secure", the browser has cached a previous warning. Open an **Incognito Window** to verify. To fix the main browser, click the warning, click "Turn on warnings", and hard-refresh (`Cmd+Shift+R`).

---

## Editing YAML Files

The YAML files, such as `docker-compose.yml`, can be edited to customize the services and configurations according to your needs. For example, you might want to change the ports, environment variables, or add new services.

Example of Editing `docker-compose.yml`:
To change the port for the DuckSoup service, find the section in `docker-compose.yml` that looks like this:

```yaml
ports:
  - "8100:8100"

```

You can change it to:

```yaml
ports:
  - "8200:8100"

```

This change would make the underlying container accessible on port 8200 instead of 8100 (Remember to update your Nginx configuration upstream block to match!). Review the YAML files and adjust them based on your specific requirements.

```