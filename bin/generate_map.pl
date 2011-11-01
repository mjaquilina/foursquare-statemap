#!/usr/bin/perl

use Modern::Perl;

use Geography::States qw();
use Data::Dumper      qw();
use Data::ICal        qw();
use DBM::Deep         qw();
use File::Slurp       qw(slurp write_file);
use Getopt::Long      qw(GetOptions);
use JSON              qw(decode_json);
use LWP::Simple       qw(get);

my $debug      = 0;
my $key        = '';
my $cache_file = '';
my $local_file = '';

GetOptions(
    'debug'        => \$debug,
    'key=s'        => \$key,
    'cache_file=s' => \$cache_file,
    'ics_file=s'   => \$local_file,
);

die "A Foursquare secret key must be provided unless running against a local ICS file"
    if (!$key and !$local_file);

my $state_map = Geography::States->new('USA');

my %cache;
if ($cache_file) {
    warn $cache_file;
    tie %cache, 'DBM::Deep', $cache_file;
}

my %states;
my @checkins = get_checkins();
for my $checkin (@checkins) {
    my $state = get_state($checkin->{lat}, $checkin->{long});    
    $states{$state}++;
}

print q|<script type="text/javascript">
    $(function(){
        $('#foursquare_map').vectorMap({
            map: 'usa_en',
            colors: {
|;

my $i      = 0;
my @states = keys %states;
for my $state (@states)  {
    print "    " x 4;
    print lc $state . ": black";
    print "," unless $i == $#states;
    print "\n";
    $i++;
}

print q|
            }
        });
    });
</script>
<div id="foursquare_map"></div>
|;

sub get_checkins {
    my $ics_data;
    if ($local_file and -e $local_file) {
        warn "Slurping $local_file" if $debug;
        $ics_data = slurp($local_file);
    } else {
        warn "Retrieving ICS from Foursquare" if $debug;
        $ics_data = get("https://feeds.foursquare.com/history/$key.ics");
    }

    my $calendar = Data::ICal->new(data => $ics_data);
    my @entries  = @{ $calendar->entries };

    my @checkins;
    for my $entry (@entries) {
        my $props = $entry->properties;
        my $name  = $props->{location}[0] ? $props->{location}[0]->value : '';
        my $geo   = $props->{geo}[0]->value;
        my ($lat, $long) = split(';', $geo);

        # nationwide event, but shows up as Texas
        next if $name eq 'Super Bowl Sunday';

        push @checkins, {
            name => $name,
            lat  => $lat,
            long => $long,
        };
    }

    return @checkins;
}

sub get_state {
    my ($lat, $long) = @_;

    return $cache{$lat.$long} if $cache{$lat.$long};

    my $json     = get("http://nominatim.openstreetmap.org/reverse?format=json&lon=$long&lat=$lat");
    my $geo_data = decode_json($json);

    $cache{$lat.$long}   = $geo_data->{address}{state};
    ($cache{$lat.$long}) = $state_map->state($cache{$lat.$long});

    return $cache{$lat.$long};
}

