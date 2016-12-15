#!/bin/bash

set -e -x

# The default build branch for all repositories. This defaults to
# TRAVIS_BRANCH unless set in the Travis build environment.
WTSI_NPG_BUILD_BRANCH=${WTSI_NPG_BUILD_BRANCH:=$TRAVIS_BRANCH}

sudo apt-get install -qq odbc-postgresql
sudo apt-get install libgd2-xpm-dev # For npg_tracking
sudo apt-get install liblzma-dev # For npg_qc

# iRODS
wget -q https://github.com/wtsi-npg/disposable-irods/releases/download/${DISPOSABLE_IRODS_VERSION}/disposable-irods-${DISPOSABLE_IRODS_VERSION}.tar.gz -O /tmp/disposable-irods-${DISPOSABLE_IRODS_VERSION}.tar.gz
tar xfz /tmp/disposable-irods-${DISPOSABLE_IRODS_VERSION}.tar.gz -C /tmp
cd /tmp/disposable-irods-${DISPOSABLE_IRODS_VERSION}
./scripts/download_and_verify_irods.sh
./scripts/install_irods.sh
./scripts/configure_irods.sh

# Jansson
wget -q https://github.com/akheron/jansson/archive/v${JANSSON_VERSION}.tar.gz -O /tmp/jansson-${JANSSON_VERSION}.tar.gz
tar xfz /tmp/jansson-${JANSSON_VERSION}.tar.gz -C /tmp
cd /tmp/jansson-${JANSSON_VERSION}
autoreconf -fi
./configure ; make ; sudo make install
sudo ldconfig

# baton
wget -q https://github.com/wtsi-npg/baton/releases/download/${BATON_VERSION}/baton-${BATON_VERSION}.tar.gz -O /tmp/baton-${BATON_VERSION}.tar.gz
tar xfz /tmp/baton-${BATON_VERSION}.tar.gz -C /tmp
cd /tmp/baton-${BATON_VERSION}


IRODS_HOME=
baton_irods_conf="--with-irods"

if [ -n "$IRODS_RIP_DIR" ]
then
    export IRODS_HOME="$IRODS_RIP_DIR/iRODS"
    baton_irods_conf="--with-irods=$IRODS_HOME"
fi

./configure ${baton_irods_conf} ; make ; sudo make install
sudo ldconfig

# htslib/samtools
wget -q https://github.com/samtools/htslib/releases/download/${HTSLIB_VERSION}/htslib-${HTSLIB_VERSION}.tar.bz2 -O /tmp/htslib-${HTSLIB_VERSION}.tar.bz2
tar xfj /tmp/htslib-${HTSLIB_VERSION}.tar.bz2 -C /tmp
cd /tmp/htslib-${HTSLIB_VERSION}
./configure --enable-plugins ; make ; sudo make install
sudo ldconfig

cd /tmp
git clone https://github.com/samtools/htslib-plugins.git htslib-plugins.git
cd htslib-plugins.git
make ; sudo make install

wget -q https://github.com/samtools/samtools/releases/download/${SAMTOOLS_VERSION}/samtools-${SAMTOOLS_VERSION}.tar.bz2 -O /tmp/samtools-${SAMTOOLS_VERSION}.tar.bz2
tar xfj /tmp/samtools-${SAMTOOLS_VERSION}.tar.bz2 -C /tmp
cd /tmp/samtools-${SAMTOOLS_VERSION}
./configure --enable-plugins --with-htslib=system ; make ; sudo make install
sudo ln -s /usr/local/bin/samtools /usr/local/bin/samtools_irods

# CPAN
cpanm --quiet --notest Alien::Tidyp # For npg_tracking
cpanm --quiet --notest Module::Build

### Temporary changes to Travis config for unreleased dependencies

# want to check out:
# - perl-irods-wrap, ml_warehouse from specific iainrb commits
# - others from wtsi-npg/master as normal

# WTSI NPG Perl repo dependencies
repos=""
for repo in perl-dnap-utilities npg_ml_warehouse npg_tracking npg_seq_common npg_qc; do
    cd /tmp
    # Always clone master when using depth 1 to get current tag
    git clone --branch master --depth 1 ${WTSI_NPG_GITHUB_URL}/${repo}.git ${repo}.git
    cd /tmp/${repo}.git
    # Shift off master to appropriate branch (if possible)
    git ls-remote --heads --exit-code origin ${WTSI_NPG_BUILD_BRANCH} && git pull origin ${WTSI_NPG_BUILD_BRANCH} && echo "Switched to branch ${WTSI_NPG_BUILD_BRANCH}"
    repos=$repos" /tmp/${repo}.git"
done

# iainrb Perl repo dependencies (not yet released on wtsi-npg, 2016-12-15)
PERL_IRODS_WRAP_COMMIT=b721f6bf04ab8e91aa9c96a2c6c2d3ea8d3e99ef
PERL_IRODS_WRAP_TEMP_VERSION=2.3.1
ML_WAREHOUSE_COMMIT=c67a7e8ac3c427593bdd9b08eb4b57989c7d1c15
ML_WAREHOUSE_TEMP_VERSION=2.6.1.1
cd /tmp
git clone https://github.com/iainrb/perl-irods-wrap.git perl-irods-wrap.git
cd perl-irods-wrap.git
git checkout $PERL_IRODS_WRAP_COMMIT
git tag -a $PERL_IRODS_WRAP_TEMP_VERSION -m "Temporary version $PERL_IRODS_WRAP_TEMP_VERSION"
cd /tmp
git clone https://github.com/iainrb/ml_warehouse.git ml_warehouse.git
cd ml_warehouse.git
git checkout $ML_WAREHOUSE_COMMIT
git tag -a $ML_WAREHOUSE_TEMP_VERSION -m "Temporary version $ML_WAREHOUSE_TEMP_VERSION"
cd /tmp
repos=$repos" /tmp/perl-irods-wrap.git /tmp/ml_warehouse.git"

# Install CPAN dependencies. The src libs are on PERL5LIB because of
# circular dependencies. The blibs are on PERL5LIB because the package
# version, which cpanm requires, is inserted at build time. They must
# be before the libs for cpanm to pick them up in preference.

for repo in $repos
do
    export PERL5LIB=$repo/blib/lib:$PERL5LIB:$repo/lib
done

for repo in $repos
do
    cd $repo
    cpanm --notest --installdeps .
    perl Build.PL
    ./Build
done

# Finally, bring any common dependencies up to the latest version and
# install
for repo in $repos
do
    cd $repo
    cpanm --notest --installdeps .
    ./Build install
done

cd $TRAVIS_BUILD_DIR

cpanm --notest --installdeps .
