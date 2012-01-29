package Winobot::DD;

use strict;
use warnings;

sub import {
    strict->import();
    warnings->import();

    require utf8;
    utf8->import();

    require feature;
    feature->import(':5.10');

    require mro;
    mro->import();
    mro::set_mro(scalar(caller()), 'c3');

    no indirect;
    indirect->unimport(':FATAL');

    no autovivification;
    autovivification->unimport('exists');

    return;
}

1;
