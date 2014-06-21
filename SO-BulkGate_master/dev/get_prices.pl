#!/usr/bin/perl
#
#

use strict;
use warnings;
use 5.010;

use Data::Dumper;


my $loader = PriceLoader->new();
$loader->load_prices();
$loader->output_prices();




package PriceLoader;

use strict qw/vars subs/;
use warnings;
use utf8;
use 5.010;

use Data::Dumper;
use Carp;
use YAML::XS;
use Getopt::Long;

use constant {
    SSH_HOST   => 'l-4.aqq.me',
    SQL_SCRIPT => 'get_prices.sql',
    SQL_USER   => 'bulk',
    DBNAME     => 'codesdb',
    CSV_GATES  => [ qw/clx ib nth amd beep mblox silver idm/ ],
};


sub new {
    my $class = shift;

    bless my $self = {}, $class;
    $self->parse_options(@_);

    return $self;
}

sub parse_options {
    my $self = shift;

    my @argv = ref $_[0] ? @{$_[0]} : @_;
    @ARGV = @argv if @argv;

    local $SIG{__WARN__} = sub { die $_[0] };

    my $parser = Getopt::Long::Parser->new(
        config => [ qw/no_auto_abbrev no_ignore_case pass_through/ ],
    );
    
    my %opts;

    my $treat_opt = sub {
        my ($key, $value) = @_;
        if ($value =~ /^--/) {
            $key =~ s/^--//;
            $opts{$key} = 1;
            unshift @ARGV, $value;
        }
        else {
            $opts{$key} = $value;
        }
    };

    $parser->getoptions(
        'csv=s'        => \$opts{csv},
        'csv_gates=s'  => \$opts{csv_gates},
        'dump=s'       => \$opts{dump},
        'connect=s'    => $treat_opt, 
        'ssh=s'        => $treat_opt, 
        'sql-script=s' => \$opts{sql_script},
        'write-sql'    => \$opts{write_sql},
        'dbname'       => \$opts{dbname}, 
        'sql-user'     => \$opts{sql_user},
        'extra=s'      => \$opts{extra},
        'input=s'      => \$opts{input},
        'output|o=s'   => \$opts{output},
        'help|h'       => \$opts{help},
        'man'          => \$opts{man},
    );

    if ( $opts{help} || $opts{man} || !grep $_, values %opts ) {
        $self->help($opts{man});
        exit 0;
    }

    $opts{output} ||= shift @ARGV if @ARGV;


    -f $opts{$_} || die "file for '$_' options not found" 
        for grep defined $opts{$_}, qw/csv dump extra input/;

    
    if ($opts{ssh} || $opts{sql_script}) {
        $opts{ssh_host}   = !$opts{ssh} || $opts{ssh} == 1 ? SSH_HOST 
                           : $opts{ssh};
        $opts{sql_script} = SQL_SCRIPT if !$opts{sql_script} 
                                       || $opts{sql_script} == 1;

        $opts{sql_user} ||= SQL_USER;
        $opts{dbname}   ||= DBNAME;
        $opts{ssh} = 1;
    }

    if ($opts{connect}) {
        $opts{connect} = get_connect(\%opts);
    }

    $self->{db_getters} = [];
    foreach my $suffix ( grep $opts{$_}, qw/dump ssh connect/ ) {
        my $method = "db_get_from_$suffix";
        push @{$self->{db_getters}}, \&{$method};
    }

    if ($opts{csv}) {
        my $cg = $opts{csv_gates};
        $opts{csv_gates} = $cg ? [ split /,/, $cg ] : [ @{&CSV_GATES} ];
    }

    $opts{db} = @{$self->{db_getters}} ? 1 : 0;
    $opts{sources} = [ 
        map { \&{"get_${_}_prices"} } grep $opts{$_}, qw/input db csv extra/ 
    ];

    $self->{$_} = $opts{$_} for keys %opts;
}


sub load_prices {
    my $self = shift;

    $self->{prices} = {};
    foreach my $method ( @{$self->{sources}} ) {
        $self->$method();
    }

    return $self->{prices};
}

sub output_prices {
    my $self = shift;
    
    die 'save before load prices' unless $self->{prices};

    my $out;
    if ($self->{output}) {
        open $out, '>', $self->{output}
            or die "can't open output file '$self->{output}'";
    }
    else {
        $out = \*STDOUT;
    }

    $YAML::XS::QuoteNumericStrings = 0;
    print $out YAML::XS::Dump($self->{prices});
}

sub get_input_prices {
    my $self = shift;

    my $data = YAML::XS::LoadFile($self->{input});
    return unless $data;
    merge_prices($data, $self->{prices});
}

sub get_extra_prices {
    my $self = shift;

    my $data = YAML::XS::LoadFile($self->{extra});
    return unless $data;
    merge_prices($data, $self->{prices});
}

sub merge_prices {
    my ($in, $result) = @_;

    unless ( grep ref $_ eq 'HASH', ($in, $result) ) {
        Carp::confess 'invalid args: hash-refs allowed only';
    }

    foreach my $mccmnc (keys %$in) {
        my $gates = $in->{$mccmnc};
        foreach my $gate ( keys %{$gates || {}} ) {
            $result->{$mccmnc}{$gate} = $gates->{$gate};
        }
    }
}

sub get_csv_prices {
    my $self = shift;

    return unless my $file = $self->{csv};

    open my $fh, '<', $file
        or die "can't open csv '$self->{csv}': $!";

    my @gates = @{$self->{csv_gates}};
    my $header = <$fh>;
    my $idx = 0;
    my %f = map {$_ => 1} qw/mcc mnc/, @gates;
    my @f = map $_->[1], 
                grep $f{$_->[0]}, 
                    map [lc $_ => $idx++], 
                        split /;/, $header
    ; 

    @gates = map "mt_$_", @gates;
    my $n_gates = @gates;
    my $n = 0;
    my $prices  = $self->{prices};
    while (<$fh>) {
        my ($mcc, $mnc, @gp) = (split /;/, $_)[@f];

        next if $mnc eq '';

        $n++;

        my $mccmnc = $mcc . (int $mnc ? $mnc : '');                
        foreach my $n (0..$n_gates - 1) {
            next if $gp[$n] eq '';
            $gp[$n] =~ s/,/./;
            $prices->{$mccmnc}{$gates[$n]} = $gp[$n];
        }
    }

    close $fh;

    return $n;
}


sub get_db_prices {
    my $self = shift;

    foreach my $method ( @{$self->{db_getters}} ) {
        return if $self->$method();
    }

    return;
}

sub db_get_from_ssh {
    my $self = shift;

    my ($host, $user, $dbname, $sql) = @$self{ qw/ ssh_host 
                                                   sql_user 
                                                   dbname 
                                                   sql_script
                                               /}
    ;

    my $sql_exists;
    if ($self->{write_sql}) {
        $self->write_sql_to_host();
        $sql_exists = 1;
    }

    my $cmd = qq[ssh $host 'psql -A -U $user $dbname -f $sql' 2>&1];

    my @data = qx{ $cmd };

    if ($?) {
        die "sql execute:\n" . Dumper @data 
            if $sql_exists || $data[0] !~ /No such file/i;

        warn "script '$sql' not exists on host '$host'.\ntrying to create\n";

        $self->write_sql_to_host();

        @data = qx{ $cmd };
        die "sql execute (attempt 2):\n" . Dumper @data if $?;
    }

    shift @data;
    return if $data[0] =~ /0 rows/i;
    
    pop @data;
    return merge_text_with_prices(\@data, $self->{prices});
}

sub write_sql_to_host {
    my $self = shift;

    my $file = "/tmp/$self->{sql_script}";
    open my $fh, '>', $file or die "create sql script: $!"; 
    print $fh $self->get_sql();
    close $fh;

    my $r = qx{scp $file $self->{ssh_host}:~/ 2>&1};
    my $e = $?;

    unlink $file;

    if ($e) {
        die "copy sql '$file' to '$self->{ssh_host}': $r";
    }
}

sub get_sql {
    my $self = shift;

    $self->{sql} ||= <<__SQL__;
    SELECT c.mcc, o.mnc as mccmnc, lower(g.gateway), p.price 
    FROM prices p LEFT JOIN gateways  g ON g.gateway_id  = p.gateway_id 
                  LEFT JOIN operators o ON o.operator_id = p.operator_id
                  LEFT JOIN countries c ON c.country_id  = o.country_id
    ORDER BY 1;
__SQL__
}


sub db_get_from_dump {
    my $self = shift;

    open my $fh, '<', $self->{dump} or die "open dump '$self->{dump}': $!";
    my $n = merge_text_with_prices($fh, $self->{prices});
    close $fh;
    return $n;
}

sub merge_text_with_prices {
    my ($in, $result) = @_;

    my $read = is_fh($in)         ? sub { <$in> }
             : ref $in eq 'ARRAY' ? sub { shift @$in }
             : Carp::confess '$in must be FH or array refs only'
    ;

    my $n = 0;
    while ( $_ = $read->() ) {
        next unless /^\d+\|/;
        chomp;
        $n++;
        my @row = split /\|/;
        my $mccmnc = $row[0] . (int $row[1] ? $row[1] : '');
        $result->{$mccmnc}{$row[2]} = $row[3];
    }

    return $n;
}

sub is_fh {
    my $fh = shift;
    my $fh_t = ref $fh;
    return $fh_t =~ /IO|GLOB/ 
        || $fh_t =~ /::/ && $fh_t->isa('IO::Handle') ? 1 
                                                     : 0;
}


sub db_get_from_connect {
    my $self = shift;

    my $dbh = $self->{connect}->();

    my $sth = $dbh->prepare( <<__SQL__ );
        SELECT c.mcc, o.mnc as mccmnc, lower(g.gateway), p.price 
        FROM prices p LEFT JOIN gateways  g ON g.gateway_id  = p.gateway_id 
                      LEFT JOIN operators o ON o.operator_id = p.operator_id
                      LEFT JOIN countries c ON c.country_id  = o.country_id
        ORDER BY 1;
__SQL__
    
    $sth->execute();
    
    my (%data, @row);
    $sth->bind_columns( \(@row[0..$sth->{NUM_OF_FIELDS} - 1]) );
    
    my $prices = $self->{prices};
    my $n = 0;
    while ( $sth->fetch ) {
        $n++;
        my $mccmnc = $row[0] . (int $row[1] ? $row[1] : '');
        $prices->{$mccmnc}{$row[2]} = $row[3];
    }

    return $n;
}

sub get_connect {
    my $opts = shift;

    require DBI;
    return sub {
        my $dsn = "dbi:Pg:dbname=$opts->{dbname}" 
                    . ($opts->{ssh_host} ? ";host=$opts->{ssh_host}" : '')
        ;
        DBI->connect($dsn, $opts->{sql_user}, undef, {RaiseError => 1}); 
    };
}

sub help {
    my (undef, $man) = @_;

    require Pod::Usage;
    Pod::Usage->import();

    pod2usage(-noperldoc => 1, -verbose => 1) unless $man;
    pod2usage(-noperldoc => 1, -verbose => 2) if $man;
}


1;


__DATA__

=head1 NAME

    get_prices.pl - скрипт для формирования файла с ценами операторов,
                    используемого SO::BulkGate

=head1 SYNOPSIS

 get_prices.pl [options] [file]

 get_prices.pl [--dump file] [--ssh [1 | host]] [--connect [1 | key=value,]]
               [--csv file] [--input-file] [--extra file] [--output file] 
               [--sql-user user] [--dbname dbname] [--write-sql] 
               [--help | -h | --man]

 Options:
    -help            короткое описание
    -man             полная документация 

=head1 DESCRIPTION

    B<This program> will read the given input file(s) and do something
    useful with the contents thereof.

=head1 OPTIONS

=over 8

=item B<-help>

Print a brief help message and exits.

=item B<-man>

Prints the manual page and exits.

=back


=cut
