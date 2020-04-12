#!/usr/bin/env perl

# Gus - Discord bot for the twilightzone Sven Co-op server
#
# Requires https://github.com/vsTerminus/Mojo-Discord (release v3+)
# Based on https://github.com/vsTerminus/Goose
#
# Copyright 2017-2020, Nico R. Wohlgemuth <nico@lifeisabug.com>

use v5.16.0;

use utf8;
use strict;
use warnings;

use lib '/etc/perl';

no warnings 'experimental::smartmatch';

binmode( STDOUT, ":encoding(UTF-8)" );

#use Data::Dumper;
use Mojo::Discord;
use IO::Async::Loop::Mojo;
use IO::Async::FileStream;
use DBI;
use DBD::SQLite::Constants ':file_open';
use LWP::Simple qw( $ua get );
use LWP::UserAgent;
use JSON;
use Net::SRCDS::Queries;
use IO::Interface::Simple;
use Term::Encoding qw(term_encoding);
use DateTime::TimeZone;
use Geo::Coder::Google;
use Weather::YR;
use URI::Escape;
use MaxMind::DB::Reader;
use Encode::Simple qw(encode_utf8 decode_utf8);

$ua->agent( 'Mozilla/5.0' );
$ua->timeout( 6 );

my $self;

my $config = {
   game         => 'Sven Co-op @ twlz',
   chatlinkchan => '458683388887302155',
   mainchan     => '458323696910598167',
   wufluchan    => '673626913864155187',
   kekchan      => '541343127550558228',
   ayayachan    => '459345843942588427',
   fromsven     => "$ENV{HOME}/sc5/svencoop/scripts/plugins/store/_fromsven.txt",
   tosven       => "$ENV{HOME}/sc5/svencoop/scripts/plugins/store/_tosven.txt",
   db           => "$ENV{HOME}/scstats/scstats.db",
   steamapikey  => '',
   steamapiurl  => 'https://api.steampowered.com/ISteamUser/GetPlayerSummaries/v0002/?key=XXXSTEAMAPIKEYXXX&steamids=',
   steamapiurl2 => 'https://api.steampowered.com/ISteamUser/GetPlayerBans/v1/?key=XXXSTEAMAPIKEYXXX&steamids=',
   serverport   => '27015',
   gmapikey     => '',
   geo          => "$ENV{HOME}/gus/GeoLite2-City.mmdb",
   omdbapikey   => '',

   discord => {
      client_id => '',
      owner_id  => '373912992758235148',
   }
};

my $discord = Mojo::Discord->new(
   'version'   => '9999',
   'url'       => 'https://twlz.lifeisabug.com',
   'token'     => '',
   'name'      => 'Gus',
   'reconnect' => 1,
   'verbose'   => 0,
   'logdir'    => "$ENV{HOME}/gus",
   'logfile'   => 'discord.log',
   'loglevel'  => 'info',
);

my $maps = {
   'asmap00'              => ':sheep: Azure Sheep',
   'ba_tram1'             => '<:flower:458608402549964814> HL: Blue Shift',
   'bm_nightmare_a_final' => '<:scary:516921261688094720> Black Mesa Nightmare',
   'bm_sts'               => '<:sven:459617478365020203> Black Mesa Special Tactics Sector',
   'botparty'             => '<:omegalul:458685801706815489> Bot Party',
   'botrace'              => '<:happy:555506080793493538> Bot Race',
   'echoes00'             => '<:wow:516921262199799818> HL: Echoes',
   'escape_series_1a'     => ':runner: Escape Series: Part 1',
   'escape_series_2a'     => ':runner: Escape Series: Part 2',
   'escape_series_3a'     => ':runner: Escape Series: Part 3',
   'g-ara1'               => '<:nani:603508663562272788> G-ARA',
   'hidoi_map1'           => '<:BAKA:603609334550888448> ....(^^;) Hidoi Map 1',
   'hidoi_map2'           => '<:BAKA:603609334550888448> ....(^^;) Hidoi Map 2',
   'hl_c00'               => '<:flower:458608402549964814> Half-Life',
   'island'               => ':island: Comfy, island',
   'of0a0'                => '<:flower:458608402549964814> HL: Opposing Force',
   'of_utbm'              => ':new_moon: OP4: Under the Black Moon',
   'otokotati_no_kouzan'  => ':hammer_pick: Otokotati No Kouzan',
   'pizza_ya_san1'        => ':pizza: Pizza Ya San: 1',
   'pizza_ya_san2'        => ':pizza: Pizza Ya San: 2',
   'po_c1m1'              => ':regional_indicator_p: Poke 646',
   'projectg1'            => ':dromedary_camel: Project: Guilty',
   'pv_c1m1'              => ':regional_indicator_v: Poke 646: Vendetta',
   'quad_f'               => '<:piginablanket:542462830163656764> Quad',
   'ra_quad'              => '<:piginablanket:542462830163656764> Real Adrenaline Quad',
   'ressya_no_tabi'       => ':train2::camera_with_flash: Ressya No Tabi',
   'restriction01'        => ':radioactive: Restriction',
   'road_to_shinnen'      => ':shinto_shrine: Oh god, oh no, Road to Shinnen',
   'rust_islands_b9'      => '<:eecat:460442390457483274> R U S T',
   'rust_legacy_b9'       => '<:eecat:460442390457483274> (legacy) R U S T',
   'rust_mini_b9'         => '<:eecat:460442390457483274> (mini) R U S T',
   'sa13'                 => '<:Kannasuicide:603609334080995338> SA13',
   'sc_royals1'           => ':eye: Royals',
   'sc_tl_build_puzzle_fft_final' => '<:PepeKek:603647721496248321> Build Puzzle',
   'th_ep1_01'            => '<:irlmaier:460382258336104448> They Hunger: Episode 1',
   'th_ep2_00'            => '<:irlmaier:460382258336104448> They Hunger: Episode 2',
   'th_ep3_00'            => '<:irlmaier:460382258336104448> They Hunger: Episode 3',
   'th_escape'            => '<:KannaSpook:603856338132664321> They Hunger: Escape',
   'the_daikon_warfare1'  => ':seedling: The Daikon Warfare',
   'tunnelvision_1'       => '<:zooming:640195746444083200> Tunnel Vision',
   'uboa'                 => ':rice_ball: UBOA',
};

my @winddesc = (
   'Calm',
   'Light air',
   'Light breeze',
   'Gentle breeze',
   'Moderate breeze',
   'Fresh breeze',
   'Strong breeze',
   'High wind',
   'Gale',
   'Strong gale',
   'Storm',
   'Violent storm',
   'Hurricane'
);

my $discord_markdown_pattern = qr/(?<!\\)(`|@|:|#|\||__|\*|~|>)/;

###

my $lastmap = '';

my $gi = MaxMind::DB::Reader->new(file => $$config{'geo'});

my $dbh = DBI->connect("dbi:SQLite:$$config{'db'}", undef, undef, {
   RaiseError => 1,
   sqlite_open_flags => SQLITE_OPEN_READONLY,
});

discord_on_ready();
discord_on_message_create();

$discord->init();

open my $fh, '<', $$config{'fromsven'} or die;

my $filestream = IO::Async::FileStream->new(
   read_handle => $fh,
   interval => 0.25,

   on_initial => sub {
      my ( $self ) = @_;
      $self->seek_to_last( "\n" );
   },

   on_read => sub {
      my ( $self, $buffref ) = @_;

      while ( $$buffref =~ s/^(.*\n)// )
      {
         my $line = decode_utf8($1);

         chomp( $line );

         if ( $line =~ /^status .+ [0-9][0-9]?$/ )
         {
            say localtime(time) . " -> status: $line";

            my @data = split( ' ', $line );

            $discord->status_update( { 'name' => "$data[1] @ twlz Sven Co-op", type => 0 } );

            return if ( $data[2] eq '0' );

            my $embed = {
               'color' => '15844367',
               'provider' => {
                  'name' => 'twlz',
                  'url' => 'https://twlz.lifeisabug.com',
                },
                'fields' => [
                {
                   'name'   => 'Map',
                   'value'  => "$data[1] ",
                   'inline' => \1,
                },
                {
                   'name'   => 'Players',
                   'value'  => $data[2],
                   'inline' => \1,
                },
                ],
            };

            my $message = {
               'content' => '',
               'embed' => $embed,
            };
            
            $discord->send_message( $$config{'chatlinkchan'}, $message );

            if ( exists $$maps{$data[1]} && $$maps{$data[1]} ne $lastmap )
            {
               my $s = '';
               $s = 's' if ( $data[2] > 1 );
               $discord->send_message( $$config{'mainchan'}, "**$$maps{$data[1]}** has started with **$data[2]** player$s!" );
               $lastmap = $$maps{$data[1]};
            }
         }
         else
         {
            say localtime(time) . " -> $line";

            $line =~ /<(.+?)><(.+?):.+?><(.+?)> (.+)/;
            my $nick = $1;
            my $msg  = $4;
            my $r    = $gi->record_for_address($2);

            $msg =~ s/\@+everyone/everyone/g;
            $msg =~ s/\@+here/here/g;

            $nick =~ s/`//g;
            $msg  =~ s/$discord_markdown_pattern/\\$1/g;

            my $final = "`$nick`  $msg";
            $final =~ s/^/<:gtfo:603609334781313037> / if ($line =~ /^- /);
            $final =~ s/^/<:NyanPasu:562191812702240779> / if ($line =~ /^\+ /);

            $discord->send_message( $$config{'chatlinkchan'}, ':flag_' . ($r->{country}{iso_code} ? lc($r->{country}{iso_code}) : 'white') . ': ' . $final );
         }
      }
      return 0;
   }
);

my $loop = IO::Async::Loop::Mojo->new();
$loop->add($filestream);
$loop->run unless (Mojo::IOLoop->is_running);

close $fh;
$dbh->disconnect;
exit;

###

sub discord_on_message_create
{
   $discord->gw->on('MESSAGE_CREATE' => sub
   {
      my ($gw, $hash) = @_;

      my $id = $hash->{'author'}->{'id'};
      my $author = $hash->{'author'};
      my $msg = $hash->{'content'};
      my $msgid = $hash->{'id'};
      my $channel = $hash->{'channel_id'};
      my @mentions = @{$hash->{'mentions'}};

      add_user($_) for(@mentions);

      unless ( exists $author->{'bot'} && $author->{'bot'} )
      {
         $msg =~ s/\@+everyone/everyone/g;
         $msg =~ s/\@+here/here/g;

         if ( $channel eq $$config{'chatlinkchan'} )
         {
            $msg =~ s/`//g;
            $msg =~ s/%/%%/g;
            $msg =~ s/<@(\d+)>/\@$self->{'users'}->{$1}->{'username'}/g; # user/nick
            $msg =~ s/<#(\d+)>/#$self->{'channelnames'}->{$1}/g; # channel
            $msg =~ s/<@&(\d+)>/\@$self->{'rolenames'}->{$1}/g; # role
            $msg =~ s/<(:.+:)\d+>/$1/g; # emoji

            say localtime(time) . " <- <$$author{'username'}> $msg";

            open (my $tosvenfh, '>>:encoding(UTF-8)', $$config{'tosven'}) or die;
            say $tosvenfh "(DISCORD) $$author{'username'}: $msg";
            close $tosvenfh;
         }
         elsif ( $msg =~ /^!player (.+)/i )
         {
            my $param = $1;
            my ($stmt, @bind, $r);

            my $nsa;
            $nsa = 1 if ( $channel eq $$config{'ayayachan'} );

            if ( $param =~ /^STEAM_(0:[01]:[0-9]+)$/ )
            {
               $stmt = "SELECT * FROM stats WHERE steamid = ? ORDER BY datapoints DESC, date(seen) DESC LIMIT 1";
               @bind = ( "$1" );
            }
            else
            {
               $stmt = "SELECT * FROM stats WHERE name LIKE ? ORDER BY datapoints DESC, date(seen) DESC LIMIT 1";
               @bind = ( "%$1%" );
            }

            $r = $dbh->selectrow_arrayref( $stmt, {}, @bind );

            if ( defined $r )
            {
               (my $url = $$config{'steamapiurl'} . $r->[0] ) =~ s/XXXSTEAMAPIKEYXXX/$$config{'steamapikey'}/;
               my $content = get( $url );

               unless ( defined $content )
               {
                  $discord->send_message( $channel, "`Couldn't query Steam Player API`" );
                  return;
               }

               my $result = decode_json( $content );

               (my $url2 = $$config{'steamapiurl2'} . $r->[0] ) =~ s/XXXSTEAMAPIKEYXXX/$$config{'steamapikey'}/;
               my $content2 = get( $url2 );

               unless ( defined $content2 )
               {
                  $discord->send_message( $channel, "`Couldn't query Steam Bans API`" );
                  return;
               }

               my $result2 = decode_json( $content2 );

               my $geo = Geo::Coder::Google->new(apiver => 3, language => 'en', key => $$config{'gmapikey'}, result_type => 'locality|sublocality|administrative_area_level_1|country|political');

               my $input;
               eval { $input = $geo->reverse_geocode( latlng => sprintf('%.3f,%.3f', $r->[12], $r->[13]) ) };

               my $loc = 'Unknown';
               $loc = $input->{formatted_address} if ( $input );

               my $embed = {
                  'color' => '15844367',
                  'footer' => {
                     'text' => 'STEAM_' . $r->[1],
                  },
                  'provider' => {
                     'name' => 'twlz',
                     'url' => 'https://twlz.lifeisabug.com',
                   },
                   'thumbnail' => {
                      'url' => $$result{'response'}{'players'}->[0]{avatarfull},
                   },
                   'fields' => [
                   {
                      'name'   => 'Name',
                      'value'  => "**[".decode_utf8($r->[2])."](".$$result{'response'}{'players'}->[0]{'profileurl'}." \"$$result{'response'}{'players'}->[0]{personaname}\")**",
                      'inline' => \1,
                    },
                    {
                       'name'   => 'Country',
                       'value'  => lc($r->[11]) eq 'se' ? ':gay_pride_flag:' : ':flag_'.($r->[11] ? lc($r->[11]) : 'white').':',
                       'inline' => \1,
                    },
                    {
                       'name'   => 'Time on TWLZ',
                       'value' => $r->[14] < 1 ? '-' : duration( $r->[14]*30 ) . ' +',
                       'inline' => \1,
                    },
                    {
                       'name'   => 'Last Seen',
                       'value'  => defined $r->[16] ? $r->[16] : 'Unknown',
                       'inline' => \1,
                    },
                    ],
               };

               if ( $nsa )
               {
                  if ( defined $r->[16] && ( int($r->[4]) > 0 || $r->[6] > 0 ) )
                  {
                      push @{$$embed{'fields'}}, { 'name' => 'Score', 'value' => int($r->[4]), 'inline' => \1, };
                      push @{$$embed{'fields'}}, { 'name' => 'Deaths', 'value' => $r->[6], 'inline' => \1, };
                  }

                  push @{$$embed{'fields'}}, { 'name' => 'Location', 'value' => "[GMaps](https://www.google.com/maps/\@$r->[12],$r->[13],11z)", 'inline' => \1, };
               }

               push @{$$embed{'fields'}}, { 'name' => 'VAC Bans', 'value' => $$result2{'players'}->[0]{'NumberOfVACBans'} . ' (' . duration($$result2{'players'}->[0]{'DaysSinceLastBan'}*24*60*60) . ' ago)', 'inline' => \1, } if ( $$result2{'players'}->[0]{'NumberOfVACBans'} > 0 );
               push @{$$embed{'fields'}}, { 'name' => 'Steam Community Banned', 'value' => 'Yes', 'inline' => \1, } if ( $$result2{'players'}->[0]{'CommunityBanned'} eq 'true' );

               my $message = {
                  'content' => '',
                  'embed' => $embed,
               };

               $discord->send_message( $channel, $message );
            }
            else
            {
                $discord->send_message( $channel, "`No results`" );
            }
         }
         elsif ( $msg =~ /^!stat(us|su)/i && $channel ne $$config{'wufluchan'} )
         {
            my $if       = IO::Interface::Simple->new('lo');
            my $addr     = $if->address;
            my $port     = $$config{'serverport'};
            my $ap       = "$addr:$port";
            my $encoding = term_encoding;

            my $q = Net::SRCDS::Queries->new(
               encoding => $encoding,
               timeout  => 1.5,
            );

            $q->add_server( $addr, $port );
            my $infos = $q->get_all;

            unless ( defined $$infos{$ap}{'info'} )
            {
               $discord->send_message( $channel, "`Couldn't query server`" );
            }
            else
            {
               my $diff = '';
               $diff = "  Difficulty: **$1**" if ( $$infos{$ap}{'info'}{'sname'} =~ /difficulty: (.+)/ );
               my $dmsg = "Map: **$$infos{$ap}{'info'}{'map'}**  Players: **$$infos{$ap}{'info'}{'players'}/$$infos{$ap}{'info'}{'max'}**$diff";

               $discord->send_message( $channel, $dmsg );
            }
         }
         elsif ( $msg =~ /^!w(?:eather)? (.+)/i && $channel ne $$config{'wufluchan'} )
         {
            my ($loc, $lat, $lon);
            my $alt = 0;

            my $geo = Geo::Coder::Google->new(apiver => 3, language => 'en', key => $$config{'gmapikey'});

            my $input;
            eval { $input = $geo->geocode(location => "$1") };

            unless ( $input )
            {
               $discord->send_message( $channel, '`No matching location`' );
               return;
            }

            $loc = $input->{formatted_address};
            $lat = $input->{geometry}{location}{lat};
            $lon = $input->{geometry}{location}{lng};

            my $json = get( "https://maps.googleapis.com/maps/api/elevation/json?key=$$config{'gmapikey'}&locations=" . $lat . ',' . $lon );

            if ($json)
            {
               my $elevdata;
               eval { $elevdata = decode_json($json) };
               $alt = $elevdata->{results}->[0]->{elevation} if ( $elevdata->{status} eq 'OK' );
            }

            my $flag = 'flag_white';
            for ( @{$input->{address_components}} )
            {
               $flag = 'flag_' . lc($_->{short_name}) if ( 'country' ~~ @{$_->{types}} );
            }

            my $fcloc;
            eval { $fcloc = Weather::YR->new(lat => $lat, lon => $lon, msl => int($alt), tz => DateTime::TimeZone->new(name => 'Europe/Oslo'), lang => 'en') };

            unless ($fcloc)
            {
               $discord->send_message( $channel, '`Error fetching weather data, try again later`' );
               return;
            }

            my $fc = $fcloc->location_forecast->now;

            my $beaufort   = $fc->wind_speed->beaufort;
            my $celsius    = $fc->temperature->celsius;
            my $cloudiness = $fc->cloudiness->percent;
            my $fahrenheit = $fc->temperature->fahrenheit;
            my $fog        = $fc->fog->percent;
            my $humidity   = $fc->humidity->percent;
            my $symbol     = $fc->precipitation->symbol->text;
            my $symbolid   = $fc->precipitation->symbol->number;
            my $winddir    = $fc->wind_direction->name;

            my $embed = {
               'color' => '15844367',
               'provider' => {
                  'name' => 'yr.no',
                  'url' => 'https://www.yr.no/',
                },
                'thumbnail' => {
                   'url' => "https://api.met.no/weatherapi/weathericon/1.1/?symbol=$symbolid&content_type=image/png",
                   'width' => 38,
                   'height' => 38,
                },
                'footer' => {
                   'text' => "Location altitude: " . sprintf('%dm / %dft', int($alt), int($alt * 3.2808)),
                },
                'fields' => [
                {
                   'name'   => ( $flag eq 'flag_se' ? ':gay_pride_flag:' : ":$flag:" ) . ' Weather for:',
                   'value'  => "**[$loc](https://www.google.com/maps/\@$lat,$lon,13z)**",
                   'inline' => \0,
                 },
                 {
                    'name'   => 'Temperature',
                    'value'  => sprintf('**%.1f°C** / **%.1f°F**', $celsius, $fahrenheit),
                    'inline' => \1,
                 },
                 {
                    'name'   => 'Symbol',
                    'value'  => $symbol,
                    'inline' => \1,
                 },
                 {
                    'name'   => 'Cloudiness',
                    'value'  => sprintf('%u%%', $cloudiness),
                    'inline' => \1,
                 },
                 {
                    'name'   => 'Humidity',
                    'value'  => sprintf('%u%%', $humidity),
                    'inline' => \1,
                 },
                 {
                    'name'   => 'Fog',
                    'value'  => sprintf('%u%%', $fog),
                    'inline' => \1,
                 },
                 {
                    'name'   => 'Wind',
                    'value'  => sprintf('%s from %s', $winddesc[$beaufort], $winddir),
                    'inline' => \1,
                 },
                 ],
            };

            my $message = {
               'content' => '',
               'embed' => $embed,
            };

            $discord->send_message( $channel, $message );
         }
         elsif ( $msg =~ /^!img ?(.+)?/i && $channel eq $$config{'kekchan'} )
         {
            my $type = defined $1 ? lc($1) : 'random';
            $type =~ s/ //g;

            #my @types = qw(hass hmidriff pgif 4k hentai holo hneko neko hkitsune kemonomimi anal hanal gonewild kanna ass pussy thigh hthigh gah coffee food);
            my @types = qw(hass hmidriff hentai holo hneko neko hkitsune kemonomimi hanal kanna thigh hthigh coffee food);
            $type = $types[rand @types] if ( $type eq 'random' );

            if ( $type eq 'help' || !( $type ~~ @types ) )
            {
               $discord->send_message( $channel, "`One of: @{types}`" );
               return;
            }

            my $neko = "https://nekobot.xyz/api/image?type=$type";
            my $ua = LWP::UserAgent->new( agent => 'Mozilla/5.0', timeout => 6 );
            my $r = $ua->get( $neko, 'Content-Type' => 'application/json' );
            unless ( $r->is_success )
            {
               $discord->send_message( $channel,  '`Error fetching data`' );
               return;
            }
            my $i = from_json ( $r->decoded_content );

            if ( defined $$i{success} && $$i{success} )
            {
               $discord->send_message( $channel, $$i{message} );
            }
            else
            {
               $discord->send_message( $channel,  '`Error fetching data`' );
            }
         }
         elsif ( $msg =~ /^!ud (.+)/i && $channel eq $$config{'kekchan'} )
         {
            my $input = $1;
            my $query = uri_escape( $input );
            my $ua = LWP::UserAgent->new( agent => 'Mozilla/5.0', timeout => 6 );
            $ua->agent( ssl_opts => { verify_hostname => 0 } );
            my $r = $ua->get( "https://api.urbandictionary.com/v0/define?term=$query", 'Content-Type' => 'application/json' );
            unless ( $r->is_success )
            {
               $discord->send_message( $channel,  '`Error fetching data`' );
               return;
            }
            my $ud = decode_json ( $r->decoded_content );

            if ( !defined $$ud{error} && defined $$ud{list} )
            {
               if ( defined $$ud{list}[0]{definition} )
               {
                   my $res = '';

                   for (0..3)
                   {
                      $$ud{list}[$_]{definition} =~ s/\s+/ /g;
                      $res .= sprintf("(%d) %s:: %s\n", $_+1, (lc($$ud{list}[$_]{word}) ne lc($input)) ? $$ud{list}[$_]{word} . ' ' : '', (length($$ud{list}[$_]{definition}) > 665) ? substr($$ud{list}[$_]{definition}, 0, 666) . '...' : $$ud{list}[$_]{definition});
                      last unless (defined $$ud{list}[$_+1]{definition});
                   }

                   $discord->send_message( $channel, "```$res```" );
               }
               else
               {
                  $discord->send_message( $channel, '`No match`' );
               }
            }
            else
            {
               $discord->send_message( $channel, '`Error fetching data`' );
            }
         }
         elsif ( $msg =~ /^!(ncov|waiflu|wuflu|virus|corona)/i && $channel eq $$config{'wufluchan'} )
         {
            my $ncov = 'https://raw.githubusercontent.com/montanaflynn/covid-19/master/data/current.json';
            my $ua = LWP::UserAgent->new( agent => 'Mozilla/5.0', timeout => 6 );
            my $r = $ua->get( $ncov, 'Content-Type' => 'application/json' );
            unless ( $r->is_success )
            {
               $discord->send_message( $channel,  '`Error fetching data`' );
               return;
            }
            my $i = from_json ( $r->decoded_content );

            if ( defined $$i{global} )
            {
               my ($confirmed, $deaths, $recovered, $updated) = (0, 0, 0, 0);

               for ( keys %{$$i{global}} )
               {
                  $confirmed += $$i{global}{$_}{confirmed};
                  $deaths    += $$i{global}{$_}{deaths};
                  $recovered += $$i{global}{$_}{recovered};
                  $updated    = $$i{global}{$_}{updated} if ( $$i{global}{$_}{updated} > $updated );
               }

               my $embed = {
                  'color' => '15158332',
                  'provider' => {
                     'name' => 'Berliner Morgenpost',
                     'url' => 'https://interaktiv.morgenpost.de/corona-virus-karte-infektionen-deutschland-weltweit/',
                   },
                   'title' => '2019-nCoV / SARS-CoV-2 / COVID-19',
                   'url' => 'https://bnonews.com/index.php/2020/02/the-latest-coronavirus-cases/',
                   'thumbnail' => {
                      'url' => 'https://cdn.discordapp.com/attachments/673626913864155187/677160782844133386/e1epICE.png',
                   },
                   'footer' => {
                      'text' => 'Last updated ' . duration( time-substr($updated, 0, -3) ) . ' ago.',
                   },
                   'fields' => [
                    {
                       'name'   => ':earth_africa: **Worldwide**',
                       'value'  => "**Infected:** $confirmed (**Currently:** " . ($confirmed-$deaths-$recovered) . ") **Deaths:** $deaths (" . sprintf('%.2f', ($deaths/$confirmed)*100) . "%) **Recovered:** $recovered",
                       'inline' => \1,
                    },
                    {
                       'name'   => ':flag_us: **United States of America**',
                       'value'  => "**I:** $$i{global}{'United States'}{confirmed} (**C:** " . ($$i{global}{'United States'}{confirmed}-$$i{global}{'United States'}{deaths}-$$i{global}{'United States'}{recovered}) . ") **D:** $$i{global}{'United States'}{deaths} (" . sprintf('%.2f', ($$i{global}{'United States'}{deaths}/$$i{global}{'United States'}{confirmed})*100) . "%) **R:** $$i{global}{'United States'}{recovered}",
                       'inline' => \0,
                    },
                    {
                       'name'   => ':flag_es: **Spain**',
                       'value'  => "**I:** $$i{global}{Spain}{confirmed} (**C:** " . ($$i{global}{Spain}{confirmed}-$$i{global}{Spain}{deaths}-$$i{global}{Spain}{recovered}) . ") **D:** $$i{global}{Spain}{deaths} (" . sprintf('%.2f', ($$i{global}{Spain}{deaths}/$$i{global}{Spain}{confirmed})*100) . "%) **R:** $$i{global}{Spain}{recovered}",
                       'inline' => \0,
                    },
                    {
                       'name'   => ':flag_it: **Italy**',
                       'value'  => "**I:** $$i{global}{Italy}{confirmed} (**C:** " . ($$i{global}{Italy}{confirmed}-$$i{global}{Italy}{deaths}-$$i{global}{Italy}{recovered}) . ") **D:** $$i{global}{Italy}{deaths} (" . sprintf('%.2f', ($$i{global}{Italy}{deaths}/$$i{global}{Italy}{confirmed})*100) . "%) **R:** $$i{global}{Italy}{recovered}",
                       'inline' => \0,
                    },
                    {
                       'name'   => ':flag_de: **Germany**',
                       'value'  => "**I:** $$i{global}{Germany}{confirmed} (**C:** " . ($$i{global}{Germany}{confirmed}-$$i{global}{Germany}{deaths}-$$i{global}{Germany}{recovered}) . ") **D:** $$i{global}{Germany}{deaths} (" . sprintf('%.2f', ($$i{global}{Germany}{deaths}/$$i{global}{Germany}{confirmed})*100) . "%) **R:** $$i{global}{Germany}{recovered}",
                       'inline' => \0,
                    },
                    {
                       'name'   => ':flag_fr: **France**',
                       'value'  => "**I:** $$i{global}{France}{confirmed} (**C:** " . ($$i{global}{France}{confirmed}-$$i{global}{France}{deaths}-$$i{global}{France}{recovered}) . ") **D:** $$i{global}{France}{deaths} (" . sprintf('%.2f', ($$i{global}{France}{deaths}/$$i{global}{France}{confirmed})*100) . "%) **R:** $$i{global}{France}{recovered}",
                       'inline' => \0,
                    },
                    {
                       'name'   => ':flag_ir: **Iran**',
                       'value'  => "**I:** $$i{global}{Iran}{confirmed} (**C:** " . ($$i{global}{Iran}{confirmed}-$$i{global}{Iran}{deaths}-$$i{global}{Iran}{recovered}) . ") **D:** $$i{global}{Iran}{deaths} (" . sprintf('%.2f', ($$i{global}{Iran}{deaths}/$$i{global}{Iran}{confirmed})*100) . "%) **R:** $$i{global}{Iran}{recovered}",
                       'inline' => \0,
                    },
                    {
                       'name'   => ':flag_gb: **United Kingdom**',
                       'value'  => "**I:** $$i{global}{'United Kingdom'}{confirmed} (**C:** " . ($$i{global}{'United Kingdom'}{confirmed}-$$i{global}{'United Kingdom'}{deaths}-$$i{global}{'United Kingdom'}{recovered}) . ") **D:** $$i{global}{'United Kingdom'}{deaths} (" . sprintf('%.2f', ($$i{global}{'United Kingdom'}{deaths}/$$i{global}{'United Kingdom'}{confirmed})*100) . "%) **R:** $$i{global}{'United Kingdom'}{recovered}",
                       'inline' => \1,
                    },
                    {
                       'name'   => ':flag_tr: **Turkey**',
                       'value'  => "**I:** $$i{global}{Turkey}{confirmed} (**C:** " . ($$i{global}{Turkey}{confirmed}-$$i{global}{Turkey}{deaths}-$$i{global}{Turkey}{recovered}) . ") **D:** $$i{global}{Turkey}{deaths} (" . sprintf('%.2f', ($$i{global}{Turkey}{deaths}/$$i{global}{Turkey}{confirmed})*100) . "%) **R:** $$i{global}{Turkey}{recovered}",
                       'inline' => \1,
                    },
                    {
                       'name'   => ':flag_be: **Belgium**',
                       'value'  => "**I:** $$i{global}{Belgium}{confirmed} (**C:** " . ($$i{global}{Belgium}{confirmed}-$$i{global}{Belgium}{deaths}-$$i{global}{Belgium}{recovered}) . ") **D:** $$i{global}{Belgium}{deaths} (" . sprintf('%.2f', ($$i{global}{Belgium}{deaths}/$$i{global}{Belgium}{confirmed})*100) . "%) **R:** $$i{global}{Belgium}{recovered}",
                       'inline' => \1,
                    },
                    {
                       'name'   => ':flag_ch: **Switzerland**',
                       'value'  => "**I:** $$i{global}{Switzerland}{confirmed} (**C:** " . ($$i{global}{Switzerland}{confirmed}-$$i{global}{Switzerland}{deaths}-$$i{global}{Switzerland}{recovered}) . ") **D:** $$i{global}{Switzerland}{deaths} (" . sprintf('%.2f', ($$i{global}{Switzerland}{deaths}/$$i{global}{Switzerland}{confirmed})*100) . "%) **R:** $$i{global}{Switzerland}{recovered}",
                       'inline' => \1,
                    },
                    {
                       'name'   => ':flag_nl: **Netherlands**',
                       'value'  => "**I:** $$i{global}{Netherlands}{confirmed} (**C:** " . ($$i{global}{Netherlands}{confirmed}-$$i{global}{Netherlands}{deaths}-$$i{global}{Netherlands}{recovered}) . ") **D:** $$i{global}{Netherlands}{deaths} (" . sprintf('%.2f', ($$i{global}{Netherlands}{deaths}/$$i{global}{Netherlands}{confirmed})*100) . "%) **R:** $$i{global}{Netherlands}{recovered}",
                       'inline' => \1,
                    },
                    {
                       'name'   => ':flag_ca: **Canada**',
                       'value'  => "**I:** $$i{global}{Canada}{confirmed} (**C:** " . ($$i{global}{Canada}{confirmed}-$$i{global}{Canada}{deaths}-$$i{global}{Canada}{recovered}) . ") **D:** $$i{global}{Canada}{deaths} (" . sprintf('%.2f', ($$i{global}{Canada}{deaths}/$$i{global}{Canada}{confirmed})*100) . "%) **R:** $$i{global}{Canada}{recovered}",
                       'inline' => \1,
                    },
                    {
                       'name'   => ':flag_br: **Brazil**',
                       'value'  => "**I:** $$i{global}{Brazil}{confirmed} (**C:** " . ($$i{global}{Brazil}{confirmed}-$$i{global}{Brazil}{deaths}-$$i{global}{Brazil}{recovered}) . ") **D:** $$i{global}{Brazil}{deaths} (" . sprintf('%.2f', ($$i{global}{Brazil}{deaths}/$$i{global}{Brazil}{confirmed})*100) . "%) **R:** $$i{global}{Brazil}{recovered}",
                       'inline' => \1,
                    },
                    {
                       'name'   => ':flag_at: **Austria**',
                       'value'  => "**I:** $$i{global}{Austria}{confirmed} (**C:** " . ($$i{global}{Austria}{confirmed}-$$i{global}{Austria}{deaths}-$$i{global}{Austria}{recovered}) . ") **D:** $$i{global}{Austria}{deaths} (" . sprintf('%.2f', ($$i{global}{Austria}{deaths}/$$i{global}{Austria}{confirmed})*100) . "%) **R:** $$i{global}{Austria}{recovered}",
                       'inline' => \1,
                    },
                    {
                       'name'   => ':flag_pt: **Portugal**',
                       'value'  => "**I:** $$i{global}{Portugal}{confirmed} (**C:** " . ($$i{global}{Portugal}{confirmed}-$$i{global}{Portugal}{deaths}-$$i{global}{Portugal}{recovered}) . ") **D:** $$i{global}{Portugal}{deaths} (" . sprintf('%.2f', ($$i{global}{Portugal}{deaths}/$$i{global}{Portugal}{confirmed})*100) . "%) **R:** $$i{global}{Portugal}{recovered}",
                       'inline' => \1,
                    },
                    {
                       'name'   => ':flag_kr: **South Korea**',
                       'value'  => "**I:** $$i{global}{'South Korea'}{confirmed} (**C:** " . ($$i{global}{'South Korea'}{confirmed}-$$i{global}{'South Korea'}{deaths}-$$i{global}{'South Korea'}{recovered}) . ") **D:** $$i{global}{'South Korea'}{deaths} (" . sprintf('%.2f', ($$i{global}{'South Korea'}{deaths}/$$i{global}{'South Korea'}{confirmed})*100) . "%) **R:** $$i{global}{'South Korea'}{recovered}",
                       'inline' => \1,
                    },
                    {
                       'name'   => ':flag_il: **Israel**',
                       'value'  => "**I:** $$i{global}{Israel}{confirmed} (**C:** " . ($$i{global}{Israel}{confirmed}-$$i{global}{Israel}{deaths}-$$i{global}{Israel}{recovered}) . ") **D:** $$i{global}{Israel}{deaths} (" . sprintf('%.2f', ($$i{global}{Israel}{deaths}/$$i{global}{Israel}{confirmed})*100) . "%) **R:** $$i{global}{Israel}{recovered}",
                       'inline' => \1,
                    },
                    {
                       'name'   => ':flag_ru: **Russia**',
                       'value'  => "**I:** $$i{global}{Russia}{confirmed} (**C:** " . ($$i{global}{Russia}{confirmed}-$$i{global}{Russia}{deaths}-$$i{global}{Russia}{recovered}) . ") **D:** $$i{global}{Russia}{deaths} (" . sprintf('%.2f', ($$i{global}{Russia}{deaths}/$$i{global}{Russia}{confirmed})*100) . "%) **R:** $$i{global}{Russia}{recovered}",
                       'inline' => \1,
                    },
                    ],
               };
               my $message = {
                  'content' => '',
                  'embed' => $embed,
               };

               $discord->send_message( $channel, $message );
            }
            else {
               $discord->send_message( $channel,  '`Error fetching data`' );
            }

         }
         elsif ( $msg =~ /^!xon(?:stat)?s? (.+)/i && $channel ne $$config{'wufluchan'} )
         {
            my ($qid, $stats);
            ($qid = $1) =~ s/[^0-9]//g;

            unless ($qid) {
               $discord->send_message( $channel, 'Invalid player ID');
               return;
            }

            my $xonstaturl = 'https://stats.xonotic.org/player/';
            my $json = get( $xonstaturl . $qid . '.json');

            if ($json) {
               eval { $stats = decode_json($json) };
            }
            else {
               $discord->send_message( $channel, 'No response from server; Correct player ID?');
               return;
            }

            my $snick   = $stats->[0]->{player}->{stripped_nick};
            my $games   = $stats->[0]->{games_played}->{overall}->{games};
            my $win     = $stats->[0]->{games_played}->{overall}->{wins};
            my $loss    = $stats->[0]->{games_played}->{overall}->{losses};
            my $pct     = $stats->[0]->{games_played}->{overall}->{win_pct};
            my $kills   = $stats->[0]->{overall_stats}->{overall}->{total_kills};
            my $deaths  = $stats->[0]->{overall_stats}->{overall}->{total_deaths};
            my $ratio   = $stats->[0]->{overall_stats}->{overall}->{k_d_ratio};
            my $elo     = $stats->[0]->{elos}->{overall}->{elo} ? $stats->[0]->{elos}->{overall}->{elo}          : 0;
            my $elot    = $stats->[0]->{elos}->{overall}->{elo} ? $stats->[0]->{elos}->{overall}->{game_type_cd} : 0;
            my $elog    = $stats->[0]->{elos}->{overall}->{elo} ? $stats->[0]->{elos}->{overall}->{games}        : 0;
            my $capr    = $stats->[0]->{overall_stats}->{ctf}->{cap_ratio} ? $stats->[0]->{overall_stats}->{ctf}->{cap_ratio} : 0;
            my $favmap  = $stats->[0]->{fav_maps}->{overall}->{map_name};
            my $favmapt = $stats->[0]->{fav_maps}->{overall}->{game_type_cd};
            my $lastp   = $stats->[0]->{overall_stats}->{overall}->{last_played_fuzzy};

            my $embed = {
               'color' => '15844367',
               'provider' => {
                  'name' => 'XonStat',
                  'url' => 'https://stats.xonotic.org',
                },
#               'thumbnail' => {
#                  'url' => "https://cdn.discordapp.com/emojis/458355320364859393.png?v=1",
#                  'width' => 38,
#                  'height' => 38,
#               },
                'image' => {
                   'url' => "https://stats.xonotic.org/static/badges/$qid.png?" . time, # work around discord image caching
                   'width' => 650,
                   'height' => 70,
                },
                'footer' => {
                   'text' => "Last played: $lastp",
                },
                'fields' => [
                 {
                    'name'   => 'Name',
                    'value'  => "**[$snick]($xonstaturl$qid)**",
                    'inline' => \1,
                 },
                 {
                    'name'   => 'Games Played',
                    'value'  => $games,
                    'inline' => \1,
                 },
                 {
                    'name'   => 'Favourite Map',
                    'value'  => sprintf('%s (%s)', $favmap, $favmapt),
                    'inline' => \1,
                 },
                 {
                    'name'   => 'Cap Ratio',
                    'value'  => $capr ? sprintf('%.2f', $capr) : '-',
                    'inline' => \1,
                 },
                 ],
            };

            my $message = {
               'content' => '',
               'embed' => $embed,
            };

            $discord->send_message( $channel, $message );

   #     main::msg($target, "%s :: games: %d/%d/%d (%.2f%% win) :: k/d: %.2f (%d/%d)%s :: fav map: %s (%s) :: last played %s", $snick, $games, $win, $loss, $pct, $ratio, $kills, $deaths, ($elo && $elo ne 100) ? sprintf(' :: %s elo: %.2f (%d games%s)', $elot, $elo, $elog, $elot eq 'ctf' ? sprintf(', %.2f cr', $capr) : '' ) : '', $favmap, $favmapt, $last);
         }
         elsif ( $msg =~ /^!(?:[io]mdb|movie) (.+)/i && $channel ne $$config{'wufluchan'} )
         {
            my @args = split(/ /, $1);
            my $year;
            $year = pop(@args) if ($args[-1] =~ /^\(?\d{4}\)?$/);
            $year =~ s/[^\d]//g;
            my $title = join ' ', @args;

            my $type = 't';
            $type = 'i' if ($title =~ /(tt\d{7,8})/);

            my $url = 'http://www.omdbapi.com/?apikey=' . $$config{'omdbapikey'};
            $url .= '&' . $type . '=' . $title;
            $url .= '&y=' . $year if ($year);

            my $ua = LWP::UserAgent->new( agent => 'Mozilla/5.0', timeout => 6 );
            my $r = $ua->get( $url, 'Content-Type' => 'application/json' );
            unless ( $r->is_success )
            {
               $discord->send_message( $channel,  '`Error fetching data`' );
               return;
            }
            my $omdb = decode_json ( $r->decoded_content );

            if ($$omdb{Response} eq 'True')
            {
               my $footer = '';
               $footer .= "Rated: $$omdb{Rated}"         unless ( $$omdb{Rated}    eq 'N/A' );
               $footer .= "; Country: $$omdb{Country}"   unless ( $$omdb{Country}  eq 'N/A' );
               $footer .= "; Language: $$omdb{Language}" unless ( $$omdb{Language} eq 'N/A' );
               $footer .= "; Writer: $$omdb{Writer}"     unless ( $$omdb{Writer}   eq 'N/A' );
               $footer .= "; Director: $$omdb{Director}" unless ( $$omdb{Director} eq 'N/A' );
               $footer .= "; Awards: $$omdb{Awards}"     unless ( $$omdb{Awards}   eq 'N/A' );
               substr($footer, 0, 2, '')                 if     ( $$omdb{Rated}    eq 'N/A' );

               my $embed = {
                  'color' => '15844367',
                  'provider' => {
                     'name' => 'OMDB',
                     'url'  => 'https://www.omdbapi.com',
                   },
                   'title' => $$omdb{Title} . ($$omdb{Type} eq 'series' ? ' (TV Series)' : ''),
                   'url'   => "https://imdb.com/title/$$omdb{imdbID}/",
                   'footer' => {
                      'text' => $footer,
                   },
                   'fields' => [
                    {
                       'name'   => 'Year',
                       'value'  => $$omdb{Year},
                       'inline' => \1,
                    },
                    {
                       'name'   => 'Runtime',
                       'value'  => $$omdb{Runtime} . ($$omdb{Type} eq 'series' ? ' (per EP)' : ''),
                       'inline' => \1,
                    },
                    {
                       'name'   => 'Genre',
                       'value'  => $$omdb{Genre},
                       'inline' => \1,
                    },
                    ],
               };

               $$embed{image} = { 'url' => $$omdb{Poster}, } unless ( $$omdb{Poster} eq 'N/A' );

               push @{$$embed{'fields'}}, { 'name' => 'Actors',      'value' => $$omdb{Actors},                                    'inline' => \1, } unless ( $$omdb{Actors}     eq 'N/A' );
               push @{$$embed{'fields'}}, { 'name' => 'Plot',        'value' => $$omdb{Plot},                                      'inline' => \0, } unless ( $$omdb{Plot}       eq 'N/A' );
               push @{$$embed{'fields'}}, { 'name' => 'IMDB Rating', 'value' => "$$omdb{imdbRating}/10 ($$omdb{imdbVotes} votes)", 'inline' => \1, } unless ( $$omdb{imdbRating} eq 'N/A' );
               push @{$$embed{'fields'}}, { 'name' => 'Metascore',   'value' => "$$omdb{Metascore}/100",                           'inline' => \1, } unless ( $$omdb{Metascore}  eq 'N/A' );
               push @{$$embed{'fields'}}, { 'name' => 'Seasons',     'value' => $$omdb{totalSeasons},                              'inline' => \1, }     if ( $$omdb{Type}       eq 'series' );

               my $message = {
                  'content' => '',
                  'embed' => $embed,
               };

               $discord->send_message( $channel, $message );
            }
            else
            {
               $discord->send_message( $channel,  '`No match`' );
            }
         }
         elsif ( $msg =~ /^((?:\[\s\]\s[^\[\]]+\s?)+)/ )
         {
            my @x;

            $msg =~ s/`//g;
            $msg =~ s/(\[\s\]\s[^\[\]]+)+?\s?/push @x,$1/eg;
            $x[int(rand(@x))] =~ s/\[\s\]/[x]/;

            $discord->send_message( $channel, "`@x`" );
         }
      }
   });

   return;
}


sub discord_on_ready
{
   $discord->gw->on('READY' => sub
   {
      my ($gw, $hash) = @_;
      add_me($hash->{'user'});
      $discord->status_update( { 'name' => $$config{'game'}, type => 0 } ) if ( $$config{'game'} );
   });

   return;
}

sub add_me
{
   my ($user) = @_;
   $self->{'id'} = $user->{'id'};
   add_user($user);

   return;
}

sub add_user
{
   my ($user) = @_;
   my $id = $user->{'id'};
   $self->{'users'}{$id} = $user;

   return;
}

sub add_guild
{
   my ($guild) = @_;

   $self->{'guilds'}{$guild->{'id'}} = $guild;

   foreach my $channel (@{$guild->{'channels'}})
   {
      $self->{'channels'}{$channel->{'id'}} = $guild->{'id'};
      $self->{'channelnames'}{$channel->{'id'}} = $channel->{'name'}
   }

   foreach my $role (@{$guild->{'roles'}})
   {
      $self->{'rolenames'}{$role->{'id'}} = $role->{'name'};
   }

   return;
}

sub duration
{
   my $sec = shift || return 0;

   my @gmt = gmtime($sec);

   $gmt[5] -= 70;
   return   ($gmt[5] ?                                                       $gmt[5].'y' : '').
            ($gmt[7] ? ($gmt[5]                                  ? ' ' : '').$gmt[7].'d' : '').
            ($gmt[2] ? ($gmt[5] || $gmt[7]                       ? ' ' : '').$gmt[2].'h' : '').
            ($gmt[1] ? ($gmt[5] || $gmt[7] || $gmt[2]            ? ' ' : '').$gmt[1].'m' : '');
}
