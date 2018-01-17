package WTSI::NPG::HTS::MetaHelperFactoryTest;

use strict;
use warnings;
use File::Temp qw[tempdir];
use Log::Log4perl;

use Test::More;
use Test::Exception;
use WTSI::NPG::iRODS;
use WTSI::NPG::HTS::MetaHelperFactory;

use base qw[WTSI::NPG::HTS::TestRabbitMQ];

# Tests below do not require a RabbitMQ server, but *do* require the
# Net::AMQP::RabbitMQ module. The TEST_RABBITMQ variable defined in the
# base class WTSI::NPG::HTS::TestRabbitMQ can be used to skip this class,
# if Net::AMQP::RabbitMQ is not installed.

Log::Log4perl::init('./etc/log4perl_tests.conf');

sub require : Test(1) {
    require_ok('WTSI::NPG::HTS::MetaHelperFactory');
}

sub make_helpers : Test(6) {

    my $irods = WTSI::NPG::iRODS->new(environment          => \%ENV,
                                      strict_baton_version => 0);

    my $tmp = tempdir('MetaHelperFactoryTest_temp_XXXXXX',
                      CLEANUP => 1);

    my $factory0 = WTSI::NPG::HTS::MetaHelperFactory->new(
        enable_rmq         => 0,
        irods              => $irods,
    );
    my $helper0 = $factory0->make_meta_helper();
    isa_ok($helper0, 'WTSI::NPG::HTS::MetaHelper');
    # ensure we have an instance of the parent class, not the subclass
    ok(!($helper0->isa('WTSI::NPG::HTS::MetaHelperWithReporting')),
       'Factory does not return a MetaHelperWithReporting');

    my $factory1 = WTSI::NPG::HTS::MetaHelperFactory->new(
        channel            => 42,
        enable_rmq         => 1,
        exchange           => 'foo',
        irods              => $irods,
        routing_key_prefix => 'bar',
    );
    my $helper1 = $factory1->make_meta_helper();
    isa_ok($helper1, 'WTSI::NPG::HTS::MetaHelperWithReporting');
    is($helper1->channel, 42, 'channel attribute is correct');
    is($helper1->exchange, 'foo', 'exchange attribute is correct');
    is($helper1->routing_key_prefix, 'bar',
       'routing_key_prefix attribute is correct');

}
