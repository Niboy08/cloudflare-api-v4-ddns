#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

# Automatically update your CloudFlare DNS record to the IP, Dynamic DNS
# Can retrieve cloudflare Domain id and list zone's, because, lazy

# Place at:
# curl https://raw.githubusercontent.com/yulewang/cloudflare-api-v4-ddns/master/cf-v4-ddns.sh > /usr/local/bin/cf-ddns.sh && chmod +x /usr/local/bin/cf-ddns.sh
# run `crontab -e` and add next line:
# */1 * * * * /usr/local/bin/cf-ddns.sh >/dev/null 2>&1
# or you need log:
# */1 * * * * /usr/local/bin/cf-ddns.sh >> /var/log/cf-ddns.log 2>&1

# Usage:
# cf-ddns.sh -k cloudflare-api-token \
#            -h host.example.com \     # fqdn of the record you want to update
#            -z example.com \          # will show you all zones if forgot, but you need this
#            -t A|AAAA                 # specify ipv4/ipv6, default: ipv4

# Optional flags:
#            -f false|true \           # force dns update, disregard local stored ip

# default config

# API token, see https://www.cloudflare.com/a/account/my-account,
# incorrect api-token results in E_UNAUTH error
CFKEY=（令牌-开启代理权限）

# Zone name, eg: example.com
CFZONE_NAME=（一级域名如：baidu.com）

# Hostname to update, eg: homeserver.example.com
CFRECORD_NAME=（二级域名头如：www）

# Record type, A(IPv4)|AAAA(IPv6), default IPv4
CFRECORD_TYPE=A

# Cloudflare TTL for record, between 120 and 86400 seconds
CFTTL=120

# Ignore local file, update ip anyway
FORCE=false

WANIPSITE="http://ipv4.icanhazip.com"

# Site to retrieve WAN ip, other examples are: bot.whatismyipaddress.com, https://api.ipify.org/ ...
if [ "$CFRECORD_TYPE" = "A" ]; then
  :
elif [ "$CFRECORD_TYPE" = "AAAA" ]; then
  WANIPSITE="http://ipv6.icanhazip.com"
else
  echo "$CFRECORD_TYPE specified is invalid, CFRECORD_TYPE can only be A(for IPv4)|AAAA(for IPv6)"
  exit 2
fi

# get parameter
while getopts k:h:z:t:f: opts; do
  case ${opts} in
    k) CFKEY=${OPTARG} ;;
    h) CFRECORD_NAME=${OPTARG} ;;
    z) CFZONE_NAME=${OPTARG} ;;
    t) CFRECORD_TYPE=${OPTARG} ;;
    f) FORCE=${OPTARG} ;;
  esac
done

# If required settings are missing just exit
if [ "$CFKEY" = "" ]; then
  echo "Missing API token, get at: https://www.cloudflare.com/a/account/my-account"
  echo "and save in ${0} or using the -k flag"
  exit 2
fi
if [ "$CFRECORD_NAME" = "" ]; then
  echo "Missing hostname, what host do you want to update?"
  echo "save in ${0} or using the -h flag"
  exit 2
fi

# If the hostname is not a FQDN
if [ "$CFRECORD_NAME" != "$CFZONE_NAME" ] && ! [ -z "${CFRECORD_NAME##*$CFZONE_NAME}" ]; then
  CFRECORD_NAME="$CFRECORD_NAME.$CFZONE_NAME"
  echo " => Hostname is not a FQDN, assuming $CFRECORD_NAME"
fi

# Get current and old WAN ip
WAN_IP=$(curl -s ${WANIPSITE})
WAN_IP_FILE=$HOME/.cf-wan_ip_$CFRECORD_NAME.txt
if [ -f $WAN_IP_FILE ]; then
  OLD_WAN_IP=$(cat $WAN_IP_FILE)
else
  echo "No file, need IP"
  OLD_WAN_IP=""
fi

# If WAN IP is unchanged and not -f flag, exit here
if [ "$WAN_IP" = "$OLD_WAN_IP" ] && [ "$FORCE" = false ]; then
  echo "WAN IP Unchanged, to update anyway use flag -f true"
else
  # Get zone_identifier & record_identifier
  ID_FILE=$HOME/.cf-id_$CFRECORD_NAME.txt
  if [ -f $ID_FILE ] && [ $(wc -l < $ID_FILE) -eq 4 ] \
    && [ "$(sed -n '3p' "$ID_FILE")" == "$CFZONE_NAME" ] \
    && [ "$(sed -n '4p' "$ID_FILE")" == "$CFRECORD_NAME" ]; then
      CFZONE_ID=$(sed -n '1p' "$ID_FILE")
      CFRECORD_ID=$(sed -n '2p' "$ID_FILE")
  else
      echo "Updating zone_identifier & record_identifier"
      CFZONE_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$CFZONE_NAME" -H "Authorization: Bearer $CFKEY" -H "Content-Type: application/json" | grep -Po '(?<="id":")[^"]*' | head -1)
      CFRECORD_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$CFZONE_ID/dns_records?name=$CFRECORD_NAME" -H "Authorization: Bearer $CFKEY" -H "Content-Type: application/json" | grep -Po '(?<="id":")[^"]*' | head -1)
      echo "$CFZONE_ID" > $ID_FILE
      echo "$CFRECORD_ID" >> $ID_FILE
      echo "$CFZONE_NAME" >> $ID_FILE
      echo "$CFRECORD_NAME" >> $ID_FILE
  fi

  # If WAN is changed, update Cloudflare
  echo "Updating DNS to $WAN_IP"

  RESPONSE=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$CFZONE_ID/dns_records/$CFRECORD_ID" \
    -H "Authorization: Bearer $CFKEY" \
    -H "Content-Type: application/json" \
    --data "{\"id\":\"$CFZONE_ID\",\"type\":\"$CFRECORD_TYPE\",\"name\":\"$CFRECORD_NAME\",\"content\":\"$WAN_IP\", \"ttl\":$CFTTL}")

  if [ "$(echo $RESPONSE | grep "\"success\":true")" != "" ]; then
    echo "Updated successfully!"
    echo $WAN_IP > $WAN_IP_FILE
  else
    echo 'Something went wrong :('
    echo "Response: $RESPONSE"
    exit 1
  fi
fi

# Ensure CFZONE_ID is set before checking proxy status
if [ -z "${CFZONE_ID:-}" ]; then
  echo "CFZONE_ID is not set. Exiting."
  exit 1
fi

# Check and ensure Cloudflare proxy is enabled
echo "Ensuring Cloudflare proxy is enabled"
RECORD_DETAILS=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$CFZONE_ID/dns_records/$CFRECORD_ID" \
  -H "Authorization: Bearer $CFKEY" \
  -H "Content-Type: application/json")

PROXY_STATUS=$(echo $RECORD_DETAILS | grep "\"proxied\":true")

if [ -z "$PROXY_STATUS" ]; then
  echo "Proxy is disabled, enabling it now..."
  RESPONSE=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$CFZONE_ID/dns_records/$CFRECORD_ID" \
    -H "Authorization: Bearer $CFKEY" \
    -H "Content-Type: application/json" \
    --data "{\"id\":\"$CFZONE_ID\",\"type\":\"$CFRECORD_TYPE\",\"name\":\"$CFRECORD_NAME\",\"content\":\"$WAN_IP\", \"ttl\":$CFTTL, \"proxied\":true}")

  if [ "$(echo $RESPONSE | grep "\"success\":true")" != "" ]; then
    echo "Proxy enabled successfully!"
  else
    echo 'Failed to enable proxy :('
    echo "Response: $RESPONSE"
    exit 1
  fi
else
  echo "Proxy is already enabled"
fi
