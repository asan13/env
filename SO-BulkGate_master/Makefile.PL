use 5.010;
use strict;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME          => 'SO::BulkGate',
    VERSION_FROM  => 'lib/SO/BulkGate.pm', 
#    ABSTRACT_FROM => 'lib/SO/BulkGate.pm', 
    AUTHOR        => 'Konstantin S. Uvarin, Andrey V. Asyakin',

      TEST_REQUIRES => {
        'AE::AdHoc'       => 0,
        'Test::Exception' => 0,
        'DBD::SQLite'     => 0,
      },

    PREREQ_PM         => {
        'AnyEvent'                   => 0,
        'AnyEvent::HTTP'             => 0,
        'AnyEvent::Redis::RipeRedis' => 0,
        'Class::XSAccessor'          => 0,
        'common::sense'              => 0,
        'DBIx::RetryOverDisconnects' => 0,
        'JSON'                       => 0,
        'Log::Log4perl'              => 0,
        'Params::Validate'           => 0,
        'Plack::Request'             => 0,
        'Sub::Name'                  => 0,
        'URI::Escape'                => 0,
        'YAML::XS'                   => 0,
    },

    EXE_FILES => [ ],
);


package MY;

####
sub install {
    my $self = shift;
  
    my $install_sec = $self->SUPER::install( @_ );
    $install_sec =~ s/doc_install\n/doc_install notif_install\n/;
  
    $install_sec .= <<MAKE
bin_install :
	\$(NOECHO) \$(MOD_INSTALL) bin /www/bin/

etc_install :
	\$(NOECHO) \$(MOD_INSTALL) \\
		etc/conf.yml /www/etc/bulk_gate/

data_install:
	\$(NOECHO) \$(MOD_INSTALL) data/install /data/bulk_gate

daemon_install :
	\$(NOECHO) \$(MOD_INSTALL) daemon /www/daemon
	\$(NOECHO) \$(MOD_INSTALL) cron /www/cron
	\$(NOECHO) \$(MOD_INSTALL) psgi /www/psgi

notif_install :
	\$(NOECHO) echo "\\nSome notification!"
MAKE
;
    return $install_sec;
}

sub test {
    my $self = shift;
    my $test_sec = $self->SUPER::test( @_ );

    $test_sec .= q{
testall ::
	PERL_DL_NONLAZY=1 $(FULLPERLRUN) "-MExtUtils::Command::MM" "-e" "test_harness($(TEST_VERBOSE), '$(INST_LIB)', '$(INST_ARCHLIB)')" t/*.t xt/*.t
};
    return $test_sec;
}


1;
