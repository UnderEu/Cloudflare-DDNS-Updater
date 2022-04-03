#!/bin/bash

auth_email=""										# The email used to login 'https://dash.cloudflare.com'
auth_method=""										# Set to "global" for Global API Key or "token" for Scoped API Token 
auth_key=""											# Your API Token or Global API Key
zone_identifier=""									# Can be found in the "Overview" tab of your domain
record_name=""										# Which record you want to be synced
ttl=""												# Set the DNS TTL (seconds)
proxy=""											# Set the proxy to true or false

###########################################
## Check if we have a public IPv6
## Using -6 parameter to force curl to only use IPv6 for this connection
###########################################
ipv6_regex="(([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:)|fe80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|::(ffff(:0{1,4}){0,1}:){0,1}((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])|([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9]))"

ip=$(curl -s -6 https://cloudflare.com/cdn-cgi/trace | grep -E '^ip'); ret=$?
if [[ ! $ret == 0 ]]; then # In the case that Cloudflare failed to return an IPv6 address.
    # Attempt to get the IPv6 address from other websites.
    ip=$(curl -s -6 https://api64.ipify.org || curl -s -6 https://ipv6.icanhazip.com)
else
    # Extract just the IPv6 address from the 'ip' line from Cloudflare.
    ip=$(echo $ip | sed -E "s/^ip=($ipv6_regex)$/\1/")
fi

# Use regex to check for proper IPv6 format.
if [[ ! $ip =~ ^$ipv6_regex$ ]]; then
    logger -s "DDNS Updater v6: Failed to find a valid IPv6 address."
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
## Seek for the AAAA record
###########################################

logger "DDNS Updater v6: Check Initiated"
record=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$zone_identifier/dns_records?type=AAAA&name=$record_name" \
                      -H "X-Auth-Email: $auth_email" \
                      -H "$auth_header $auth_key" \
                      -H "Content-Type: application/json")

###########################################
## Check if the domain has an AAAA record
###########################################
if [[ $record == *"\"count\":0"* ]]; then
  logger -s "DDNS Updater v6: Record does not exist, perhaps create one first? (${ip} for ${record_name})"
  exit 1
fi

###########################################
## Get existing IPv6 Address
###########################################
old_ip=$(echo "$record" | sed -E 's/.*"content":"'${ipv6_regex}'".*/\1/')
# Compare if they're the same
if [[ $ip == $old_ip ]]; then
  logger "DDNS Updater v6: IP ($ip) for ${record_name} has not changed."
  exit 0
fi

###########################################
## Set the record identifier from result
###########################################
record_identifier=$(echo "$record" | sed -E 's/.*"id":"(\w+)".*/\1/')

###########################################
## Change the IPv6 Address @ Cloudflare using the API
###########################################
update=$(curl -s -X PATCH "https://api.cloudflare.com/client/v4/zones/$zone_identifier/dns_records/$record_identifier" \
                     -H "X-Auth-Email: $auth_email" \
                     -H "$auth_header $auth_key" \
                     -H "Content-Type: application/json" \
             		 --data "{\"type\":\"AAAA\",\"name\":\"$record_name\",\"content\":\"$ip\",\"ttl\":\"$ttl\",\"proxied\":${proxy}}")

###########################################
## Report the status
###########################################
case "$update" in
*"\"success\":false"*)
  logger -s "DDNS Updater v6: $ip $record_name DDNS failed for $record_identifier ($ip). DUMPING RESULTS:\n$update"
  exit 1;;
*)
  logger "DDNS Updater v6: $ip $record_name DDNS updated."
  exit 0;;
esac
