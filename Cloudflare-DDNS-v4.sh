#!/bin/bash

auth_email=""										# The email used to login 'https://dash.cloudflare.com'
auth_method=""										# Set to "global" for Global API Key or "token" for Scoped API Token 
auth_key=""											# Your API Token or Global API Key
zone_identifier=""									# Can be found in the "Overview" tab of your domain
record_name=""										# Which record you want to be synced
ttl=""												# Set the DNS TTL (seconds)
proxy=""											# Set the proxy to true or false

###########################################
## Check if we have a public IPv4
## Using -4 parameter to force curl to only use IPv4 for this connection
###########################################
ipv4_regex='([01]?[0-9]?[0-9]|2[0-4][0-9]|25[0-5])\.([01]?[0-9]?[0-9]|2[0-4][0-9]|25[0-5])\.([01]?[0-9]?[0-9]|2[0-4][0-9]|25[0-5])\.([01]?[0-9]?[0-9]|2[0-4][0-9]|25[0-5])'

ip=$(curl -s -4 https://cloudflare.com/cdn-cgi/trace | grep -E '^ip'); ret=$?
if [[ ! $ret == 0 ]]; then # In the case that Cloudflare failed to return an IPv4 address.
    # Attempt to get the IPv4 address from other websites.
    ip=$(curl -s -4 https://api.ipify.org || curl -s -4 https://ipv4.icanhazip.com)
else
    # Extract just the IPv4 address from the 'ip' line from Cloudflare.
    ip=$(echo $ip | sed -E "s/^ip=($ipv4_regex)$/\1/")
fi

# Use regex to check for proper IPv4 format.
if [[ ! $ip =~ ^$ipv4_regex$ ]]; then
    logger -s "DDNS Updater v4: Failed to find a valid IPv4 address."
    exit 2
fi

###########################################
## Check and set the proper auth header
###########################################
if [ "${auth_method}" == "global" ]; then
  auth_header="X-Auth-Key:"
else
  auth_header="Authorization: Bearer"
fi

###########################################
## Seek for the A record
###########################################

logger "DDNS Updater v4: Check Initiated"
record=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$zone_identifier/dns_records?type=A&name=$record_name" \
                      -H "X-Auth-Email: $auth_email" \
                      -H "$auth_header $auth_key" \
                      -H "Content-Type: application/json")

###########################################
## Check if the domain has an A record
###########################################
if [[ $record == *"\"count\":0"* ]]; then
  logger -s "DDNS Updater v4: Record does not exist, perhaps create one first? (${ip} for ${record_name})"
  exit 1
fi

###########################################
## Get existing IPv4 Address
###########################################
old_ip=$(echo "$record" | sed -E 's/.*"content":"(([0-9]{1,3}\.){3}[0-9]{1,3})".*/\1/')
# Compare if they're the same
if [[ $ip == $old_ip ]]; then
  logger "DDNS Updater v4: IP ($ip) for ${record_name} has not changed."
  exit 0
fi

###########################################
## Set the record identifier from result
###########################################
record_identifier=$(echo "$record" | sed -E 's/.*"id":"(\w+)".*/\1/')

###########################################
## Change the IPv4 Address @ Cloudflare using the API
###########################################
update=$(curl -s -X PATCH "https://api.cloudflare.com/client/v4/zones/$zone_identifier/dns_records/$record_identifier" \
                     -H "X-Auth-Email: $auth_email" \
                     -H "$auth_header $auth_key" \
                     -H "Content-Type: application/json" \
                     --data "{\"type\":\"A\",\"name\":\"$record_name\",\"content\":\"$ip\",\"ttl\":\"$ttl\",\"proxied\":${proxy}}")

###########################################
## Report the status
###########################################
case "$update" in
*"\"success\":false"*)
  logger -s "DDNS Updater v4: $ip $record_name DDNS failed for $record_identifier ($ip). DUMPING RESULTS:\n$update"
  exit 1;;
*)
  logger "DDNS Updater v4: $ip $record_name DDNS updated."
  exit 0;;
esac
