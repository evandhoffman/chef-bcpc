#!/bin/bash -e
set -e

# This script must be invoked from the root of the repository (e.g., as
# bootstrap/common_scripts/common_build_bins.sh).

FILES_ROOT=/chef-bcpc-files

pushd cookbooks/bcpc/files/default
# Define the appropriate version of each binary to grab/build
VER_KIBANA=4.0.2
VER_PIP=7.0.3
VER_RALLY=0.0.4
VER_REQUESTS_AWS=0.1.6
VER_GRAPHITE_CARBON=0.9.13
VER_GRAPHITE_WHISPER=0.9.13
VER_GRAPHITE_WEB=0.9.13
# newer versions of Diamond depend upon dh-python which isn't in precise/12.04
VER_DIAMOND=f33aa2f75c6ea2dfbbc659766fe581e5bfe2476d
VER_ESPLUGIN=9c032b7c628d8da7745fbb1939dcd2db52629943

pushd bins
# Install tools needed for packaging
apt-get -y install git ruby-dev make pbuilder python-mock python-configobj python-support cdbs python-all-dev python-stdeb libmysqlclient-dev libldap2-dev libxml2-dev libxslt1-dev libpq-dev build-essential libssl-dev libffi-dev python-dev python-pip

# install fpm and support gems
if [ -z `gem list --local fpm | grep fpm | cut -f1 -d" "` ]; then
  pushd $FILES_ROOT/fpm_gems/
  gem install -l --no-ri --no-rdoc arr-pm-0.0.10.gem backports-3.6.4.gem cabin-0.7.1.gem childprocess-0.5.6.gem clamp-0.6.5.gem ffi-1.9.8.gem fpm-1.3.3.gem json-1.8.2.gem
  popd
fi

# Build kibana 4 deb
if [ ! -f kibana_${VER_KIBANA}_amd64.deb ]; then
  cp -v $FILES_ROOT/kibana-${VER_KIBANA}-linux-x64.tar.gz kibana-${VER_KIBANA}.tar.gz
  tar -zxf kibana-${VER_KIBANA}.tar.gz
  fpm -s dir -t deb --prefix /opt/kibana -n kibana -v ${VER_KIBANA} -C kibana-${VER_KIBANA}-linux-x64
  rm -rf kibana-${VER_KIBANA}-linux-x64{,.tar.gz}
fi
FILES="kibana_${VER_KIBANA}_amd64.deb $FILES"

# fluentd plugins and dependencies are fetched by bootstrap_prereqs.sh, just copy them
# in from the local cache and add them to $FILES
cp $FILES_ROOT/fluentd_gems/*.gem .
FILES="$(ls -1 $FILES_ROOT/fluentd_gems/*.gem | xargs) $FILES"

# Fetch the cirros image for testing
if [ ! -f cirros-0.3.4-x86_64-disk.img ]; then
  cp -v $FILES_ROOT/cirros-0.3.4-x86_64-disk.img .
fi
FILES="cirros-0.3.4-x86_64-disk.img $FILES"

# Grab the Ubuntu 14.04 installer image
if [ ! -f ubuntu-14.04-mini.iso ]; then
  cp -v $FILES_ROOT/ubuntu-14.04-mini.iso ubuntu-14.04-mini.iso
fi
FILES="ubuntu-14.04-mini.iso $FILES"

# Make the diamond package
if [ ! -f diamond.deb ]; then
  cp -r $FILES_ROOT/diamond Diamond
  cd Diamond
  git checkout $VER_DIAMOND
  make builddeb
  VERSION=`cat version.txt`
  cd ..
  mv Diamond/build/diamond_${VERSION}_all.deb diamond.deb
  rm -rf Diamond
fi
FILES="diamond.deb $FILES"

if [ ! -f elasticsearch-plugins.tgz ]; then
  cp -r $FILES_ROOT/elasticsearch-head .
  cd elasticsearch-head
  git archive --output ../elasticsearch-plugins.tgz --prefix head/_site/ $VER_ESPLUGIN
  cd ..
  rm -rf elasticsearch-head
fi
FILES="elasticsearch-plugins.tgz $FILES"

# Fetch pyrabbit
if [ ! -f pyrabbit-1.0.1.tar.gz ]; then
  cp -v $FILES_ROOT/pyrabbit-1.0.1.tar.gz .
fi
FILES="pyrabbit-1.0.1.tar.gz $FILES"

# Build requests-aws package
if [ ! -f python-requests-aws_${VER_REQUESTS_AWS}_all.deb ]; then
  cp -v $FILES_ROOT/requests-aws-${VER_REQUESTS_AWS}.tar.gz .
  tar zxf requests-aws-${VER_REQUESTS_AWS}.tar.gz
  fpm -s python -t deb -f requests-aws-${VER_REQUESTS_AWS}/setup.py
  rm -rf requests-aws-${VER_REQUESTS_AWS}.tar.gz requests-aws-${VER_REQUESTS_AWS}
fi

# Build graphite packages
if [ ! -f python-carbon_${VER_GRAPHITE_CARBON}_all.deb ] || [ ! -f python-whisper_${VER_GRAPHITE_WHISPER}_all.deb ] || [ ! -f python-graphite-web_${VER_GRAPHITE_WEB}_all.deb ]; then
  cp -v $FILES_ROOT/carbon-${VER_GRAPHITE_CARBON}.tar.gz .
  cp -v $FILES_ROOT/whisper-${VER_GRAPHITE_WHISPER}.tar.gz .
  cp -v $FILES_ROOT/graphite-web-${VER_GRAPHITE_WEB}.tar.gz .
  tar zxf carbon-${VER_GRAPHITE_CARBON}.tar.gz
  tar zxf whisper-${VER_GRAPHITE_WHISPER}.tar.gz
  tar zxf graphite-web-${VER_GRAPHITE_WEB}.tar.gz
  fpm --python-install-bin /opt/graphite/bin -s python -t deb -f carbon-${VER_GRAPHITE_CARBON}/setup.py
  fpm --python-install-bin /opt/graphite/bin -s python -t deb -f whisper-${VER_GRAPHITE_WHISPER}/setup.py
  fpm --python-install-lib /opt/graphite/webapp -s python -t deb -f graphite-web-${VER_GRAPHITE_WEB}/setup.py
  rm -rf carbon-${VER_GRAPHITE_CARBON} carbon-${VER_GRAPHITE_CARBON}.tar.gz whisper-${VER_GRAPHITE_WHISPER} whisper-${VER_GRAPHITE_WHISPER}.tar.gz graphite-web-${VER_GRAPHITE_WEB} graphite-web-${VER_GRAPHITE_WEB}.tar.gz
fi
FILES="python-carbon_${VER_GRAPHITE_CARBON}_all.deb python-whisper_${VER_GRAPHITE_WHISPER}_all.deb python-graphite-web_${VER_GRAPHITE_WEB}_all.deb $FILES"

# Build the zabbix packages
if [ ! -f zabbix-agent.tar.gz ] || [ ! -f zabbix-server.tar.gz ]; then
  cp -v $FILES_ROOT/zabbix-2.2.2.tar.gz .
  tar zxf zabbix-2.2.2.tar.gz
  rm -rf /tmp/zabbix-install && mkdir -p /tmp/zabbix-install
  cd zabbix-2.2.2
  ./configure --prefix=/tmp/zabbix-install --enable-agent --with-ldap
  make install
  tar zcf zabbix-agent.tar.gz -C /tmp/zabbix-install .
  rm -rf /tmp/zabbix-install && mkdir -p /tmp/zabbix-install
  ./configure --prefix=/tmp/zabbix-install --enable-server --with-mysql --with-ldap
  make install
  cp -a frontends/php /tmp/zabbix-install/share/zabbix/
  cp database/mysql/* /tmp/zabbix-install/share/zabbix/
  tar zcf zabbix-server.tar.gz -C /tmp/zabbix-install .
  rm -rf /tmp/zabbix-install
  cd ..
  cp zabbix-2.2.2/zabbix-agent.tar.gz .
  cp zabbix-2.2.2/zabbix-server.tar.gz .
  rm -rf zabbix-2.2.2 zabbix-2.2.2.tar.gz
fi
FILES="zabbix-agent.tar.gz zabbix-server.tar.gz $FILES"

# Rally has a number of dependencies. Some of the dependencies are in apt by default but some are not. Those that
# are not are built here.

# We build a package for rally here but we also get the tar file of the source because it includes the samples
# directory that we want and we need a good place to run our tests from.

if [ ! -f rally.tar.gz ]; then
  cp /chef-bcpc-files/rally/rally-${VER_RALLY}.tar.gz .
  tar xvf rally-${VER_RALLY}.tar.gz
  tar zcf rally.tar.gz -C rally-${VER_RALLY}/ .
  rm -rf rally-${VER_RALLY}.tar.gz rally-${VER_RALLY}
fi

# TODO FOR erhudy: fix up these Rally packages to be built like the Graphite stuff

if [ ! -f rally-pip.tar.gz ] || [ ! -f rally-bin.tar.gz ]; then
  # Rally has a very large number of version specific dependencies!!
  # The latest version of PIP is installed instead of the distro version. We don't want this to block to exit on error
  # so it is changed here and reset at the end. Several apt packages must be present since easy_install builds
  # some of the dependencies.
  # Note: Once we fully switch to trusty/kilo then we should not have to patch this (hopefully).
  echo "Processing Rally setup..."

  # Create a deb for pip to replace really old upstream pip
  if [[ ! -f python-pip_${VER_PIP}_all.deb ]]; then
    cp $FILES_ROOT/rally/pip-${VER_PIP}.tar.gz .
    tar xvzf pip-${VER_PIP}.tar.gz
    fpm -s python -t deb pip-${VER_PIP}/setup.py
    dpkg -i python-pip_${VER_PIP}_all.deb
    rm -rf pip-${VER_PIP} pip-${VER_PIP}.tar.gz
  fi

  # We install rally and a few other items here. Since fpm does not resolve dependencies but only lists them, we
  # have to force an install and then tar up the dist-packages and local/bin
  PIP_INSTALL="pip install --no-cache-dir --disable-pip-version-check --no-index -f $FILES_ROOT/rally"
  $PIP_INSTALL --default-timeout 60 -I rally 
  $PIP_INSTALL --default-timeout 60 python-openstackclient
  $PIP_INSTALL -U argparse
  $PIP_INSTALL -U setuptools

  tar zcf rally-pip.tar.gz -C /usr/local/lib/python2.7/dist-packages .
  tar zcf rally-bin.tar.gz --exclude="fpm" --exclude="ruby*" -C /usr/local/bin .
fi

FILES="rally.tar.gz rally-pip.tar.gz rally-bin.tar.gz python-pip_${VER_PIP}_all.deb $FILES"

# End of Rally
popd # bins
popd # cookbooks/bcpc/files/default