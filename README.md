# About #

winobot is an Perl based IRC bot built on [AnyEvent::IRC](https://metacpan.org/module/AnyEvent::IRC) and [Moose](https://metacpan.org/module/Moose). The name "winobot" comes from [Wonder Showzen](en.wikipedia.org/wiki/Wonder_Showzen) a short lived TV show on MTV2. [Watch](http://www.youtube.com/watch?v=67YfJyc_rew) the skit.

# Features #

* Likes to party
* Built on [AnyEvent](https://metacpan.org/module/AnyEvent)
* Configuration file driven (built on [Thorium](https://metacpan.org/module/Thorium))
* [MongoDB](http://mongodb.org) is the backing store for Features
* Markov Chain's via [Hailo](https://metacpan.org/module/Hailo) (must load feature)
* Automatic condensing of URL's with TinyURL (must load feature)
* Twitter feed monitoring from Stream API (must load feature and requires API keys)
* Supports encrypted rooms via [Algorithm::IRCSRP2](https://metacpan.org/module/Algorithm::IRCSRP2) (must load feature)
* Utility features such as Date, Echo, Help, LoadUnload, Uptime, etc (must load features)

# Quirks #

* Missing documentation for configuration and feature use
* CPAN dependency heavy
* Lots on the TODO list
* No runtime configuration altering / reloading
* No runtime admin interface
* Logging must be turned on, see [Thorium::Log](https://metacpan.org/module/Thorium::Log) (there should be a command line option for this)
* No initial data is loaded into database (insult, praises, etc)

# Installation #

## Dependencies ##

###  Perl 5.14+ ###

Use [perlbrew](https://metacpan.org/module/perlbrew) to make this hassle free.

###  CPAN Modules For core ###

Use [cpanm](https://metacpan.org/module/cpanm) to make this hassle free.

* AnyEvent
* AnyEvent::HTTP
* AnyEvent::IRC
* AnyEvent::Worker
* Class::MOP
* Class::Unload
* Dir::Self
* Find::Lib
* Hailo
* List::MoreUtils
* Math::Random::Secure
* MongoDB
* Moose
* Regexp::Common
* Sub::Exporter
* Text::ASCIITable::Wrap
* Thorium
* Try::Tiny
* autovivification
* indirect

### CPAN Modules For Features ###

* Algorithm::IRCSRP2
* AnyEvent::HTTP
* AnyEvent::Twitter
* AnyEvent::Twitter::Stream
* Array::Diff
* DateTime
* Email::Send
* Email::Simple
* HTML::Extract
* Hailo
* JSON::XS
* Math::Random::ISAAC::XS
* Math::Random::Secure
* Memory::Usage
* Net::FTP
* Net::OAuth
* Net::SSLeay
* Regexp::Common
* Roman::Unicode
* Text::ASCIITable::Wrap
* Time::Duration
* Try::Tiny
* XML::LibXML

### MongoDB ###

Any reasonably recent version will do.

## Checkout / Install / Run ##

    $ cpanm <huge-list-of-dependencies>
    $ git clone git://github.com/aflott/winobot.git
    $ cd winobot
    $ # create a preset in conf/presets
    $ ./configure --load the-preset-name-you-chose-minus-the-dot-yaml-ext
    $ ./winobot.pl

# TODO #

## core ##

1. turn `$id` into a proper object
1. access control / admin interface
1. make `$state->conf` a role in `Winobot::State`, then eliminate use of get\_feature\_option
1. `load <name>` produces pass when module was not loaded
1. reconnect ability
1. add $state->db role
1. use AnyEvent version of MongoDB
1. add unix signals with anyevent
1. make features reloadable per channel? futzing with namespaces might do it?
1. restore handler functionality for channel-less events (disconnect, connect, etc)
1. add time zone to `defaults.yaml` instead of `winobot.pl`

## Features ##

### SRP ###

1. automatic srp'ing on connect / join / reconnect
1. handle multiple channels, servers

## Thorium ##

1. when no files are processed, dont output "No config files processed!" when local.yaml was actually generated. maybe change to "No template files processed!"?
1. don't use Proc::ProcessTable

## Hobocamp ##

1. compile fixes for OSX
