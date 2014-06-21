package SO::BulkGate::Router::Gate;

sub PARAMS() { qw/smsc user pass/ }

use Class::XSAccessor
    getters => [ qw/id name smsc user pass url encoding/ ],
    constructor => 'new',
;


sub params {
    return {
        map {$_ => $_[0]->$_} grep defined $_[0]->$_, PARAMS 
    }
}


1;
