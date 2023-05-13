#!/bin/bash

# save and run
# . builder

CPUC=`cat /proc/cpuinfo | grep processor | wc -l`
CPUC=$((CPUC-1))
PARENTF=`pwd`
BUILDF="$PARENTF/build"
OPRV='openresty-1.21.4.1'
IS_LOCAL=1
IS_PAUSED=0
IS_GET_ONLY=1



function main {
    notice "builder for $OPRV"
    notice "from parent folder $PARENTF"

    warn "IS_LOCAL $IS_LOCAL"
    warn "IS_PAUSED $IS_PAUSED"
    warn "IS_GET_ONLY $IS_GET_ONLY"

    rm versions

    if whoami | grep -q root; then
        root_prepare
    fi

    #postgres_get
    #redis_get

    #etc_src
    #ngx_module
    luajit2_prepare
    #lua_src
    openssl_get
    opr_src
    make_configure

    #make_nginx_service
    #make_postgres_service
    #make_nginx_tmpfile

    #prepare_for_archive
}

# ------------------------------------------------------------------------------

function root_prepare {

    notice "root_prepare"

    if ! whoami | grep -q root; then
        err 'root required. exit.'
    fi

    if ! grep -q "nginx" /etc/passwd; then
        groupadd nginx
        useradd -M -g nginx nginx
    fi

    if cat /etc/*release* | grep -q 'openSUSE Leap 15.4'; then
        warn 'openSUSE Leap 15.4 detected.'
        zypper in -t pattern -y devel_C_C++ devel_basis devel_perl console
        zypper in -y pcre-devel libopenssl-devel gd-devel libGeoIP-devel libatomic_ops-devel dialog
    fi

    if cat /etc/*release* | grep -q 'VERSION="9 (stretch)"'; then
        warn 'Debian 9 detected.'
        apt-get install -y vim mc less mlocate git cmake build-essential curl gnupg aptitude
        apt-get install -y libpq-dev libpcre3-dev zlib1g-dev libgd-dev libgeoip-dev libatomic-ops-dev
    fi

    if cat /etc/*release* | grep -q 'VERSION="10 (buster)"'; then
        warn 'Debian 10 detected.'
        apt-get install -y vim mc less mlocate git cmake build-essential curl gnupg aptitude
        apt-get install -y libpq-dev libpcre3-dev zlib1g-dev libgd-dev libgeoip-dev libatomic-ops-dev

        if [ -f /usr/bin/gcc-8 ] && [ -f /usr/bin/gcc-7 ] && [ `gcc -dumpversion` -gt 7 ] ; then
            err 'gcc 7 required. update-alternatives --set gcc /usr/bin/gcc-7 and run builder again.'
        fi

        if [ -f /usr/bin/gcc-8 ] && [ ! -f /usr/bin/gcc-7 ]; then

            aptitude install -y gcc-7

            if [ -f /usr/bin/gcc-7 ]; then

                update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-7 10
                update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-8 20

                update-alternatives --list gcc

                update-alternatives --set gcc /usr/bin/gcc-7
                warn 'set after install: update-alternatives --set gcc /usr/bin/gcc-8'
            fi

            err 'gcc 7 required. run builder again.'
        fi
    fi

    if cat /etc/*release* | grep -q 'VERSION="11 (bullseye)"'; then
        warn 'Debian 11 detected.'
        apt-get install -y vim mc less mlocate git cmake build-essential curl gnupg aptitude
        apt-get install -y libpq-dev libpcre3-dev zlib1g-dev libgd-dev libgeoip-dev libatomic-ops-dev
    fi


    if cat /etc/*release* | grep -q 'CentOS Linux release 8'; then
        warn 'CentOS 8 detected.'

        dnf groupinstall "Development Tools" -y
        dnf config-manager --set-enabled PowerTools
        dnf install python2 -y
        dnf install pcre-devel -y
        dnf install zlib-devel -y
        dnf install gd-devel -y
        dnf install openssl-devel -y

        dnf install epel-release -y
        dnf install GeoIP-devel -y
        dnf install libatomic_ops-devel -y

        ln -s /usr/bin/python2 /usr/bin/python
    fi

    if [ $IS_LOCAL == 0 ]; then
        rm -rf /usr/local/$OPRV
        rm -rf /var/lib/openresty/
        mkdir -p /var/lib/openresty/{fastcgi,proxy,scgi,tmp,uwsgi,cache}
        chown -R nginx:nginx /var/lib/openresty/

        mkdir -p /var/run/openresty
        chown -R nginx:nginx /var/run/openresty

        mkdir /var/log/openresty/
    fi
}


# ------------------------------------------------------------------------------


function opr_src {

    notice "opr_src"

    mkdir opr_src ; cd opr_src

    get_arch "https://openresty.org/download/$OPRV.tar.gz" "$OPRV.tar.gz" $OPRV

    cd $PARENTF
}

# ------------------------------------------------------------------------------

function luajit2_prepare {

    notice "luajit2_prepare"

    if [ $IS_LOCAL == 1 ]; then
        mkdir lua_src ; cd lua_src
    else
        mkdir -p /opt/lua_src ; cd /opt/lua_src
    fi

    get_github 'openresty' 'luajit2.git'
    if [ $IS_GET_ONLY == 0 ]; then
        pushd 'luajit2.git'

            make clean
            mkdir build

            if [ $IS_LOCAL == 1 ]; then
                make -j4 PREFIX=$PARENTF/lua_src/luajit2.git/build
                make install PREFIX=$PARENTF/lua_src/luajit2.git/build
            else
                make -j4 PREFIX=/opt/lua_src/luajit2.git/build
                make install PREFIX=/opt/lua_src/luajit2.git/build
            fi
        popd
    fi

    cd $PARENTF
}

# ------------------------------------------------------------------------------

function openssl_get {

    notice "openssl_get"

    mkdir etc_src ; cd etc_src


    #get_arch 'https://github.com/openssl/openssl/archive/OpenSSL_1_1_1g.tar.gz' 'OpenSSL_1_1_1g.tar.gz' 'openssl-OpenSSL_1_1_1g'
    get_arch 'https://github.com/openssl/openssl/releases/download/openssl-3.1.0/openssl-3.1.0.tar.gz' 'openssl-3.1.0.tar.gz' 'openssl-3.1.0'


    cd $PARENTF
}

# ------------------------------------------------------------------------------


function make_configure {

    notice "make_configure"

    local PREFIX=""
    local CONF_PATH=""
    local PID_PATH=""
    local ERROR_LOG=""
    local HTTP_LOG=""
    local CLIENT_BODY_TEMP=""
    local PROXY_TEMP_PATH=""
    local FASTCGI_TEMP_PATH=""
    local UWSGI_TEMP_PATH=""
    local SCGI_TEMP_PATH=""
    local LUAJIT2_BUILD_LIB=""
    local LUAJIT2_SRC=""
    #local LUA_SSL_NGINX_MODULE=""

    if [ $IS_LOCAL == 1 ]; then
        mkdir -p $BUILDF/{tmp,proxy,fastcgi,uwsgi,scgi}
        PREFIX="$BUILDF/"
        CONF_PATH="$PREFIX/conf/nginx.conf"
        PID_PATH="$PREFIX/logs/nginx.pid"
        ERROR_LOG="$PREFIX/logs/error.log"
        HTTP_LOG="$PREFIX/logs/access.log"
        CLIENT_BODY_TEMP="$PREFIX/tmp/"
        PROXY_TEMP_PATH="$PREFIX/proxy/"
        FASTCGI_TEMP_PATH="$PREFIX/fastcgi/"
        UWSGI_TEMP_PATH="$PREFIX/uwsgi/"
        SCGI_TEMP_PATH="$PREFIX/scgi/"
        LUAJIT2_BUILD_LIB="$PARENTF/lua_src/luajit2.git/build/lib"
        LUAJIT2_SRC="$PARENTF/lua_src/luajit2.git/src"
        #LUA_SSL_NGINX_MODULE="$PARENTF/lua_src/lua-ssl-nginx-module.git/"
    else
        PREFIX="/usr/local/$OPRV"
        CONF_PATH="/etc/$OPRV/nginx.conf"
        PID_PATH="/usr/local/$OPRV/nginx/logs/nginx.pid"
        ERROR_LOG="/usr/local/$OPRV/nginx/logs/error.log"
        HTTP_LOG="/usr/local/$OPRV/nginx/logs/access.log"
        CLIENT_BODY_TEMP="/var/lib/openresty/tmp/"
        PROXY_TEMP_PATH="/var/lib/openresty/proxy/"
        FASTCGI_TEMP_PATH="/var/lib/openresty/fastcgi/"
        UWSGI_TEMP_PATH="/var/lib/openresty/uwsgi/"
        SCGI_TEMP_PATH="/var/lib/openresty/scgi/"
        LUAJIT2_BUILD_LIB="/opt/lua_src/luajit2.git/build/lib"
        LUAJIT2_SRC="/opt/lua_src/luajit2.git/src"
        #LUA_SSL_NGINX_MODULE="/opt/lua_src/lua-ssl-nginx-module.git/"
    fi

    WITH_OPENSSL=""
    if [ -d $PARENTF/etc_src/openssl-3.1.0 ]; then
        WITH_OPENSSL="--with-openssl=$PARENTF/etc_src/openssl-3.1.0 --with-openssl-opt='enable-tls1_3'"
    fi


cat << L10HEREDOC > opr_src/$OPRV/nginx_configuration
#!/bin/bash

./configure \\
--with-cc-opt="-Wno-sign-compare -Wno-string-plus-int -Wno-deprecated-declarations -Wno-unused-parameter -Wno-unused-const-variable -Wno-conditional-uninitialized -Wno-mismatched-tags -Wno-sometimes-uninitialized -Wno-parentheses-equality -Wno-tautological-compare -Wno-self-assign -Wno-deprecated-register -Wno-deprecated -Wno-invalid-source-encoding -Wno-pointer-sign -Wno-parentheses -Wno-enum-conversion -Wno-c++11-compat-deprecated-writable-strings -Wno-write-strings" \\
--with-ld-opt="-Wl,-rpath,$LUAJIT2_BUILD_LIB" \\
--prefix=$PREFIX \\
--conf-path=$CONF_PATH \\
--pid-path=$PID_PATH \\
--error-log-path=$ERROR_LOG \\
--http-log-path=$HTTP_LOG \\
--http-client-body-temp-path=$CLIENT_BODY_TEMP \\
--http-proxy-temp-path=$PROXY_TEMP_PATH \\
--http-fastcgi-temp-path=$FASTCGI_TEMP_PATH \\
--http-uwsgi-temp-path=$UWSGI_TEMP_PATH \\
--http-scgi-temp-path=$SCGI_TEMP_PATH \\
--user=nginx \\
--group=nginx \\
--with-debug \\
--with-stream \\
--with-stream_ssl_module \\
--with-stream_ssl_preread_module \\
--with-threads \\
--with-file-aio \\
--with-http_ssl_module $WITH_OPENSSL \\
--with-http_v2_module \\
--with-http_realip_module \\
--with-http_addition_module \\
--with-http_image_filter_module \\
--with-http_geoip_module \\
--with-http_sub_module \\
--with-http_mp4_module \\
--with-http_gunzip_module \\
--with-http_gzip_static_module \\
--with-http_random_index_module \\
--with-http_secure_link_module \\
--with-http_stub_status_module \\
--with-pcre \\
--with-pcre-jit \\
--with-libatomic \\


L10HEREDOC

    chmod +x "opr_src/$OPRV/nginx_configuration"

    notice "export these environment:"
    #echo "unset LUAJIT_LIB && unset LUAJIT_INC"
    #echo "unset SREGEX_LIB && unset SREGEX_INC"
    #echo "unset LIBDRIZZLE_INC && unset LIBDRIZZLE_LIB"
    #echo "unset MODSECURITY_INC && unset MODSECURITY_LIB"
    echo
    echo "export LUAJIT_LIB=$LUAJIT2_BUILD_LIB && export LUAJIT_INC=$LUAJIT2_SRC"

    #if [ $IS_LOCAL == 1 ]; then
        #echo "export SREGEX_LIB=$PARENTF/etc_src/sregex.git/build/lib && export SREGEX_INC=$PARENTF/etc_src/sregex.git/src"
        #echo "export LIBDRIZZLE_INC=$PARENTF/etc_src/drizzle7-2011.07.21/build/include/libdrizzle-1.0 && export LIBDRIZZLE_LIB=$PARENTF/etc_src/drizzle7-2011.07.21/build/lib64/"
        #echo "export MODSECURITY_INC=$BUILDF/modsecurity/include/"
        #echo "export MODSECURITY_LIB=$BUILDF/modsecurity/lib64/"
    #fi
    echo

    notice 'run ./nginx_configuration'
    notice 'gmake install -j4'

    if [ $IS_PAUSED == 1 ]; then
        read -p "Press [Enter] key to continue..."
    fi

    cd opr_src/$OPRV && exec bash
}




# ------------------------------------------------------------------------------

# get_arch 'https://domain.tld/archive.tar.gz' 'archive.tar.gz' 'folder'

function get_arch {
    notice "get_arch [$1] FILE [$2] FOLD [$3]"
    local     getUrl=$1
    local   fileName=$2
    local folderName=$3

    if [ ! -f $fileName ]; then
        notice "wget $getUrl -O $fileName"
        wget $getUrl -O $fileName
    fi

    #if [ -d $folderName ]; then
    #    notice "rm rf $folderName"
    #    rm -rf $folderName
    #fi



    if [ ! -d $folderName ] && [[ $fileName =~ ".zip" ]]; then
        notice "unzip"
        unzip $fileName
    fi

    if [[ ! -d $folderName ]] && [[ $fileName =~ ".tar." ]]; then
        notice "tar xf"
        tar xf $fileName
    fi



    if [ ! -f $fileName ]; then
        err "get_arch: file $fileName is not exists"
    fi

    if [ ! -d $folderName ]; then
        err "get_arch: folder $folderName is not exists"
    fi
}

# ------------------------------------------------------------------------------

# get_github 'user' 'project.git'
# get_github 'user' 'project.git' 'branch'
#
# project 'project.git' save to similar folder 'project.git'

function get_github {
    notice "get_github https://github.com/$1/$2"
    local folderName=$2
    local     branch=$3

    if [ -d $folderName ]; then
        cd $folderName
        pwd
        git pull
        cd ..
    else
        if [ "$branch" == "" ]; then
            git clone https://github.com/$1/$folderName $folderName
        else
            warn "branch $branch"
            git clone -b $branch https://github.com/$1/$folderName $folderName
        fi
    fi

    if [ ! -d $folderName ]; then
        err "get_github: folder $folderName is not exists"
    fi

    echo "https://github.com/$1/$folderName" >> "$PARENTF/versions"

    pushd $folderName
        git describe --tags --abbrev=0
        echo `git describe --tags --abbrev=0` >> "$PARENTF/versions"
    popd
}

# ------------------------------------------------------------------------------

# get_gitany 'https://domain.tld/anypath' 'folder.git'
# get_gitany 'https://domain.tld/anypath' 'folder.git' 'branch'

function get_gitany {
    notice "get_gitany $1 to $2"
    local folderName=$2
    local     branch=$3

    if [ -d $folderName ]; then
        pushd $folderName
            pwd
            git pull
        popd
    else
        if [ "$branch" == "" ]; then
            git clone $1 $folderName
        else
            warn "branch $branch"
            git clone -b $branch $1 $folderName
        fi
    fi

    if [ ! -d $folderName ]; then
        err "get_gitany: folder $folderName is not exists"
    fi

    echo "$1" >> "$PARENTF/versions"

    pushd $folderName
        git describe --tags --abbrev=0
        echo `git describe --tags --abbrev=0` >> "$PARENTF/versions"
    popd
}

# ------------------------------------------------------------------------------

function notice {
    builtin echo -en "\033[1m"
    echo "NOTICE: $@"
    builtin echo -en "\033[0m"
}

function success {
    builtin echo -en "\033[1;32m"
    echo "SUCCESS: $@"
    builtin echo -en "\033[0m"
}

function warn {
    builtin echo -en "\033[1;33m"
    echo "WARN: $@"
    builtin echo -en "\033[0m"
}

function err {
    builtin echo -en "\033[1;31m"
    echo "ERR: $@"
    builtin echo -en "\033[0m"
    exit 1
}

function fatal {
    builtin echo -en "\033[1;31m"
    echo "FATAL: $@"
    builtin echo -en "\033[0m"
    exit 1
}

# ------------------------------------------------------------------------------

main
