#!/usr/bin/env perl

BEGIN {
    $ENV{'TZ'} = 'America/Chicago';
    require POSIX;
    POSIX::tzset();
}

use Find::Lib 'lib';

use Winobot;

Winobot::run();
