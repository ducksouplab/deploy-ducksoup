# Server Configuration Tutorial for DuckSoup Deployment

**BEWARE**: This tutorial hasn't been properly tested, so it might not work perfectly yet. We will update it as we go depending on time and user feedback. If you follow this tutorial and find anything that can be corrected, please let us know.

This tutorial will help you set up a new server to run DuckSoup and different Otree-based experiments. If you want to learn how to use DuckSoup, configure it, or code new experiments, please refer to the [Experiment template tutorials](https://github.com/ducksouplab/experiment_templates/tree/main/tutorial).

DuckSoup uses Docker and Docker Compose to manage its services, which makes it easier to install and run.

In this guide, you will learn how to:

- Set up a Debian-based server with the necessary software.
- Configure the server, including user permissions and security settings.
- Set up Docker and Nginx to manage the DuckSoup application.
- Use a helper script called `appctl` to make pulling Docker images and managing services easier.
- Create the necessary folders and environment settings for the application.

By the end of this tutorial, you will have a working DuckSoup setup ready for your online experiments. Let's get started!

## Prerequisites

Before you begin, make sure you have:

- A Debian-based server (or another compatible Linux system).
- SSH access to the server (you should be able to log in remotely).
- Basic knowledge of how to use the command line.

## Step 1: Setting Up the Host

1. **Install Required Software**

   On your server, install the following software:

   ```bash
   sudo apt-get update
   sudo apt-get install -y \
       docker.io \
       docker-compose \
       nginx \
       certbot
   ```

   You may also want to install a firewall (like `ufw`) and tools to manage log files.

2. **Optional: Install NVIDIA GPU Support**

   If you want to use a GPU for video encoding, follow these steps:

   - Install the NVIDIA driver:
     ```bash
     sudo apt-get install nvidia-driver-460
     ```

   - Install NVIDIA Docker support:
     ```bash
     sudo apt-get install nvidia-container-runtime
     ```

   - Restart Docker:
     ```bash
     sudo systemctl restart docker
     ```

## Step 2: Configuring the Host

1. **Create a User for Deployment**

   Create a user that will run the application:

   ```bash
   sudo adduser deploy
   ```

2. **Set Up Security**

   Configure security settings for the `deploy` user. This may include setting up SSH keys and configuring firewall rules.

3. **Configure Docker**

   If needed, change Docker's default network settings by editing `/etc/docker/daemon.json`:

   ```json
   {
     "default-address-pools": [
       {"base":"172.80.0.0/16","size": 24}
     ]
   }
   ```

   Then restart Docker:

   ```bash
   sudo systemctl daemon-reload
   sudo systemctl restart docker
   ```

4. **Set Up Nginx and Let's Encrypt**

   Create a new Nginx server block:

   ```bash
   sudo nano /etc/nginx/sites-available/ducksoup
   ```

   Edit the file to match your domain and services. Then enable the server block:

   ```bash
   sudo ln -s /etc/nginx/sites-available/ducksoup /etc/nginx/sites-enabled/
   sudo systemctl reload nginx
   ```

   Use Certbot to enable HTTPS:

   ```bash
   sudo certbot --nginx -d your-domain.com
   ```

## Step 3: Configuring the Application

1. **Clone the Repository**

   Switch to the `deploy` user and clone the DuckSoup repository:

   ```bash
   su deploy
   git clone https://github.com/ducksouplab/deploy-ducksoup.git
   cd deploy-ducksoup
   ```

2. **Set Up the Appctl Script**

   Make the `appctl` script executable and add it to your PATH:

   ```bash
   chmod u+x app/appctl
   export PATH="$PATH:`pwd`/app"
   ```

3. **Pull Docker Images Using Appctl**

   Use the `appctl` script to pull the latest Docker images:

   ```bash
   appctl pull ducksoup
   appctl pull db
   appctl pull otree
   appctl pull mastok
   appctl pull grafana
   ```

4. **Create Required Folders**

   Create the necessary folders for configuration, data, logs, and plugins:

   ```bash
   mkdir -p app/config/ducksoup app/data/db app/data/ducksoup app/log/ducksoup app/plugins
   ```

   Set the correct permissions:

   ```bash
   chown -R deploy:deploy app/config app/data app/log app/plugins
   chmod 770 -R app/data app/log
   ```

5. **Create Environment Variables**

   Copy the example environment file and edit it:

   ```bash
   cp app/env.example app/.env
   nano app/.env
   ```

   Update the variables as needed, especially `DOCKER_UNAME`, `DOCKER_UID`, and `DOCKER_GID`. Here are some key variables to consider:

   - `DOCKER_UNAME`: The username for the Docker container.
   - `DOCKER_UID`: The user ID for the Docker container.
   - `DOCKER_GID`: The group ID for the Docker container.

   **Example of Editing Environment Variables**:
   - To set the username to `deploy`, you would change:
     ```bash
     DOCKER_UNAME=deploy
     ```
   - To set the user ID to `1001`, you would change:
     ```bash
     DOCKER_UID=1001
     ```

## Step 4: Running the Application

1. **Build and Start Services**

   Use Docker Compose to build and start the services:

   ```bash
   cd app
   docker compose up -d --build
   ```

2. **Access the Application**

   You can now access the DuckSoup application at `http://your-domain.com`.

## Conclusion

You have successfully set up a new server using the DuckSoup deploy repository. For more customization and usage details, refer to the main README file.

## Editing YAML Files

The YAML files, such as `docker-compose.yml`, can be edited to customize the services and configurations according to your needs. For example, you might want to change the ports, environment variables, or add new services. 

**Example of Editing `docker-compose.yml`**:
- To change the port for the DuckSoup service, find the section in `docker-compose.yml` that looks like this:
  ```yaml
  ports:
    - "8100:8100"
  ```
- You can change it to:
  ```yaml
  ports:
    - "8200:8100"
  ```
This change would make DuckSoup accessible on port 8200 instead of 8100.

Make sure to review the YAML files and adjust them based on your specific requirements.