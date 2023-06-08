#!/bin/bash
# Shell script that uses gh cli to enable only specific GHAS feature to one org 
# and uses the same ./bin/application-secrets.json file to get GitHub App ID and Private Key
# 
# Input: 
#   argument 1: org name
#   argument 2: features you want to enable
#   argument 3: the GHES server URL


orgToEnable=$1
features=$(echo $2 | tr "," "\n")
automatic=false
# check if automatic is in features list then set it to true and remove it from the list
if [[ $features == *"automatic"* ]]; then
    automatic=true
    features=$(echo $features | sed 's/automatic//g')
fi
ghesServerUrl=$3


# Get the GitHub App ID and Private Key from ./bin/application-secrets.json for the org
app_id=$(cat ./bin/application-secrets.json | jq -c '.[] | select(.login == "'$orgToEnable'")' | jq -c '.APP_ID' | sed 's/"//g' | sed 's/,//g' | sed 's/ //g')
app_private_key=$(cat ./bin/application-secrets.json | jq -r '.[] | select(.login == "'$orgToEnable'") | .APP_PRIVATE_KEY')
app_priv_key_base64=$(echo "$app_private_key" | base64)


# generate the token and authenticate to the GHES server
echo " -> Generating token using the App and authenticating"
token=$(gh token generate -b $app_priv_key_base64 --app_id=$app_id --hostname=$ghesServerUrl --duration=10 | jq -r '.token')
gh auth login --with-token $token


# translate the features to enable to the API call
# if the feature is not supported, it will be ignored
for feature in $features
do
    echo " -> Enabling $feature for $orgToEnable"
    case $feature in
    pushprotection)
        security_product="secret_scanning_push_protection"
        if [ "$automatic" = true ] ; then
            feature_automatic="secret_scanning_push_protection_enabled_for_new_repositories"
        fi
        ;;
    secretscanning)
        security_product="secret_scanning"
        if [ "$automatic" = true ] ; then
            feature_automatic="secret_scanning_enabled_for_new_repositories"
        fi
        ;;
    dependabot)
        security_product="dependabot_alerts"
        if [ "$automatic" = true ] ; then
            feature_automatic="dependabot_alerts_enabled_for_new_repositories"
        fi
        ;;
    dependabotupdates)
        security_product="dependabot_security_updates"
        if [ "$automatic" = true ] ; then
            feature_automatic="dependabot_security_updates_enabled_for_new_repositories"
        fi
        ;;
    advancedsecurity)
        security_product="advanced_security"
        if [ "$automatic" = true ] ; then
            feature_automatic="advanced_security_enabled_for_new_repositories"
        fi
        ;;
    codescanning)
        security_product="code_scanning_default_setup"
        ;;
    *)
        echo "Unsupported feature: $feature"
        continue
        ;;
    esac

    # enable the security product for the org
    gh api \
    --silent \
    --method POST \
    -H "Accept: application/vnd.github+json" \
    --hostname $ghesServerUrl \
    /orgs/$orgToEnable/$security_product/enable_all

    # if automatic is true, enable 
    if [ "$automatic" = true ] ; then
        echo "      -> Enabling $feature_automatic for new repos on $orgToEnable"
        gh api \
        --silent \
        --method PATCH \
        -H "Accept: application/vnd.github+json" \
        --hostname $ghesServerUrl \
        /orgs/$orgToEnable \
        -f $feature_automatic=true
    fi
done

echo " -> Done"
