setup_ccmv2() {
  : ${CCM_V2_INVERTING_PROXY_CERTIFICATE:? required}
  : ${CCM_V2_INVERTING_PROXY_HOST:? required}
  : ${CCM_V2_AGENT_KEY_ID:? required}
  : ${CCM_V2_AGENT_BACKEND_ID_PREFIX:? required}

  mkdir -p /etc/ccmv2

  ACCESS_KEY_PATH="/etc/ccmv2/access_key"
  touch $ACCESS_KEY_PATH
  chmod 600 "$ACCESS_KEY_PATH"

  cat > ${ACCESS_KEY_PATH} <<EOF
CCM_V2_AGENT_ACCESS_KEY_ID=$CCM_V2_AGENT_ACCESS_KEY_ID
EOF

  BACKEND_ID="${CCM_V2_AGENT_BACKEND_ID_PREFIX}${INSTANCE_ID}"
  BACKEND_HOST="localhost"
  BACKEND_PORT="9443"

  LEGACY_IV=436c6f7564657261436c6f7564657261
  AGENT_KEY_PATH=/etc/ccmv2/ccmv2-key.enc
  AGENT_CERT_PATH=/etc/ccmv2/ccmv2-cert.enc
  touch "$AGENT_KEY_PATH"
  touch "$AGENT_CERT_PATH"

  if [[ ! -z "$CCM_V2_AGENT_CERTIFICATE" &&  ! -z $CCM_V2_AGENT_ENCIPHERED_KEY ]]; then
    CCM_V2_AGENT_KEY_HEX=$(echo -n $CCM_V2_AGENT_KEY_ID | od -An -tx1 -N16 | tr -d ' \n')
    echo ${CCM_V2_AGENT_ENCIPHERED_KEY} | openssl enc -aes-128-cbc -d -A -a -K ${CCM_V2_AGENT_KEY_HEX} -iv ${LEGACY_IV} > ${AGENT_KEY_PATH}
    chmod 400 "$AGENT_KEY_PATH"

    echo "$CCM_V2_AGENT_CERTIFICATE" | base64 --decode > "$AGENT_CERT_PATH"
    chmod 400 "$AGENT_CERT_PATH"
  fi

  TRUSTED_BACKEND_CERT_PATH="/etc/jumpgate/cluster.pem"

  TRUSTED_PROXY_CERT_PATH=/etc/ccmv2/ccmv2-proxy-cert.enc
  echo "$CCM_V2_INVERTING_PROXY_CERTIFICATE" | base64 --decode > "$TRUSTED_PROXY_CERT_PATH"
  chmod 400 "$TRUSTED_PROXY_CERT_PATH"

  INVERTING_PROXY_URL="$CCM_V2_INVERTING_PROXY_HOST"

  if [[ "$IS_CCM_V2_JUMPGATE_ENABLED" == "true" && "$IS_FREEIPA" == "true" && ! -z $CCM_V2_AGENT_ACCESS_KEY_ID ]]; then

    if [[ -z $CCM_V2_AGENT_HMAC_KEY ]]; then
      # legacy without HMAC check, AES-128
      set +x
      ACCESS_KEY="$(echo ${CCM_V2_AGENT_ENCIPHERED_ACCESS_KEY} | openssl enc -aes-128-cbc -d -A -a -K ${CCM_V2_AGENT_KEY_HEX} -iv ${LEGACY_IV})"
      cat >>${ACCESS_KEY_PATH} <<EOF
ACCESS_KEY=$(echo "${ACCESS_KEY}" | base64 -w0 )
EOF
      set -x
    else
      # HMAC check, AES-256
      : ${CCM_V2_IV:? required}
      : ${CCM_V2_AGENT_HMAC_FOR_PRIVATE_KEY:? required}

      set +x
      CHECK_DIGEST="$(echo -n ${CCM_V2_AGENT_ENCIPHERED_ACCESS_KEY} | openssl dgst -hmac ${CCM_V2_AGENT_HMAC_KEY} -sha512 -r | cut -f1 -d' ')"
      if [[ "$CHECK_DIGEST" != "$CCM_V2_AGENT_HMAC_FOR_PRIVATE_KEY" ]]; then
        echo "HMAC for Machine User Private Key does not match the calculated value. Exiting."
        exit 1
      fi

      CCM_V2_AGENT_KEY_HEX32=$(echo -n $CCM_V2_AGENT_KEY_ID | od -An -tx1 -N32 | tr -d ' \n')
      CCM_V2_IV_HEX=$(echo -n $CCM_V2_IV | od -An -tx1 -N16 | tr -d ' \n')
      ACCESS_KEY="$(echo ${CCM_V2_AGENT_ENCIPHERED_ACCESS_KEY} | openssl enc -aes-256-cbc -d -A -a -K ${CCM_V2_AGENT_KEY_HEX32} -iv ${CCM_V2_IV_HEX})"
      cat >>${ACCESS_KEY_PATH} <<EOF
ACCESS_KEY=$(echo "${ACCESS_KEY}" | base64 -w0)
EOF
      set -x
    fi

  fi

  # A more sophisticated solution might need to be patched in later - tbh the script originally expected a full url with protocol scheme and closing slash
  INVERTING_PROXY_FULL_URL="https://$INVERTING_PROXY_URL/"

  /cdp/bin/ccmv2/generate-config.sh "$BACKEND_ID" "$BACKEND_HOST" "$BACKEND_PORT" "$AGENT_KEY_PATH" "$AGENT_CERT_PATH" "$ENVIRONMENT_CRN" "$ACCESS_KEY_PATH" "$TRUSTED_BACKEND_CERT_PATH" "$TRUSTED_PROXY_CERT_PATH" "$INVERTING_PROXY_FULL_URL"
}
