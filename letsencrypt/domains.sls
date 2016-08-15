# -*- coding: utf-8 -*-
# vim: ft=sls

{% set haproxyreload = {
    'xenial': 'systemctl reload haproxy',
    'trusty': 'service haproxy reload',
}.get(grains.oscodename) %}

{% from "letsencrypt/map.jinja" import letsencrypt with context %}

include:
  - haproxy.service

/usr/local/bin/check_letsencrypt_cert.sh:
  file.managed:
    - mode: 755
    - contents: |
        #!/bin/bash

        FIRST_CERT=$1

        for DOMAIN in "$@"
        do
            openssl x509 -in /etc/letsencrypt/live/$1/cert.pem -noout -text | grep DNS:${DOMAIN} > /dev/null || exit 1
        done
        CERT=$(date -d "$(openssl x509 -in /etc/letsencrypt/live/$1/cert.pem -enddate -noout | cut -d'=' -f2)" "+%s")
        CURRENT=$(date "+%s")
        REMAINING=$((($CERT - $CURRENT) / 60 / 60 / 24))
        [ "$REMAINING" -gt "30" ] || exit 1
        echo Domains $@ are in cert and cert is valid for $REMAINING days


{%- if letsencrypt.standalone -%}


{%
  for setname, domainlist in salt['pillar.get'](
    'letsencrypt:domainsets'
  ).iteritems()
%}


create-initial-cert-{{ setname }}-{{ domainlist | join('+') }}:
  cmd.run:
    - unless: /usr/local/bin/check_letsencrypt_cert.sh {{ domainlist|join(' ') }}
    - name: {{
          letsencrypt.cli_install_dir
        }}/letsencrypt-auto --no-self-upgrade -d {{ domainlist|join(' -d ') }} certonly --http-01-port 63443 && cat /etc/letsencrypt/live/{{ setname }}/fullchain.pem /etc/letsencrypt/live/{{ setname }}/privkey.pem > /etc/haproxy/certs/{{ setname }}.pem && {{ haproxyreload }} 
    - cwd: {{ letsencrypt.cli_install_dir }}
    - require:
      - file: letsencrypt-config
      - file: /usr/local/bin/check_letsencrypt_cert.sh

letsencrypt-crontab-{{ setname }}-{{ domainlist[0] }}:
  cron.present:
    - name: /usr/local/bin/check_letsencrypt_cert.sh {{ domainlist|join(' ') }} > /dev/null ||{{
          letsencrypt.cli_install_dir
        }}/letsencrypt-auto --no-self-upgrade -d {{ domainlist|join(' -d ') }} certonly  --http-01-port 63443
        && cat /etc/letsencrypt/live/{{ setname }}/fullchain.pem /etc/letsencrypt/live/{{ setname }}/privkey.pem > /etc/haproxy/certs/{{ setname }}.pem &&{{ haproxyreload }} 
    - month: '*'
    - minute: random
    - hour: random
    - dayweek: '*'
    - identifier: letsencrypt-{{ setname }}-{{ domainlist[0] }}
    - require:
      - cmd: create-initial-cert-{{ setname }}-{{ domainlist | join('+') }}
{% endfor %}

{%- else -%}


{%
  for setname, domainlist in salt['pillar.get'](
    'letsencrypt:domainsets'
  ).iteritems()
%}

create-initial-cert-{{ setname }}-{{ domainlist | join('+') }}:
  cmd.run:
    - unless: /usr/local/bin/check_letsencrypt_cert.sh {{ domainlist|join(' ') }}
    - name: {{
          letsencrypt.cli_install_dir
        }}/letsencrypt-auto --no-self-upgrade -d {{ domainlist|join(' -d ') }} certonly
    - cwd: {{ letsencrypt.cli_install_dir }}
    - require:
      - file: letsencrypt-config
      - file: /usr/local/bin/check_letsencrypt_cert.sh




letsencrypt-crontab-{{ setname }}-{{ domainlist[0] }}:
  cron.present:
    - name: /usr/local/bin/check_letsencrypt_cert.sh {{ domainlist|join(' ') }} > /dev/null ||{{
          letsencrypt.cli_install_dir
        }}/letsencrypt-auto --no-self-upgrade -d {{ domainlist|join(' -d ') }} certonly
    - month: '*'
    - minute: random
    - hour: random
    - dayweek: '*'
    - identifier: letsencrypt-{{ setname }}-{{ domainlist[0] }}
    - require:
      - cmd: create-initial-cert-{{ setname }}-{{ domainlist | join('+') }}
{% endfor %}

    {%- endif -%}
