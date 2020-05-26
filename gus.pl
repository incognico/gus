#!/usr/bin/env perl

# Gus - Discord bot for the twilightzone Sven Co-op server
#
# Requires https://github.com/vsTerminus/Mojo-Discord (release v3+)
# Based on https://github.com/vsTerminus/Goose
#
# Copyright 2017-2020, Nico R. Wohlgemuth <nico@lifeisabug.com>

use v5.28.0;

use utf8;
use strict;
use warnings;

use lib '/etc/perl';

use feature 'signatures';
no warnings qw(experimental::signatures experimental::smartmatch);

binmode( STDOUT, ":encoding(UTF-8)" );

local $SIG{INT} = \&quit;

use DBI;
use DBD::SQLite::Constants ':file_open';
use Data::Dumper;
use DateTime;
use DateTime::TimeZone;
use Encode::Simple qw(encode_utf8_lax decode_utf8_lax);
use Geo::Coder::Google;
use IO::Async::FileStream;
use IO::Async::Loop::Mojo;
use IO::Async::Timer::Periodic;
use IO::Interface::Simple;
use JSON::MaybeXS;
use LWP::Simple qw($ua get);
use LWP::UserAgent;
use MaxMind::DB::Reader;
use Mojo::Discord;
use Net::SRCDS::Queries;
use Path::This '$THISDIR';
use Term::Encoding qw(term_encoding);
use URI::Escape;
use Weather::METNO;
use YAML::Tiny qw(LoadFile DumpFile);

$ua->agent( 'Mozilla/5.0' );
$ua->timeout( 6 );

my $self;
my ($store, $storechanged, $lastmap, $steamidmap) = ({}, 0, '', {});

my $config = {
   game         => 'Sven Co-op',
   fromsven     => "$ENV{HOME}/sc5/svencoop/scripts/plugins/store/_fromsven.txt",
   tosven       => "$ENV{HOME}/sc5/svencoop/scripts/plugins/store/_tosven.txt",
   db           => "$ENV{HOME}/scstats/scstats.db",
   steamapikey  => '',
   steamapiurl  => 'https://api.steampowered.com/ISteamUser/GetPlayerSummaries/v0002/?key=XXXSTEAMAPIKEYXXX&steamids=',
   steamapiurl2 => 'https://api.steampowered.com/ISteamUser/GetPlayerBans/v1/?key=XXXSTEAMAPIKEYXXX&steamids=',
   serverport   => 27015,
   gmapikey     => '',
   geo          => $THISDIR . '/GeoLite2-City.mmdb',
   store        => $THISDIR . '/.store.yml',
   omdbapikey   => ,

   discord => {
      linkchan   => 458683388887302155,
      mainchan   => 458323696910598167,
      wufluchan  => 673626913864155187,
      nsfwchan   => 541343127550558228,
      ayayachan  => 459345843942588427,
      spamchan   => 512991515744665600,
      nocmdchans => [706113584626663475, 610862900357234698, 673626913864155187, 698803767512006677],
      client_id  => ,
      owner_id   => 373912992758235148,
      ver_role   => 712296542211670088,
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
   'mustard_b'            => ':hotdog: Mustard Factory',
   'of0a0'                => '<:flower:458608402549964814> HL: Opposing Force',
   'of_utbm'              => ':new_moon: OP4: Under the Black Moon',
   'otokotati_no_kouzan'  => ':hammer_pick: Otokotati No Kouzan',
   'pizza_ya_san1'        => ':pizza: Pizza Ya San: 1',
   'pizza_ya_san2'        => ':pizza: Pizza Ya San: 2',
   'po_c1m1'              => ':regional_indicator_p: Poke 646',
   'projectg1'            => ':dromedary_camel: Project: Guilty',
   'pv_c1m1'              => ':regional_indicator_v: Poke 646: Vendetta',
   'quad_f'               => '<:blanketwrap:712012386743222313> Quad',
   'ra_quad'              => '<:blanketwrap:712012386743222313> Real Adrenaline Quad',
   'ressya_no_tabi'       => ':train2::camera_with_flash: Ressya No Tabi',
   'restriction01'        => ':radioactive: Restriction',
   'road_to_shinnen'      => ':shinto_shrine: Oh god, oh no, Road to Shinnen',
   'rust_islands_b9'      => '<:eecat:460442390457483274> R U S T',
   'rust_legacy_b9'       => '<:eecat:460442390457483274> (legacy) R U S T',
   'rust_mini_b9'         => '<:eecat:460442390457483274> (mini) R U S T',
   'sa13'                 => '<:KannaSuicide:603609334080995338> SA13',
   'sc_royals1'           => ':eye: Royals',
   'sc_tl_build_puzzle_fft_final' => '<:PepeKek:603647721496248321> Build Puzzle',
   'th_ep1_01'            => '<:irlmaier:460382258336104448> They Hunger: Episode 1',
   'th_ep2_00'            => '<:irlmaier:460382258336104448> They Hunger: Episode 2',
   'th_ep3_00'            => '<:irlmaier:460382258336104448> They Hunger: Episode 3',
   'th_escape'            => '<:KannaSpook:603856338132664321> They Hunger: Escape',
   'the_daikon_warfare1'  => ':seedling: The Daikon Warfare',
   'tunnelvision_1'       => '<:KannaZoooming:662976056956813353> Tunnel Vision',
   'uboa'                 => ':rice_ball: UBOA',
};

#my $discord_markdown_pattern = qr/(?<!\\)(`|@|:|#|\||__|\*|~|>)/;
my $discord_markdown_pattern = qr/(?<!\\)(`|@|#|\||__|\*|~|>)/;

###

my $gi = MaxMind::DB::Reader->new(file => $$config{'geo'});

my $dbh = DBI->connect("dbi:SQLite:$$config{'db'}", undef, undef, {
   RaiseError => 1,
   sqlite_open_flags => SQLITE_OPEN_READONLY,
});

DumpFile($$config{store}, $store) unless (-f $$config{store});
$store = LoadFile($$config{store});

for (keys $$store{users}->%*)
{
   $$steamidmap{$$store{users}{$_}{steamid}} = $_ if (exists $$store{users}{$_}{steamid});
}

discord_on_ready();
discord_on_message_create();

$discord->init();

open my $fh, '<', $$config{'fromsven'} or die;

my $filestream = IO::Async::FileStream->new(
   read_handle => $fh,

   interval => 1.5,

   on_initial => sub ($self, $)
   {
      $self->seek_to_last( "\n" );
   },

   on_read => sub ($self, $buffref, $)
   {
      while ( $$buffref =~ s/^(.*\n)// )
      {
         my $line = decode_utf8_lax($1);

         chomp( $line );

         if ( $line =~ /^status .+ [0-9][0-9]?$/ )
         {
            say localtime(time) . " -> status: $line";

            my @data = split( ' ', $line );

            $discord->status_update( { 'name' => 'SC on ' . $data[1], type => 0 } );

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
                   'value'  => $data[1],
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
            
            $discord->send_message( $$config{discord}{linkchan}, $message );

            if ( exists $$maps{$data[1]} && $$maps{$data[1]} ne $lastmap )
            {
               my $s = '';
               $s = 's' if ( $data[2] > 1 );
               $discord->send_message( $$config{discord}{mainchan}, "**$$maps{$data[1]}** has started with **$data[2]** player$s!" );
               $lastmap = $$maps{$data[1]};
            }
         }
         else
         {
            $line =~ /<(.+?)><(.+?):.+?><(.+?)> (.+)/;
            say localtime(time) . " -> $line";

            my $nick    = $1;
            my $r       = $gi->record_for_address($2);
            my $steamid = $3;
            my $msg     = $4;

            $nick =~ s/`//g;

            $msg =~ s/(\s|\R)+/ /g;
            $msg =~ s/\@+everyone/everyone/g;
            $msg =~ s/\@+here/here/g;
            $msg =~ s/$discord_markdown_pattern/\\$1/g;


            if ($msg =~ /^!verify/ )
            {
                verify($steamid);
                return;
            }

            my $final;
            if (exists $$steamidmap{$steamid} && defined $$store{users}{$$steamidmap{$steamid}}{linknick} && $$store{users}{$$steamidmap{$steamid}}{linknick} > 0 )
            {
               $final = "<\@$$steamidmap{$steamid}>";
            }
            else
            {
               $final = "`$nick`";
            }
            $final   .= "  $msg";

            $final =~ s/^/<:gtfo:603609334781313037> / if ($line =~ /^- /);
            $final =~ s/^/<:NyanPasu:562191812702240779> / if ($line =~ /^\+ /);

            my $message = {
               content => ':flag_' . ($r->{country}{iso_code} ? lc($r->{country}{iso_code}) : 'white') . ': ' . $final,
               allowed_mentions => { parse => [] },
            };

            $discord->send_message( $$config{discord}{linkchan}, $message );
         }
      }
      return 0;
   }
);

my $timer = IO::Async::Timer::Periodic->new(
   interval => 15,

   on_tick => sub ($) {
      DumpFile($$config{store}, $store) if $storechanged;
      $storechanged = 0;

      for (keys $$store{steamidqueue}->%*)
      {
         delete $$store{steamidqueue}{$_} if (exists $$store{steamidqueue}{$_}{ts} && ($$store{steamidqueue}{$_}{ts} + 3600) < time);
         $storechanged = 1;
      }

      return unless (defined $$store{reminders} && $discord->connected);

      $$store{reminders}->@* = grep { defined } map {
         if ( $_->{time} && $_->{time} <= time)
         {
            my $allowed = [ $_->{owner} ];

            if ($_->{target} && $_->{target} =~ /^<@!?(\d+)>$/)
            {
               if ($1 != $_->{owner})
               {
                  shift($allowed->@*);
                  push($allowed->@*, $1);

                  $_->{text} .= " (reminded by <\@$_->{owner}>)";
               }
            }

            my $message = {
               'content' => "$_->{target} $_->{text}",
               'allowed_mentions' => { users => $allowed },
            };

            $discord->send_message( $_->{chan}, $message );

            $storechanged = 1;
            undef $_;
         }
         else
         {
            $_
         }
      } $$store{reminders}->@*;
   },
);
$timer->start;

my $loop = IO::Async::Loop::Mojo->new();

$loop->add($filestream);
$loop->add($timer);

$loop->run unless (Mojo::IOLoop->is_running);

close $fh;
$dbh->disconnect;
exit;

###

sub discord_on_message_create
{
   $discord->gw->on('MESSAGE_CREATE' => sub ($gw, $hash)
   {
      my $id       = $hash->{'author'}->{'id'};
      my $author   = $hash->{'author'};
      my $member   = $hash->{'member'};
      my $msg      = $hash->{'content'};
      my $msgid    = $hash->{'id'};
      my $channel  = $hash->{'channel_id'};
      my @mentions = $hash->{'mentions'}->@*;

      add_user($_) for(@mentions);

      unless ( exists $author->{'bot'} && $author->{'bot'} )
      {
         $msg =~ s/\@+everyone/everyone/g;
         $msg =~ s/\@+here/here/g;

         if ( $channel eq $$config{discord}{linkchan} )
         {
            $msg =~ s/`//g;
            $msg =~ s/%/%%/g;
            if ( $msg =~ s/<@!?(\d+)>/\@$self->{'users'}->{$1}->{'username'}/g ) # user/nick
            {
               $msg =~ s/(?:\R^)\@$self->{'users'}->{$1}->{'username'}/ >>> /m if ($1 == $self->{'id'});
            }
            $msg =~ s/(\R|\s)+/ /gn;
            $msg =~ s/<#(\d+)>/#$self->{'channelnames'}->{$1}/g; # channel
            $msg =~ s/<@&(\d+)>/\@$self->{'rolenames'}->{$1}/g; # role
            $msg =~ s/<a?(:.+:)\d+>/$1/g; # emoji

            return unless $msg;

            my $nick = defined $$member{'nick'} ? $$member{'nick'} : $$author{'username'};
            $nick =~ s/`//g;
            $nick =~ s/%/%%/g;
            $nick =~ s/(\R|\s)+/ /gn;

            say localtime(time) . " <- <$nick> $msg";

            open (my $tosvenfh, '>>:encoding(UTF-8)', $$config{'tosven'}) or die;
            say $tosvenfh "(DISCORD) $nick: $msg";
            close $tosvenfh;
         }
         elsif ( $msg =~ /^!player (.+)/i )
         {
            my $param = $1;
            my ($stmt, @bind, $r);

            my $nsa;
            $nsa = 1 if ( $channel eq $$config{discord}{ayayachan} );

            if ( $param =~ /^STEAM_(0:[01]:[0-9]+)/ )
            {
               $stmt = "SELECT * FROM stats WHERE steamid = ? ORDER BY datapoints DESC, date(seen) DESC LIMIT 1";
               @bind = ( "$1" );
            }
#            elsif ( $param =~ /^<@!?(\d+)>/ )
#            {
#               my $request;
#
#               if ( defined $$store{users}{$1}{steamid} )
#               {
#                  $request = $1 if ( $$store{users}{$1}{steamid} =~ /^STEAM_(0:[01]:[0-9]+)$/ );
#               }
#               else
#               {
#                  $discord->send_message( $channel, 'The requested user must set his Steam ID by using `!set steamid STEAM_0:X:XXXXXX` first.' );
#                  return;
#               }
#
#               $stmt = "SELECT * FROM stats WHERE steamid = ? ORDER BY datapoints DESC, date(seen) DESC LIMIT 1";
#               @bind = ( "$request" );
#            }
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

               my $personaname = $$result{'response'}{'players'}->[0]{personaname};
               $personaname =~ s/$discord_markdown_pattern/\\$1/g;

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
                      'value'  => "**[".decode_utf8_lax($r->[2])."](".$$result{'response'}{'players'}->[0]{'profileurl'}." \"$personaname\")**",
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
                      push $$embed{'fields'}->@*, { 'name' => 'Score',  'value' => int($r->[4]), 'inline' => \1, };
                      push $$embed{'fields'}->@*, { 'name' => 'Deaths', 'value' => $r->[6],      'inline' => \1, };
                  }

                  push $$embed{'fields'}->@*, { 'name' => 'Location', 'value' => "[GMaps](https://www.google.com/maps/\@$r->[12],$r->[13],11z)", 'inline' => \1, };
               }

               push $$embed{'fields'}->@*, { 'name' => 'VAC Bans', 'value' => $$result2{'players'}->[0]{'NumberOfVACBans'} . ' (' . duration($$result2{'players'}->[0]{'DaysSinceLastBan'}*24*60*60) . ' ago)', 'inline' => \1, } if ( $$result2{'players'}->[0]{'NumberOfVACBans'} > 0 );
               push $$embed{'fields'}->@*, { 'name' => 'Steam Community Banned', 'value' => 'Yes', 'inline' => \1, } if ( $$result2{'players'}->[0]{'CommunityBanned'} eq 'true' );

               my $message = {
                  'content' => '',
                  'embed' => $embed,
               };

               $discord->send_message( $channel, $message );
            }
            else
            {
                r_red( $channel, $msgid );
            }
         }
         elsif ( $msg =~ /^!stat(us|su)/i && !($channel ~~ $$config{discord}{nocmdchans}->@*) )
         {
            $discord->start_typing( $channel, sub {
               my $if       = IO::Interface::Simple->new('lo');
               my $addr     = $if->address;
               my $port     = $$config{'serverport'};
               my $ap       = "$addr:$port";
               my $encoding = term_encoding;

               my $q = Net::SRCDS::Queries->new(
                  encoding => $encoding,
                  timeout  => 2,
               );

               $q->add_server( $addr, $port );
               my $infos = $q->get_all;

               unless ( defined $$infos{$ap}{'info'} )
               {
                  r_pepe( $channel, $msgid );
               }
               else
               {
                  my $diff = '';
                  $diff = "  Difficulty: **$1**" if ( $$infos{$ap}{'info'}{'sname'} =~ /difficulty: (.+)/ );
                  my $dmsg = "Map: **$$infos{$ap}{'info'}{'map'}**  Players: **$$infos{$ap}{'info'}{'players'}**/$$infos{$ap}{'info'}{'max'}$diff";

                  $discord->send_message( $channel, $dmsg );
               }
            });
         }
         elsif ( $msg =~ /^!w(?:eather)? ?(.+)?/i && !($channel ~~ $$config{discord}{nocmdchans}->@*) )
         {
            my ($alt, $flg, $loc, $lat, $lon, $tz) = (0, 'white');

            unless (defined $1)
            {
               if (defined $$store{users}{$id}{weather})
               {
                  $loc = $$store{users}{$id}{weather};
                  $lat = $$store{users}{$id}{weather_priv}{lat};
                  $lon = $$store{users}{$id}{weather_priv}{lon};
                  $alt = $$store{users}{$id}{weather_priv}{alt};
                  $tz  = exists $$store{users}{$id}{weather_priv}{tz} ? $$store{users}{$id}{weather_priv}{tz} : (tz_by_coords($lat, $lon))[0];
                  $flg = $$store{users}{$id}{weather_priv}{flg};
               }
               else
               {
                  $discord->create_reaction( $channel, $msgid, ':eh:458679128556568586' );
                  return;
               }
            }
            else
            {
               my $geo = Geo::Coder::Google->new(apiver => 3, language => 'en', key => $$config{'gmapikey'});

               my $input;
               eval { $input = $geo->geocode(location => $1) };

               unless ( $input )
               {
                  r_red( $channel, $msgid );
                  return;
               }

               $loc = $input->{formatted_address};
               $lat = $input->{geometry}{location}{lat};
               $lon = $input->{geometry}{location}{lng};
               $alt = elev_by_coords($lat, $lon);
               $tz  = (tz_by_coords($lat, $lon))[0];

               for ($$input{address_components}->@*)
               {
                  $flg = lc($_->{short_name}) if ('country' ~~ $$_{types}->@*);
               }

               $$store{users}{$id}{weather}           = $loc;
               $$store{users}{$id}{weather_priv}{lat} = $lat;
               $$store{users}{$id}{weather_priv}{lon} = $lon;
               $$store{users}{$id}{weather_priv}{alt} = $alt;
               $$store{users}{$id}{weather_priv}{tz}  = $tz;
               $$store{users}{$id}{weather_priv}{flg} = $flg;

               $storechanged = 1;
            }


            my $w = Weather::METNO->new(lat => $lat, lon => $lon, alt => $alt, lang => 'en', uid => '<nico@lifeisbug.com>');

            my $symboltype = 'png';
            my $symbolurl  = 'https://distfiles.lifeisabug.com/metno/' . $symboltype;

            my $embed = {
               'color' => '15844367',
               'provider' => {
                  'name' => 'met.no',
                  'url'  => 'https://www.met.no/',
                },
                'author' => {
                   'name'     => sprintf('Weather for %s', $loc),
                   'url'      => sprintf('https://www.google.com/maps/@%f,%f,13z', $lat, $lon),
                   'icon_url' => sprintf('https://www.countryflags.io/%s/flat/64.png', $flg)
                },
                'description' => sprintf('**%s**', $w->symbol_txt),
                'thumbnail' => {
                   'url'    => sprintf('%s/%s.%s', $symbolurl, $w->symbol, $symboltype),
                },
                'footer' => {
                   'text' => sprintf('Elevation: %dm (%dft) / Local time: %s', int($alt), int($alt * 3.2808), DateTime->now(time_zone => $tz)->strftime('%R')),
                },
                'fields' => [
                 {
                    'name'   => 'Temperature',
                    'value'  => sprintf('**%.1f°C** / %.1f°F', $w->temp_c, $w->temp_f),
                    'inline' => \1,
                 },
                 {
                    'name'   => 'Humidity',
                    'value'  => sprintf('%u%%', $w->humidity),
                    'inline' => \1,
                 },
                 {
                    'name'   => 'Cloudiness',
                    'value'  => sprintf('%u%%', $w->cloudiness),
                    'inline' => \1,
                 },
                 {
                    'name'   => 'Wind',
                    'value'  => sprintf('%s from %s', $w->windspeed_bft_txt, $w->windfrom_dir),
                    'inline' => \1,
                 },
                 {
                    'name'   => 'Fog',
                    'value'  => sprintf('%u%%', $w->foginess),
                    'inline' => \1,
                 },
                 {
                    'name'   => 'UV Index',
                    'value'  => sprintf('%.3g', $w->uvindex),
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
         elsif ( $msg =~ /^!img ?(.+)?/i && $channel eq $$config{discord}{nsfwchan} )
         {
            my $type = defined $1 ? lc($1) : 'random';
            $type =~ s/ //g;

            #my @types = qw(hass hmidriff pgif 4k hentai holo hneko neko hkitsune kemonomimi anal hanal gonewild kanna ass pussy thigh hthigh gah coffee food);
            my @types = qw(hass hmidriff hentai holo hneko neko hkitsune kemonomimi hanal kanna thigh hthigh coffee food);
            $type = $types[rand @types] if ( $type eq 'random' );

            if ( $type eq 'help' || !( $type ~~ @types ) )
            {
               $discord->send_message( $channel, "`One of: @types`" );
               return;
            }

            my $neko = "https://nekobot.xyz/api/image?type=$type";
            my $ua = LWP::UserAgent->new( agent => 'Mozilla/5.0', timeout => 6 );
            my $r = $ua->get( $neko, 'Content-Type' => 'application/json' );
            unless ( $r->is_success )
            {
               r_pepe( $channel, $msgid );
               return;
            }
            my $i = decode_json ( $r->decoded_content );

            if ( defined $$i{success} && $$i{success} )
            {
               $discord->send_message( $channel, $$i{message} );
            }
            else
            {
               r_pepe( $channel, $msgid );
            }
         }
         elsif ( $msg =~ /^!ud (.+)/i && $channel eq $$config{discord}{nsfwchan} )
         {
            my $input = $1;
            my $query = uri_escape( $input );
            my $ua = LWP::UserAgent->new( agent => 'Mozilla/5.0', timeout => 6 );
            $ua->agent( ssl_opts => { verify_hostname => 0 } );
            my $r = $ua->get( "https://api.urbandictionary.com/v0/define?term=$query", 'Content-Type' => 'application/json' );
            unless ( $r->is_success )
            {
               r_pepe( $channel, $msgid );
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

                   $discord->send_message( $channel, "```asciidoc\n$res```" );
               }
               else
               {
                  r_red( $channel, $msgid );
               }
            }
            else
            {
               r_pepe( $channel, $msgid );
            }
         }
         elsif ( $msg =~ /^!(ncov|waiflu|wuflu|virus|corona)/i && $channel eq $$config{discord}{wufluchan} )
         {
            my $ncov = 'https://raw.githubusercontent.com/montanaflynn/covid-19/master/data/current.json';
            my $ua = LWP::UserAgent->new( agent => 'Mozilla/5.0', timeout => 6 );
            my $r = $ua->get( $ncov, 'Content-Type' => 'application/json' );
            unless ( $r->is_success )
            {
               r_pepe( $channel, $msgid );
               return;
            }
            my $i = decode_json ( encode_utf8_lax($r->decoded_content) );

            if ( defined $$i{global} )
            {
               my ($confirmed, $deaths, $recovered, $updated) = (0, 0, 0, 0);

               for ( keys $$i{global}->%* )
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
                       'name'   => ':flag_ru: **Russia**',
                       'value'  => "**I:** $$i{global}{Russia}{confirmed} (**C:** " . ($$i{global}{Russia}{confirmed}-$$i{global}{Russia}{deaths}-$$i{global}{Russia}{recovered}) . ") **D:** $$i{global}{Russia}{deaths} (" . sprintf('%.2f', ($$i{global}{Russia}{deaths}/$$i{global}{Russia}{confirmed})*100) . "%) **R:** $$i{global}{Russia}{recovered}",
                       'inline' => \0,
                    },
                    {
                       'name'   => ':flag_br: **Brazil**',
                       'value'  => "**I:** $$i{global}{Brazil}{confirmed} (**C:** " . ($$i{global}{Brazil}{confirmed}-$$i{global}{Brazil}{deaths}-$$i{global}{Brazil}{recovered}) . ") **D:** $$i{global}{Brazil}{deaths} (" . sprintf('%.2f', ($$i{global}{Brazil}{deaths}/$$i{global}{Brazil}{confirmed})*100) . "%) **R:** $$i{global}{Brazil}{recovered}",
                       'inline' => \0,
                    },
                    {
                       'name'   => ':flag_es: **Spain**',
                       'value'  => "**I:** $$i{global}{Spain}{confirmed} (**C:** " . ($$i{global}{Spain}{confirmed}-$$i{global}{Spain}{deaths}-$$i{global}{Spain}{recovered}) . ") **D:** $$i{global}{Spain}{deaths} (" . sprintf('%.2f', ($$i{global}{Spain}{deaths}/$$i{global}{Spain}{confirmed})*100) . "%) **R:** $$i{global}{Spain}{recovered}",
                       'inline' => \0,
                    },
                    {
                       'name'   => ':flag_gb: **United Kingdom**',
                       'value'  => "**I:** $$i{global}{'United Kingdom'}{confirmed} (**C:** " . ($$i{global}{'United Kingdom'}{confirmed}-$$i{global}{'United Kingdom'}{deaths}-$$i{global}{'United Kingdom'}{recovered}) . ") **D:** $$i{global}{'United Kingdom'}{deaths} (" . sprintf('%.2f', ($$i{global}{'United Kingdom'}{deaths}/$$i{global}{'United Kingdom'}{confirmed})*100) . "%) **R:** $$i{global}{'United Kingdom'}{recovered}",
                       'inline' => \1,
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
                       'name'   => ':flag_tr: **Turkey**',
                       'value'  => "**I:** $$i{global}{Turkey}{confirmed} (**C:** " . ($$i{global}{Turkey}{confirmed}-$$i{global}{Turkey}{deaths}-$$i{global}{Turkey}{recovered}) . ") **D:** $$i{global}{Turkey}{deaths} (" . sprintf('%.2f', ($$i{global}{Turkey}{deaths}/$$i{global}{Turkey}{confirmed})*100) . "%) **R:** $$i{global}{Turkey}{recovered}",
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
                       'name'   => ':flag_in: **India**',
                       'value'  => "**I:** $$i{global}{India}{confirmed} (**C:** " . ($$i{global}{India}{confirmed}-$$i{global}{India}{deaths}-$$i{global}{India}{recovered}) . ") **D:** $$i{global}{India}{deaths} (" . sprintf('%.2f', ($$i{global}{India}{deaths}/$$i{global}{India}{confirmed})*100) . "%) **R:** $$i{global}{India}{recovered}",
                       'inline' => \0,
                    },
                    {
                       'name'   => ':flag_pe: **Peru**',
                       'value'  => "**I:** $$i{global}{Peru}{confirmed} (**C:** " . ($$i{global}{Peru}{confirmed}-$$i{global}{Peru}{deaths}-$$i{global}{Peru}{recovered}) . ") **D:** $$i{global}{Peru}{deaths} (" . sprintf('%.2f', ($$i{global}{Peru}{deaths}/$$i{global}{Peru}{confirmed})*100) . "%) **R:** $$i{global}{Peru}{recovered}",
                       'inline' => \0,
                    },
                    {
                       'name'   => ':flag_ca: **Canada**',
                       'value'  => "**I:** $$i{global}{Canada}{confirmed} (**C:** " . ($$i{global}{Canada}{confirmed}-$$i{global}{Canada}{deaths}-$$i{global}{Canada}{recovered}) . ") **D:** $$i{global}{Canada}{deaths} (" . sprintf('%.2f', ($$i{global}{Canada}{deaths}/$$i{global}{Canada}{confirmed})*100) . "%) **R:** $$i{global}{Canada}{recovered}",
                       'inline' => \0,
                    },
                    {
                       'name'   => ':flag_sa: **Saudi Arabia**',
                       'value'  => "**I:** $$i{global}{'Saudi Arabia'}{confirmed} (**C:** " . ($$i{global}{'Saudi Arabia'}{confirmed}-$$i{global}{'Saudi Arabia'}{deaths}-$$i{global}{'Saudi Arabia'}{recovered}) . ") **D:** $$i{global}{'Saudi Arabia'}{deaths} (" . sprintf('%.2f', ($$i{global}{'Saudi Arabia'}{deaths}/$$i{global}{'Saudi Arabia'}{confirmed})*100) . "%) **R:** $$i{global}{'Saudi Arabia'}{recovered}",
                       'inline' => \0,
                    },
                    {
                       'name'   => ':flag_mx: **Mexico**',
                       'value'  => "**I:** $$i{global}{Mexico}{confirmed} (**C:** " . ($$i{global}{Mexico}{confirmed}-$$i{global}{Mexico}{deaths}-$$i{global}{Mexico}{recovered}) . ") **D:** $$i{global}{Mexico}{deaths} (" . sprintf('%.2f', ($$i{global}{Mexico}{deaths}/$$i{global}{Mexico}{confirmed})*100) . "%) **R:** $$i{global}{Mexico}{recovered}",
                       'inline' => \0,
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
               r_pepe( $channel, $msgid );
            }
         }
         elsif ( $msg =~ /^!(?:[io]mdb|movie) (.+)/i && !($channel ~~ $$config{discord}{nocmdchans}->@*) )
         {
            my @args = split(' ', $1);
            my $year;
            $year = pop(@args) if ($args[-1] =~ /^\(?\d{4}\)?$/);
            $year =~ s/[^\d]//g if ($year);
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
               r_pepe( $channel, $msgid );
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

               push $$embed{'fields'}->@*, { 'name' => 'Actors',      'value' => $$omdb{Actors},                                    'inline' => \1, } unless ( $$omdb{Actors}     eq 'N/A' );
               push $$embed{'fields'}->@*, { 'name' => 'Plot',        'value' => $$omdb{Plot},                                      'inline' => \0, } unless ( $$omdb{Plot}       eq 'N/A' );
               push $$embed{'fields'}->@*, { 'name' => 'IMDB Rating', 'value' => "$$omdb{imdbRating}/10 ($$omdb{imdbVotes} votes)", 'inline' => \1, } unless ( $$omdb{imdbRating} eq 'N/A' );
               push $$embed{'fields'}->@*, { 'name' => 'Metascore',   'value' => "$$omdb{Metascore}/100",                           'inline' => \1, } unless ( $$omdb{Metascore}  eq 'N/A' );
               push $$embed{'fields'}->@*, { 'name' => 'Seasons',     'value' => $$omdb{totalSeasons},                              'inline' => \1, }     if ( $$omdb{Type}       eq 'series' );

               my $message = {
                  'content' => '',
                  'embed' => $embed,
               };

               $discord->send_message( $channel, $message );
            }
            else
            {
               r_red( $channel, $msgid );
            }
         }
         elsif ( $msg =~ /^((?:\[\s\]\s[^\[\]]+\s?)+)/ && !($channel ~~ $$config{discord}{nocmdchans}->@*) )
         {
            my @x;

            $msg =~ s/`//g;
            $msg =~ s/(\[\s\]\s[^\[\]]+)+?\s?/push @x,$1/eg;
            $x[int(rand(@x))] =~ s/\[\s\]/[x]/;

            $discord->send_message( $channel, join '', @x );
         }
         elsif ( $msg =~ /^!(set|get) (tz|steamid|linknick) ?(.*)?/i && !($channel ~~ $$config{discord}{nocmdchans}->@*) )
         {
            my $action = $1;
            my $type   = $2;
            my $value  = $3;

            if ($action eq 'set')
            {
               return unless (defined $value);

               if ($type eq 'tz')
               {
                  if ( DateTime::TimeZone->is_valid_name($value) )
                  {
                     $$store{users}{$id}{$type} = $value;
                     $storechanged = 1;
                     r_green( $channel, $msgid );
                  }
                  else
                  {
                     r_red( $channel, $msgid );
                  }
               }
               elsif ($type eq 'steamid')
               {
                  $value =~ s/\N{U+1F44D}/:1:/g;
                  $value =~ s/STEAM_1:/STEAM_0:/;

                  if ( $value =~ /STEAM_(0:[01]:[0-9]+)/n && !(exists $$store{steamidqueue}{$value}{$type} || exists $$steamidmap{$value}) )
                  {
                     $$store{steamidqueue}{$value}{$type}     = $value;
                     $$store{steamidqueue}{$value}{discordid} = $id;
                     $$store{steamidqueue}{$value}{msgid}     = $msgid;
                     $$store{steamidqueue}{$value}{chan}      = $channel;
                     $$store{steamidqueue}{$value}{ts}        = time;
                     $storechanged = 1;

                     $discord->create_reaction( $channel, $msgid, "\N{U+23F3}" );
                     $discord->send_message( $channel, "<\@$id> Within the next hour, join the twlz Sven Co-op server and type `!verify` in chat to verify your Steam ID." );
                  }
                  elsif ( exists $$store{steamidqueue}{$value}{$type} )
                  {
                     $discord->create_reaction( $channel, $msgid, "\N{U+23F3}" );
                  }
                  else
                  {
                     r_red( $channel, $msgid );
                  }
               }
               elsif ($type eq 'linknick')
               {
                  if (defined $value)
                  {
                     unless (defined $$store{users}{$id}{steamid})
                     {
                        r_red( $channel, $msgid );
                        $discord->send_message( $channel, "<\@$id> You have no Steam ID set, use `!set steamid STEAM_0:X:XXXXXX` first." );
                        return;
                     }

                     if ($value ~~ ['0', '1'])
                     {
                        $$store{users}{$id}{linknick} = $3;
                        r_green( $channel, $msgid );
                     }
                     else
                     {
                        r_what( $channel, $msgid );
                     }
                  }
                  else
                  {
                     r_what( $channel, $msgid );
                  }
               }
               else
               {
                  $$store{users}{$id}{$type} = $value;
                  $storechanged = 1;

                  r_green( $channel, $msgid );
               }
            }
            elsif ($action eq 'get')
            {
               if (defined $$store{users}{$id}{$type})
               {
                  $discord->send_message( $channel, "<\@$id> `$type: $$store{users}{$id}{$type}`" );
               }
               else
               {
                  r_red( $channel, $msgid );
               }
            }
         }
         elsif ( $msg =~ /^\.rem (total|list|delete) ?(.+)?/i && !($channel ~~ $$config{discord}{nocmdchans}->@*) && $id == $$config{discord}{owner_id} )
         {
            unless (defined $$store{reminders})
            {
               $discord->send_message( $channel, '`0 reminders`' );
               return;
            }

            if ($1 eq 'total')
            {
               $discord->send_message( $channel, '`' . scalar($$store{reminders}->@*) . '`' );
            }
            elsif ($1 eq 'list')
            {
               my $text = "id :: chan :: owner :: target :: text :: at (utc) :: in\n";
               $text   .= "===================================\n";

               for ($$store{reminders}->@*)
               {
                  next unless (defined $_);

                  $text .= "$_->{id} :: <#$_->{chan}> :: <\@$_->{owner}> :: " . ($_->{target} =~ /<\@!?$_->{owner}>/ ? 'owner' : $_->{target})
                        . " :: $_->{text} :: " . DateTime->from_epoch(epoch => $_->{time})->strftime('%F %R') . ' :: '
                        . duration(($_->{time} - time) + 71) . "\n";
               }

               while ($text =~ /\G(.{0,1990}(?:.\z|\R))/sg)
               {
                  my $message = {
                     'content' => $1,
                     'allowed_mentions' => { parse => [] },
                  };

                  $discord->send_message( $channel, $message );
               }
            }
            elsif ($1 eq 'delete')
            {
               if ($2 && $2 =~ /(?:#|id )(\d+)/i)
               {
                  $$store{reminders}->@* = grep { defined } map {
                     if ($1 == $_->{id})
                     {
                        r_green( $channel, $msgid );

                        $storechanged = 1;
                        undef $_;
                     }
                     else
                     {
                        $_
                     }
                  } $$store{reminders}->@*;
               }
            }
         }
         elsif ( $msg =~ /^!?rem(?:ind)?\s+(?:(?<target>[^\s\.]+)\s+)?(?:(?:in|at)\s+)?(?:(?<mins>\d{1,10})|(?:(?<day>\d\d)\.(?<month>\d\d)\.(?<year>\d{4})\s+)?(?<hm>\d\d:\d\d))(?:\s+(?:(?:to|that)\s+)?(?<text>.+)?)?$/i )
         # TODO: make d m y all optional
         # TODO: random time 3h-3d when "remind me to ..."?
         {
            my $target = ( !defined $+{target} || fc($+{target}) eq fc('me') ) ? "<\@$id>" : $+{target};
            my $delay  = $+{mins};
            my $text   = defined $+{text} ? $+{text} : "\N{U+23F0}";

            my $time;

            unless (defined $delay)
            {
               unless (exists $$store{users}{$id}{tz})
               {
                  $discord->send_message( $channel, "<\@$id> Set your local timezone (https://u.nu/7skv0) with `!set tz <Time/Zone>` first (case-sensitive!) E.g. `!set tz Asia/Omsk`" );
                  return;
               }

               my ($h, $m) = split(/:/, $+{hm}, 2);

               my $dt = DateTime->now( time_zone => $$store{users}{$id}{tz} );
               eval
               {
                  $dt->set( year   => $+{year}  ) if $+{year};
                  $dt->set( month  => $+{month} ) if $+{month};
                  $dt->set( day    => $+{day}   ) if $+{day};
                  $dt->set( hour   => $h        ) if $h;
                  $dt->set( minute => $m        ) if $m;
                  $time = $dt->epoch;
               };

               if ($@ || !$time || ($text && length($text) > 512))
               {
                  r_what( $channel, $msgid );
                  return;
               }

               $time += 24*60*60 if ($time < time);
            }
            else
            {
               if ($delay && $delay < 604800)
               {
                  $time = time + ($delay * 60);
               }
               else
               {
                  r_what( $channel, $msgid );
                  return;
               }
            }

            if ($time < time || $time > 7952342400)
            {
               r_what( $channel, $msgid );
               return;
            }

            $text =~ s'https?://''gmi;

            push( $$store{reminders}->@*, {
               id     => $$store{reminder_count}++,
               chan   => $channel,
               owner  => $id,
               target => $target,
               text   => $text,
               added  => time,
               time   => $time,
            });

            r_green( $channel, $msgid );
            #$discord->send_message( $channel, '`In: '. duration($time - time) . '`' );
         }
         elsif ( $msg =~ /^!time ?(.+)?/i )
         {
            my $tz = $1;

            unless (defined $tz)
            {
               if (exists $$store{users}{$id}{tz})
               {
                  $tz = $$store{users}{$id}{tz};
               }
               else
               {
                  $discord->send_message( $channel, "<\@$id> Set your local timezone (https://u.nu/7skv0) with `!set tz <Time/Zone>` first (case-sensitive!) E.g. `!set tz Asia/Omsk`" );
                  return;
               }
            }
            
            my $loc;

            unless ( DateTime::TimeZone->is_valid_name($tz) )
            {
               my $geo = Geo::Coder::Google->new(apiver => 3, language => 'en', key => $$config{'gmapikey'});

               my $input;
               eval { $input = $geo->geocode(location => $tz) };

               unless ( $input )
               {
                  r_red( $channel, $msgid );
                  return;
               }

               $loc = $input->{formatted_address};
               $tz  = (tz_by_coords($input->{geometry}{location}{lat}, $input->{geometry}{location}{lng}))[0];
            }

            my ($date, $time, $sname, $offset, $emoji, $m, $day, $month, $epoch, $week) = split(/#/, DateTime->now(time_zone => $tz)->strftime('%F#%T#%Z#%z#%l#%M#%A#%B#%s#%V'));
            $emoji =~ s/\s//g;
            $emoji .= '30' if ($m >= 30);

            my $embed = {
               'color' => '15844367',
                'title' => ':clock' . $emoji . ': **Time** ' . ($loc ? "in **$loc" : "for zone **$tz") . '**',
                'footer' => {
                   'text' => 'Day: ' . $day . ' / Month: ' . $month . ' / Epoch: ' . $epoch,
                },
                'fields' => [
                 {
                    'name'   => 'Time',
                    'value'  => $time,
                    'inline' => \1,
                 },
                 {
                    'name'   => 'Date',
                    'value'  => $date,
                    'inline' => \1,
                 },
                 {
                    'name'   => 'Week Number',
                    'value'  => $week,
                    'inline' => \1,
                 },
                 {
                    'name'   => 'Shortname',
                    'value'  => $sname,
                    'inline' => \1,
                 },
                 {
                    'name'   => 'UTC Offset',
                    'value'  => $offset,
                    'inline' => \1,
                 },
                 ],
            };

            push $$embed{'fields'}->@*, { 'name' => 'Zone ID', 'value' => $tz, 'inline' => \1, } if $loc;

            my $message = {
               'content' => '',
               'embed' => $embed,
            };

            $discord->send_message( $channel, $message );
         }
         elsif ( $msg =~ /^!help/i )
         {
            $discord->send_message( $channel, 'https://twlz.lifeisabug.com/gus' );
         }
      }
   });

   return;
}

sub discord_on_ready ()
{
   $discord->gw->on('READY' => sub ($gw, $hash)
   {
      add_me($hash->{'user'});
      $discord->status_update( { 'name' => $$config{'game'}, type => 0 } ) if ( $$config{'game'} );
   });

   return;
}

sub add_me ($user)
{
   $self->{'id'} = $user->{'id'};
   add_user($user);

   return;
}

sub add_user ($user)
{
   $self->{'users'}{$user->{'id'}} = $user;

   return;
}

sub add_guild ($guild)
{
   $self->{'guilds'}{$guild->{'id'}} = $guild;

   foreach my $channel ($guild->{'channels'}->@*)
   {
      $self->{'channels'}{$channel->{'id'}} = $guild->{'id'};
      $self->{'channelnames'}{$channel->{'id'}} = $channel->{'name'}
   }

   foreach my $role ($guild->{'roles'}->@*)
   {
      $self->{'rolenames'}{$role->{'id'}} = $role->{'name'};
   }

   return;
}

sub duration ($sec)
{
   my @gmt = gmtime($sec);

   $gmt[5] -= 70;
   return   ($gmt[5] ?                                            $gmt[5].'y' : '').
            ($gmt[7] ? ($gmt[5]                       ? ' ' : '').$gmt[7].'d' : '').
            ($gmt[2] ? ($gmt[5] || $gmt[7]            ? ' ' : '').$gmt[2].'h' : '').
            ($gmt[1] ? ($gmt[5] || $gmt[7] || $gmt[2] ? ' ' : '').$gmt[1].'m' : '');
}

sub elev_by_coords ($lat, $lon)
{
   my $json = get('https://maps.googleapis.com/maps/api/elevation/json?key=' . $$config{'gmapikey'} . '&locations=' . $lat . ',' . $lon);

   if ($json)
   {
      my $elevdata = decode_json($json);
      return $$elevdata{results}[0]{elevation} if ( $$elevdata{status} eq 'OK' );
   }

   return;
}

sub tz_by_coords ($lat, $lon)
{
   my $json = get('https://maps.googleapis.com/maps/api/timezone/json?language=en&timestamp=' . time . '&key=' . $$config{'gmapikey'} . '&location=' . $lat . ',' . $lon);

   if ($json)
   {
      my $tzdata = decode_json($json);
      return ($$tzdata{timeZoneId}, $$tzdata{timeZoneName}) if ($$tzdata{status} eq 'OK' && DateTime::TimeZone->is_valid_name($$tzdata{timeZoneId}));
   }

   return;
}

sub verify ($steamid)
{
   if ( defined $$store{steamidqueue}{$steamid} )
   {
      $$store{users}{$$store{steamidqueue}{$steamid}{discordid}}{steamid} = $steamid;
      $$steamidmap{$steamid} = $$store{steamidqueue}{$steamid}{discordid};
      $storechanged = 1;

      $discord->delete_all_reactions_for_emoji( $$store{steamidqueue}{$steamid}{chan}, $$store{steamidqueue}{$steamid}{msgid}, "\N{U+23F3}" );
      $discord->add_guild_member_role( $$config{discord}{guild_id}, $$store{steamidqueue}{$steamid}{discordid}, $$config{discord}{ver_role} );
      $discord->send_message( $$store{steamidqueue}{$steamid}{chan}, "<\@$$store{steamidqueue}{$steamid}{discordid}> <:greentick:712004372678049822> You have successfully validated your Steam ID! Chat relay access granted. Use `!set linknick 1` in here to show your in-game nick in <#$$config{discord}{linkchan}> as your Discord nickname." );
      r_green( $$store{steamidqueue}{$steamid}{chan}, $$store{steamidqueue}{$steamid}{msgid} );

      delete $$store{steamidqueue}{$steamid};
   }

   return;
}

sub r_green ($channel, $msgid)
{
   $discord->create_reaction( $channel, $msgid, ':greentick:712004372678049822' );
   return;
}

sub r_red ($channel, $msgid)
{
   $discord->create_reaction( $channel, $msgid, ':redtick:712004372707541003' );
   return;
}

sub r_what ($channel, $msgid)
{
   $discord->create_reaction( $channel, $msgid, ':what:660870075607416833' );
   return;
}

sub r_pepe ($channel, $msgid)
{
   $discord->create_reaction( $channel, $msgid, ':PepeHands:557286043548778499' );
   return;
}

sub quit ($)
{
   DumpFile($$config{store}, $store);
   say "\n" . 'Saved.';
   exit;
}
