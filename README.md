# Description:
These scripts allow you to setup port knocking on your new server and connect to it with ease.

# Usage:
## Step 1: Connect to your server via ssh and save a fingerprint
```sh
ssh root@<your_server_ip>
```
Example:
```sh
ssh root@111.11.111.111
```

## Step 2: Run the setup script
```sh
sh ./setup_port_knocking.sh <target_ip> <target_port> <target_username> <port_open_seq>
```
<ul>
    Arguments:
    <li><code>target_ip</code>: your server IP</li>
    <li><code>target_port</code>: your desired port to connect to server</li>
    <li><code>target_username</code>: your user's name</li>
    <li><code>port_open_seq</code>: sequence of ports to open <code>target_port</code></li>
</ul>

Example:
```sh
sh ./setup_port_knocking.sh 111.11.11.111 2222 username 7000,8000,9000
```

Then you will be prompted to enter your desired user's password.

Wait till the script finishes.

Done!

## Step 3: Connect to the server with your desired port
```sh
sh ./connect_with_knock.sh <target_username> <target_ip> <target_port> <port_open_seq>
```

Example:
```sh
sh ./connect_with_knock.sh username 111.11.11.111 2222 7000,8000,9000
```

Done!
