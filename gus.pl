#!/usr/bin/env perl

# Gus - Discord bot for the twilightzone Sven Co-op server
#
# Based on https://github.com/vsTerminus/Goose
#
# Copyright 2017-2019, Nico R. Wohlgemuth <nico@lifeisabug.com>

use v5.16.0;

use utf8;
use strict;
use warnings;

use lib '/etc/perl';

no warnings 'experimental::smartmatch';

binmode( STDOUT, ":utf8" );

#use Data::Dumper;
use Mojo::Discord;
use IO::Async::Loop::Mojo;
use IO::Async::FileStream;
use DBI;
use DBD::SQLite::Constants ':file_open';
use LWP::Simple '!head';
use JSON;
use Net::SRCDS::Queries;
use IO::Interface::Simple;
use Term::Encoding qw(term_encoding);
use DateTime::TimeZone;
use Geo::Coder::Google;
use Weather::YR;
use URI::Escape;
use MaxMind::DB::Reader;

my $self;
my $lastmap = '';

my $config = {
   chatlinkchan => '458683388887302155',
   mainchan     => '458323696910598167',
   kekchan      => '541343127550558228',
   adminrole    => '',
   fromsven     => "$ENV{HOME}/sc5/svencoop/scripts/plugins/store/_fromsven.txt",
   tosven       => "$ENV{HOME}/sc5/svencoop/scripts/plugins/store/_tosven.txt",
   db           => "$ENV{HOME}/scstats/scstats.db",
   steamapikey  => '',
   steamapiurl  => 'https://api.steampowered.com/ISteamUser/GetPlayerSummaries/v0002/?key=XXXSTEAMAPIKEYXXX&steamids=',
   steamapiurl2 => 'https://api.steampowered.com/ISteamUser/GetPlayerBans/v1/?key=XXXSTEAMAPIKEYXXX&steamids=',
   serverport   => '27015',
   gmapikey     => '',
   xonstaturl   => 'https://stats.xonotic.org/player/',
   geo          => '/usr/share/GeoIP/GeoLite2-City.mmdb',

   discord => {
     client_id => '',
     owner_id => '373912992758235148',
   }
};

my $discord = Mojo::Discord->new(
   'version'   => '9999',
   'url'       => 'https://twlz.lifeisabug.com',
   'token'     => '',
   'name'      => 'Gus',
   'reconnect' => 1,
   'verbose'   => 0,
   'game'      => 'Sven Co-op @ twlz',
   'callbacks' => {
     'READY'          => sub { discord_on_ready(shift) },
     'GUILD_CREATE'   => sub { discord_on_guild_create(shift) },
     'MESSAGE_CREATE' => sub { discord_on_message_create(shift) },
     'MESSAGE_UPDATE' => sub { discord_on_message_update(shift) },
   },
);

my $maps = {
   'hl_c01_a1' => '<:flower:458608402549964814> Half-Life',
   'of1a1' => '<:flower:458608402549964814> Opposing Force',
   'ba_security1' => '<:flower:458608402549964814> Blue Shift',
   'escape_series_1a' => '<:sven:459617478365020203> Escape Series: Part 1',
   'escape_series_2a' => '<:sven:459617478365020203> Escape Series: Part 2',
   'escape_series_3a' => '<:sven:459617478365020203> Escape Series: Part 3',
   'th_ep1_00' => '<:irlmaier:460382258336104448> They Hunger: Episode 1',
   'th_ep2_00' => '<:irlmaier:460382258336104448> They Hunger: Episode 2',
   'th_ep3_00' => '<:irlmaier:460382258336104448> They Hunger: Episode 3',
   'th_escape' => '<:ayaya:510534352262791179> Woohoo, They Hunger: Escape',
   'road_to_shinnen' => '<:kms:603508354786263040> Oh god, oh no, Road to Shinnen',
   'rust_mini_b8' => '<:pog:458682189471809536> (mini) R U S T',
   'sc_tl_build_puzzle_fft_final' => '<:omegalul:458685801706815489> Build Puzzle',
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

my $reacts = {
   264851156973387788 => 'biba:458415471130050565', # biba
   150294740703772672 => '🏳️‍🌈', # prid
};

my $discord_markdown_pattern = qr/(?<!\\)(@|:|#|\||__|\*|~|>)/;

###

my $gi = MaxMind::DB::Reader->new(file => $$config{'geo'});

my $dbh = DBI->connect("dbi:SQLite:$$config{'db'}", undef, undef, {
   RaiseError => 1,
   sqlite_open_flags => SQLITE_OPEN_READONLY,
});

$discord->init();

open my $fh, '<', $$config{'fromsven'} or die;

my $filestream = IO::Async::FileStream->new(
   read_handle => $fh,
   interval => 0.5,

   on_initial => sub {
      my ( $self ) = @_;
      $self->seek_to_last( "\n" );
   },

   on_read => sub {
      my ( $self, $buffref ) = @_;

      while ( $$buffref =~ s/^(.*\n)// )
      {
         my $line = $1;

         chomp( $line );

         if ( $line =~ /^status .+ [0-9][0-9]?$/ )
         {
            say localtime(time) . " -> status: $line";

            my @data = split( ' ', $line );

            $discord->status_update( { 'game' => "$data[1] @ twlz Sven Co-op" } );

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
            $discord->send_message( $$config{'mainchan'}, "**$$maps{$data[1]}** campaign has started with **$data[2]** players!" ) if ( exists $$maps{$data[1]} && $lastmap ne $data[1] );

            $lastmap = $data[1];
         }
         else
         {
            my $r;
            my $final;

            say localtime(time) . " -> $line";

            #$line =~ s/`//g;
            #$line =~ s/\@ADMINS?/<@&$$config{'adminrole'}>/gi;
            #$line =~ s/\@everyone/everyone/g;
            #$line =~ s/\@here/here/g;
            #$line =~ s/^(?:[+-] )?<(.+)><([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}):[0-9+]><STEAM_[0-5]:[01]:[0-9]+> (.+)/`$1`  $3/g;
            #$line =~ s/<(.+?)><(.+?):.+?><(.+?)> (.+)/`$1`  $4/g;
            $line =~ /<(.+?)><(.+?):.+?><(.+?)> (.+)/;
            $r = $gi->record_for_address($2);
            my $nick = $1;
            my $msg = $4;
            $nick =~ s/$discord_markdown_pattern/\\$1/g;
            $msg =~ s/$discord_markdown_pattern/\\$1/g;

            $final = "`$nick` $msg";
            $final =~ s/^/<:gtfo:603609334781313037> / if ($line =~ /^- /);
            $final =~ s/^/<:NyanPasu:562191812702240779> / if ($line =~ /^\+ /);

            $discord->send_message( $$config{'chatlinkchan'}, ":flag_@{[lc($r->{country}{iso_code})]}: " . $final );
         }
      }
      return 0;
   }
);

my $loop = IO::Async::Loop::Mojo->new();
$loop->add( $filestream );
$loop->run unless (Mojo::IOLoop->is_running);

close $fh;
$dbh->disconnect;
exit;

###

sub discord_on_ready
{
   my ($hash) = @_;
   add_me($hash->{'user'});
   say localtime(time) . ' Connected to Discord.';
}

sub discord_on_guild_create
{
   my ($hash) = @_;
   say localtime(time) . " Adding guild: " . $hash->{'id'} . " -> " . $hash->{'name'};
   add_guild($hash);
}

sub discord_on_message_create
{
   my ($hash) = @_;

   my $id = $hash->{'author'}->{'id'};
   my $author = $hash->{'author'};
   my $msg = $hash->{'content'};
   my $msgid = $hash->{'id'};
   my $channel = $hash->{'channel_id'};
   my @mentions = @{$hash->{'mentions'}};

   foreach my $mention ( @mentions )
   {
      add_user( $mention );
   }

   unless ( exists $author->{'bot'} && $author->{'bot'} )
   {
      $msg =~ s/\@everyone/everyone/g;
      $msg =~ s/\@here/here/g;

      #if ( $channel eq $$config{'mainchan'} )
      #{
      #   my $dirty = clean($channel, $msgid, $msg);
      #   return if ( $dirty );
      #}

      if ( $channel eq $$config{'kekchan'} )
      {
         $discord->add_reaction( $channel, $msgid, $$reacts{$id} ) if ( exists $$reacts{$id} );
      }

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
      elsif ( $channel ne $$config{'chatlinkchan'} && $msg =~ /^!player (.+)/i )
      {
         return; # disabled for now

         my $param = $1;
         my ($stmt, @bind, $r);

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

            #(my $url2 = $$config{'steamapiurl2'} . $r->[0] ) =~ s/XXXSTEAMAPIKEYXXX/$$config{'steamapikey'}/;
            #my $content2 = get( $url2 );

            #unless ( defined $content2 )
            #{
            #   $discord->send_message( $channel, "`Couldn't query Steam Bans API`" );
            #   return;
            #}

            #my $result2 = decode_json( $content2 );

            my $geo = Geo::Coder::Google->new(apiver => 3, language => 'en', key => $$config{'gmapikey'}, result_type => 'locality|sublocality|administrative_area_level_1|country|political');

            my $input;
            eval { $input = $geo->reverse_geocode( latlng => sprintf('%.3f,%.3f', $r->[12], $r->[13]) ) };

            my $loc = 'Unknown';

            if ( $input )
            {
               $loc = $input->{formatted_address};
            }

            my $embed = {
               'color' => '15844367',
               'provider' => {
                  'name' => 'twlz',
                  'url' => 'https://twlz.lifeisabug.com',
                },
                'thumbnail' => {
                   'url' => $$result{'response'}{'players'}->[0]{avatarfull},
                },
#                'image' => {
#                   'url' => "https://maps.googleapis.com/maps/api/staticmap?size=360x80&scale=2&language=en&region=ps&center=$r->[12],$r->[13]&zoom=7",
#                   'width' => 360,
#                   'height' => 80,
#                },
                'fields' => [
                {
                   'name'   => 'Name',
                   'value'  => "**[".$r->[2]."](".$$result{'response'}{'players'}->[0]{'profileurl'}." \"$$result{'response'}{'players'}->[0]{personaname}\")**",
                   'inline' => \1,
                 },
                 {
                    'name'   => 'Country',
                    'value'  => lc($r->[11]) eq 'se' ? ':gay_pride_flag:' : ":flag_".lc($r->[11]).":",
                    'inline' => \1,
                 },
                 {
                    'name'   => 'Time on TWLZ',
                    'value'  => $r->[14] < 1 ? '-' : duration( $r->[14]*30 ),
                    'inline' => \1,
                 },
                 {
                    'name'   => 'Last Seen',
                    'value'  => defined $r->[16] ? $r->[16] : 'Unknown',
                    'inline' => \1,
                 },
                 ],
            };

            if ( defined $r->[16] && ( int($r->[4]) > 0 || $r->[6] > 0 ) )
            {
               push @{$$embed{'fields'}}, { 'name' => 'Score', 'value' => int($r->[4]), 'inline' => \1, };
               push @{$$embed{'fields'}}, { 'name' => 'Deaths', 'value' => $r->[6], 'inline' => \1, };
            }

            #if ( $$result2{'players'}->[0]{'NumberOfVACBans'} > 0 )
            #{
            #   push @{$$embed{'fields'}}, { 'name' => 'VAC Banned', 'value' => "Yes ($$result2{'players'}->[0]{'NumberOfVACBans'})", 'inline' => \1, };
            #   push @{$$embed{'fields'}}, { 'name' => 'Last VAC Ban', 'value' => duration($$result2{'players'}->[0]{'DaysSinceLastBan'}*24*60*60).' ago', 'inline' => \1, };
            #}

            #if ( $$result2{'players'}->[0]{'CommunityBanned'} eq 'true' )
            #{
            #   push @{$$embed{'fields'}}, { 'name' => 'Steam Community Banned', 'value' => 'Yes', 'inline' => \1, };
            #}

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
      elsif ( $channel ne $$config{'chatlinkchan'} && $msg =~ /^!status/i )
      {
         my $if       = IO::Interface::Simple->new('lo');
         my $addr     = $if->address;
         my $port     = $$config{'serverport'};
         my $ap       = "$addr:$port";
         my $encoding = term_encoding;

         my $q = Net::SRCDS::Queries->new(
            encoding => $encoding,
            timeout  => 0.25,
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
            my $msg = "Map: **$$infos{$ap}{'info'}{'map'}**  Players: **$$infos{$ap}{'info'}{'players'}/$$infos{$ap}{'info'}{'max'}**$diff";

            $discord->send_message( $channel, $msg );
         }
      }
      elsif ( $channel ne $$config{'chatlinkchan'} && $msg =~ /^((?:\[\s\]\s[^\[\]]+\s?)+)/ )
      {
         my (@x, $y);

         $msg =~ s/`//g;
         $msg =~ s/(\[\s\]\s[^\[\]]+)+?\s?/push @x,$1/eg;
         $x[int(rand(@x))] =~ s/\[\s\]/[x]/;

         $discord->send_message( $channel, "`@x`" );
      }
      elsif ( $channel ne $$config{'chatlinkchan'} && ( $msg =~ /^!weather (.+)/i || $msg =~ /^!w (.+)/i ) )
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

            if ( $elevdata->{status} eq 'OK' )
            {
               $alt = $elevdata->{results}->[0]->{elevation};
            }
         }

         my $flag = 'flag_white';
         for ( @{$input->{address_components}} )
         {
            if ( 'country' ~~ @{$_->{types}} )
            {
               $flag = 'flag_' . lc($_->{short_name});
            }
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
             'image' => {
                'url' => "https://maps.googleapis.com/maps/api/staticmap?size=360x80&scale=2&language=en&region=ps&center=$lat,$lon&zoom=8",
                'width' => 360,
                'height' => 80,
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
      elsif ( $channel ne $$config{'chatlinkchan'} && $msg =~ /^!ud (.+)/i )
      {
         my $input    = $1;
         my $query    = uri_escape("$input");
         my $response = get("https://api.urbandictionary.com/v0/define?term=$query");

         if ( $response )
         {
            my $ud = decode_json($response);

            if (defined $$ud{list}[0]{definition})
            {
                my $msg = '';

                for (0..3)
                {
                   $$ud{list}[$_]{definition} =~ s/\s+/ /g;
                   $msg .= sprintf("(%d) %s:: %s\n", $_+1, (lc($$ud{list}[$_]{word}) ne lc($input)) ? $$ud{list}[$_]{word} . ' ' : '', (length($$ud{list}[$_]{definition}) > 399) ? substr($$ud{list}[$_]{definition}, 0, 400) . '...' : $$ud{list}[$_]{definition});
                   last unless (defined $$ud{list}[$_+1]{definition});
                }

                $discord->send_message( $channel, "```$msg```" );
            }
            else
            {
               $discord->send_message( $channel, '`No match`' );
            }
         }
         else
         {
            $discord->send_message( $channel, '`API error`' );
         }
      }
      elsif ( $channel ne $$config{'chatlinkchan'} && $msg =~ /^!xonstat (.+)/i ) {
         my ($qid, $stats);
         ($qid = $1) =~ s/[^0-9]//g;

         unless ($qid) {
            $discord->send_message( $channel, 'Invalid player ID');
            return;
         }

         my $json = get($$config{'xonstaturl'} . $qid . '.json');

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
         my $last    = $stats->[0]->{overall_stats}->{overall}->{last_played_fuzzy};

         my $embed = {
            'color' => '15844367',
            'provider' => {
               'name' => 'XonStat',
               'url' => 'https://stats.xonotic.org',
             },
             #'thumbnail' => {
             #   'url' => "https://cdn.discordapp.com/emojis/458355320364859393.png?v=1",
             #   'width' => 38,
             #   'height' => 38,
             #},
             'image' => {
                'url' => "https://stats.xonotic.org/static/badges/$qid.png",
                'width' => 650,
                'height' => 70,
             },
             'footer' => {
                'text' => "Last played: $last",
             },
             'fields' => [
              {
                 'name'   => 'Name',
                 'value'  => "**[$snick]($$config{'xonstaturl'}$qid)**",
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

      #main::msg($target, "%s :: games: %d/%d/%d (%.2f%% win) :: k/d: %.2f (%d/%d)%s :: fav map: %s (%s) :: last played %s", $snick, $games, $win, $loss, $pct, $ratio, $kills, $deaths, ($elo && $elo ne 100) ? sprintf(' :: %s elo: %.2f (%d games%s)', $elot, $elo, $elog, $elot eq 'ctf' ? sprintf(', %.2f cr', $capr) : '' ) : '', $favmap, $favmapt, $last);
      }
#      elsif ( $channel ne $$config{'chatlinkchan'} && $msg =~ /^!xon$/i )
#      {
#         $discord->send_message( $channel, '<:xon:458355320364859393> IPv4: `connect 207.180.223.40` IPv6: `connect 2a02:c207:3003:5281::1`' );
#      }
   }
}

sub discord_on_message_update
{
   my ($hash) = @_;

   my $author = $hash->{'author'};
   my $msg = $hash->{'content'};
   my $msgid = $hash->{'id'};
   my $channel = $hash->{'channel_id'};

   return 0 unless $msg;

   unless ( exists $author->{'bot'} && $author->{'bot'} )
   {
   #if ( $channel eq $$config{'mainchan'} )
      #{
      #   clean($channel, $msgid, $msg);
      #}
   }
}

sub add_me
{
   my ($user) = @_;
   $self->{'id'} = $user->{'id'};
   add_user($user);
}

sub add_user
{
   my ($user) = @_;
   my $id = $user->{'id'};
   $self->{'users'}{$id} = $user;
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
}

sub clean
{
   my ($channel, $msgid, $msg) = @_;

   return 0 unless $msg;

   my $delete = 0;

   $delete++ if ($msg =~ /[^\x{0000}-\x{ffff}]/);
   $delete++ if ($msg =~ /:\w+:/i);
   $delete++ if ($msg =~ /https?:\/\/(?:www\.)?tenor/i);

   $discord->delete_message( $channel, $msgid ) if ( $delete );

   return $delete;
}

sub duration
{
   my $sec = shift;

   my @gmt = gmtime($sec);

   $gmt[5] -= 70;
   return   ($gmt[5] ?                                                       $gmt[5].'y' : '').
            ($gmt[7] ? ($gmt[5]                                  ? ' ' : '').$gmt[7].'d' : '').
            ($gmt[2] ? ($gmt[5] || $gmt[7]                       ? ' ' : '').$gmt[2].'h' : '').
            ($gmt[1] ? ($gmt[5] || $gmt[7] || $gmt[2]            ? ' ' : '').$gmt[1].'m' : '');
            ($gmt[0] ? ($gmt[5] || $gmt[7] || $gmt[2] || $gmt[1] ? ' ' : '').$gmt[0].'s' : '');
}
