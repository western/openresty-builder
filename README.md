# Openresty with specific

Openresty Nginx with steroids

based on https://gist.github.com/western/c04efe49745f24874c43

## command only

* wget https://raw.githubusercontent.com/western/openresty-builder/dev/builder
* chmod +x builder
* make code fit
```bash
IS_LOCAL=1|0 - const for locate folder to build
IS_PAUSED=1|0 - program wait for info board
IS_GET_ONLY=1|0 - do make and compile after download
```
* ./builder

## versions

* openresty-1.25.3.1
* luajit 2.1
* openssl-3.2.1

## nginx modules

* https://github.com/arut/nginx-dav-ext-module.git
* https://github.com/sto/ngx_http_auth_pam_module.git

## systemd

* cd /usr/lib/systemd/system/
* wget https://raw.githubusercontent.com/western/openresty-builder/dev/etc/openresty12531.service
