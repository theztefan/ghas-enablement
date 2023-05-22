#!/bin/bash
# This bash script will enable the features specified on all organizations 
# As input you need to provide
# argument 1: enterprise name
# argument 2: features you want to enable
# argument 3: the GHES server URL


# Define the colors
RED=$(tput setaf 1)
CYAN=$(tput setaf 6)
YELLOW=$(tput setaf 3)

# Check if the .env file exists
# If it doesn't exist, copy the .env.example file to .env
if [ ! -f .env ]; then
    cp .env.sample .env
    echo -e "${YELLOW}Info: .env file was created as it was not found in the directory.${RESET}"
fi

## Check if .bin/repos.json exists
## If it doesn't exist, create it
if [ ! -f ./bin/repos.json ]; then
    touch ./bin/repos.json
fi

## Set tmp dir
mkdir -p /tmp/ghas-enablement
tempDir="/tmp/ghas-enablement"
sed -i '' -e "s|TEMP_DIR=.*|TEMP_DIR=$tempDir|g" .env


# Get the enterprise name from the first argument
enterpriseName=$1

# Get the PAT token from ./bin/applications-secrets.json 
patToken=$(cat ./bin/application-secrets.json | jq -c '.[] | select(.user == "admin")' | jq -c '.PAT' | sed 's/"//g' | sed 's/,//g' | sed 's/ //g')

# Get the GHES server URL from the third argument
ghesServerUrl=$3

# Get all the organizations for the enterprise
# Set the enterprise name, GHES server, PAT token just for this call in .env
sed -i '' -e "s/GITHUB_ENTERPRISE=.*/GITHUB_ENTERPRISE=$enterpriseName/g" .env
sed -i '' -e "s/GITHUB_API_TOKEN=.*/GITHUB_API_TOKEN=$patToken/g" .env
sed -i '' -e "s|GHES_SERVER_BASE_URL=.*|GHES_SERVER_BASE_URL=$ghesServerUrl|g" .env
sed -i '' -e "s/GHES=.*/GHES=true/g" .env
yarn run getOrgs
mv ./bin/organizations.json ./bin/organizations.work.json

# Remove the token from .env as we will be using applications to get the tokens for the enablement
sed -i '' -e "s/GITHUB_API_TOKEN=.*/GITHUB_API_TOKEN=/g" .env


# Get the features to enable from the second argument
features=$2

# Set the features in .env
sed -i '' -e "s/ENABLE_ON=.*/ENABLE_ON=$features/g" .env

# Read the contents of the application-secrets.json file
applicationSecrets=$(cat ./bin/application-secrets.json)

# For each org in the organizations.work.json file, enable the features
# In each iteration find the application secrets for the org from application-secrets.sjon and set the values in .env

for org in $(cat ./bin/organizations.work.json | jq -c '.[] | select(.completed != true)' | jq -c '.login' | sed 's/"//g' | sed 's/,//g' | sed 's/ //g'); do
    echo "Enabling features for $org"
    # set the org name in .env
    sed -i '' -e "s/GITHUB_ORG=.*/GITHUB_ORG=$org/g" .env

    # get the application secrets for the org and set them in .env
    app_id=$(echo "${applicationSecrets}" | jq -c '.[] | select(.login == "'$org'")' | jq -c '.APP_ID' | sed 's/"//g' | sed 's/,//g' | sed 's/ //g')
    #app_private_key=$(echo "${applicationSecrets}" | jq -c '.[] | select(.login == "'$org'")' | jq -c '.APP_PRIVATE_KEY' | sed 's/"//g' | sed 's/,//g' | sed 's/ //g')
    app_private_key=$(echo "${applicationSecrets}" | jq -r '.[] | select(.login == "'$org'") | .APP_PRIVATE_KEY' | sed 's/\\n/\n/g')
    app_installation_id=$(echo "${applicationSecrets}" | jq -c '.[] | select(.login == "'$org'")' | jq -c '.APP_INSTALLATION_ID' | sed 's/"//g' | sed 's/,//g' | sed 's/ //g')
    app_client_id=$(echo "${applicationSecrets}" | jq -c '.[] | select(.login == "'$org'")' | jq -c '.APP_CLIENT_ID' | sed 's/"//g' | sed 's/,//g' | sed 's/ //g')
    app_client_secret=$(echo "${applicationSecrets}" | jq -c '.[] | select(.login == "'$org'")' | jq -c '.APP_CLIENT_SECRET' | sed 's/"//g' | sed 's/,//g' | sed 's/ //g')

    sed -i '' -e "s/APP_ID=.*/APP_ID=$app_id/g" .env
    sed -i '' -e "s:APP_PRIVATE_KEY=.*:APP_PRIVATE_KEY=\"${app_private_key//$'\n'/\\\\n}\":g" .env
    sed -i '' -e "s/APP_INSTALLATION_ID=.*/APP_INSTALLATION_ID=$app_installation_id/g" .env
    sed -i '' -e "s/APP_CLIENT_ID=.*/APP_CLIENT_ID=$app_client_id/g" .env
    sed -i '' -e "s/APP_CLIENT_SECRET=.*/APP_CLIENT_SECRET=$app_client_secret/g" .env

    # if the values for the org are not found in application-secrets.json, set the flag {completed: false} in organizations.work.json
    if [ -z "$app_id" ] || [ -z "$app_private_key" ] || [ -z "$app_installation_id" ] || [ -z "$app_client_id" ] || [ -z "$app_client_secret" ]; then
        echo -e "${RED}Missing application secrets to generate token. Failed to enable features for $org${RESET}"
        jq --arg orgName "$org" 'map(if .login == $orgName then . + {completed: false} else . end)' ./bin/organizations.work.json > ./bin/organizations.work.json.tmp && mv ./bin/organizations.work.json.tmp ./bin/organizations.work.json
        continue
    fi


    yarn run enableOrg
    if [ $? -eq 0 ]; then
        jq --arg orgName "$org" 'map(if .login == $orgName then . + {completed: true} else . end)' ./bin/organizations.work.json > ./bin/organizations.work.json.tmp && mv ./bin/organizations.work.json.tmp ./bin/organizations.work.json
    else
        # set the flag {completed: false} in organizations.work.json
        echo -e "${RED}Failed to enable features for $org${RESET}"
        jq --arg orgName "$org" 'map(if .login == $orgName then . + {completed: false} else . end)' ./bin/organizations.work.json > ./bin/organizations.work.json.tmp && mv ./bin/organizations.work.json.tmp ./bin/organizations.work.json

    fi
done