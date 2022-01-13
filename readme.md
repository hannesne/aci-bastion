# Using ACI and ngrok for a docker-based bastion in a private vnet

## Overview

This repo shows how to host a publically accessible ssh server ([OpenSSH](http://www.openssh.com/)) in a Debian-based container with internal access to a vnet using [Azure Container Instances](https://azure.microsoft.com/en-us/services/container-instances/) and [ngrok](https://ngrok.com/).
The container uses ngrok to establish a publically accessible endpoint, which will tunnel any tcp traffic to port 22 on the container.
This is the port that the ssh server listens on. You will need to sign up for a free ngrok account to enable tcp forwarding.
The container has the azure cli pre-installed. By modifying the provided docker file, you can pre-install any other tools you may need.
The container can also be connected to using Visual Studio Code's [Remote SSH extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-ssh), which opens up a whole new world of being able to debug things running a private vnet.

## Building the container

Instructions are given in Powershell, but should mostly work in Bash.
Clone the repository, and navigate your terminal to the root of the repo.

Configure credentials and other variables. Replace the placeholders below. You can pick anything for the username and password, but don't share it around.
Create an account with [ngrok](https://ngrok.com/), and download your auth token from the dashboard.

```powershell
    $USER_NAME=<ssh username>
    $USER_PASSWORD=<ssh password>
    $NGROK_AUTHTOKEN=<ngrok authentication token>
    $DOCKER_REPO="hannesn"
    $DOCKER_IMAGE="$DOCKER_REPO/bastion"
    $GROUP="aci-bastion"
    $LOCATION="eastus"
    $VNET_NAME="${GROUP}-vnet"
    $ACI_SUBNET="${GROUP}-aci-subnet"
    $ACI_NAME="${GROUP}-aci"
```

Credentials are exposed to the deployed container using environment variables set in the host environment. A startup script in the image will read the environment variables and configure the relevant users and authentication pieces for that container.
This means that you can publish your container and share it between teams, as no secrets or specific connection information is stored directly in the container.

Build the docker container.

```powershell
    docker build -t bastion .
```

Optional - run the container locally and connect to it using ssh. This is a great way to test that everything is working as expected. The ngrok tunnel url will be in the docker logs, in the format "url=tcp://8.tcp.ngrok.io:17472"

```powershell
    docker run -d --rm --name bastion -e USER_NAME=$USER_NAME -e=USER_PASSWORD=$USER_PASSWORD -e NGROK_AUTHTOKEN=$NGROK_AUTHTOKEN bastion

    $DOCKER_LOGS=$(docker logs bastion)
    $MATCH_RESULT = [regex]::Match($DOCKER_LOGS,'url=tcp://(.*?):(\d*)')
    $NGROK_HOST = ${MATCH_RESULT}.Groups[1].Value
    $NGROK_PORT = ${MATCH_RESULT}.Groups[2].Value
    echo "ssh available on ${NGROK_HOST}:${NGROK_PORT}"
    
    ssh ${USER_NAME}@${NGROK_HOST} -p ${NGROK_PORT}

    docker kill bastion
```

Ngrok will output the url of the public endpoint on the stdout stream, which is reported by the container host in the docker logs.
You will need the hostname and port in this url to connect to, it is not the standard port 22. A paid ngrok account allows you more control over these values.

With a regular ngrok account, you can only have a single tcp tunnel active at any one time. This means that you can only run a single instance of the container with any given authentication token.
To run multiple instances, you will need a different authentication token (and therefore ngrok account) for each. If you forget to kill a running container, other instances will fail with a message explaining this in the container logs.

## Deploying the container

Push the container to [dockerhub](https://hub.docker.com/). You will need a dockerhub account to do so.
You can also use [Azure Container Registry](https://azure.microsoft.com/en-us/services/container-registry/) by following [these instructions](https://docs.microsoft.com/en-us/azure/container-registry/container-registry-get-started-docker-cli?tabs=azure-cli). You will need to change the value of the `DOCKER_REPO` variables if you use ACR.
Either way, you will need to first log in using `docker login` - this only needs to be done once.

```powershell
docker tag bastion $DOCKER_IMAGE
docker push $DOCKER_IMAGE
```

You will need to be logged into azure using `azure login`.
Create the resource group and networks. You can reuse existing resources, but you'll need to udpate the names in the relevant environment variables.
The `ACI_SUBNET` subnet will need to be empty it if already exists. If you use pre-existing resources, be careful that NSG's are not blocking all outbound traffic - ngrok needs to be able to establish an outbound connection to enable the tunnel.

```powershell
    az group create -g $GROUP -l $LOCATION

    az network vnet create -n $VNET_NAME -g $GROUP
    az network vnet subnet create -n $ACI_SUBNET --vnet-name $VNET_NAME --address-prefixes "10.0.0.0/24" -g $GROUP
```

Create the ACI container group.

```powershell
    az container create `
        -n $ACI_NAME `
        --image "$DOCKER_IMAGE" `
        --secure-environment-variables `
            USER_NAME=$USER_NAME `
            USER_PASSWORD=$USER_PASSWORD `
            NGROK_AUTHTOKEN=$NGROK_AUTHTOKEN `
        --vnet $VNET_NAME `
        --subnet $ACI_SUBNET `
        -g $GROUP
```

ACI allows you to do interesting things such as mounting Azure File Shares or git repos as volumes. This can be very useful if you need a durable development environment, or for doing deployments.

Connect to your container using ssh. The adress to connect to is exposed in the logs from ACI, in the format "url=tcp://8.tcp.ngrok.io:17472", and extracted using a regular expression. Use the value of the `USER_PASSWORD` variable when prompted for a password.

```powershell
    $ACI_LOGS=$(az container logs --name $ACI_NAME --resource-group $GROUP)
    $MATCH_RESULT = [regex]::Match($ACI_LOGS,'url=tcp://(.*?):(\d*)')
    $NGROK_HOST = ${MATCH_RESULT}.Groups[1].Value
    $NGROK_PORT = ${MATCH_RESULT}.Groups[2].Value
    echo "ssh available on ${NGROK_HOST}:${NGROK_PORT}"
    
    ssh ${USER_NAME}@${NGROK_HOST} -p ${NGROK_PORT}
```

Run `hostname -I` in the connected ssh session. This will report the ip adress of the current instance, which should be in the 10.0.0.x range.

You can do further testing by deploying a function app that is only accessible from within your vnet using [Private Site Access](https://docs.microsoft.com/en-us/azure/azure-functions/functions-create-private-site-access#create-an-azure-functions-app). Use `curl` from your ssh session to access the function app. The same curl command from your local machine should give you a 403 response.

You can connect to the container using Visual Studio Code's [Remote SSH extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-ssh). This will allow you to do debugging of live services in vnet constrained environments. This will not work if you used an image based on Alpine (such as the default Azure CLI image).
