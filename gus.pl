#!/usr/bin/env perl

# Gus - Discord bot for the twilightzone Sven Co-op server
#
# Requires https://github.com/vsTerminus/Mojo-Discord
# Based on https://github.com/vsTerminus/Goose
#
# Copyright 2017-2021, Nico R. Wohlgemuth <nico@lifeisabug.com>

use v5.28.0;

use utf8;
use strict;
use warnings;
use autodie ':all';

use lib '/etc/perl';

use feature 'signatures';
no warnings qw(experimental::signatures experimental::smartmatch);

binmode( STDOUT, ":encoding(UTF-8)" );

local $SIG{INT} = \&quit;

use DBI;
use DBD::SQLite::Constants ':file_open';
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
$ua->timeout( 3 );
$ua->default_header('Accept-Encoding' => HTTP::Message::decodable);

my $self;
my ($store, $storechanged, $lastmap, $retries, $maptime, $cache) = ({}, 0, '?', 0, 0, {});

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
   aqiapikey    => '',

   discord => {
      linkchan   => 458683388887302155,
      mainchan   => 458323696910598167,
      mediachan  => 615139520135954453,
      vipchan    => 748823540496597013,
      ayayachan  => 459345843942588427,
      nocmdchans => [706113584626663475, 610862900357234698, 698803767512006677],

      client_id  => 393059875871260672,
      owner_id   => 373912992758235148,
      guild_id   => 458323696910598165,

      ver_role   => 712296542211670088,
   }
};

my $discord = Mojo::Discord->new(
   'version'   => '9999',
   'url'       => 'https://twlz.lifeisabug.com',
   'token'     => '',
   'reconnect' => 1,
   'verbose'   => 1,
   'logdir'    => "$ENV{HOME}/gus",
   'logfile'   => 'discord.log',
   'loglevel'  => 'debug',
);

my $maps = {
   'asmap00'              => ':sheep: Azure Sheep',
   'ba_tram1'             => '<:flower:772815800712560660> HL: Blue Shift',
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
   'hl_c00'               => '<:flower:772815800712560660> Half-Life',
   'island'               => ':island: Comfy, island',
   'mustard_b'            => ':hotdog: Mustard Factory',
   'of0a0'                => '<:flower:772815800712560660> HL: Opposing Force',
   'of_utbm'              => ':new_moon: OP4: Under the Black Moon',
   'otokotati_no_kouzan'  => ':hammer_pick: Otokotati No Kouzan',
   'pizza_ya_san1'        => ':pizza: Pizza Ya San: 1',
   'pizza_ya_san2'        => ':pizza: Pizza Ya San: 2',
   'po_c1m1'              => ':regional_indicator_p: Poke 646',
   'projectg1'            => ':dromedary_camel: Project: Guilty',
   'pv_c1m1'              => ':regional_indicator_v: Poke 646: Vendetta',
   'quad_f'               => '<:blanky:805497042612912158> Quad',
   'ra_quad'              => '<:blanky:805497042612912158> Real Adrenaline Quad',
   'ressya_no_tabi'       => ':train2::camera_with_flash: Ressya No Tabi',
   'restriction01'        => ':radioactive: Restriction',
   'road_to_shinnen'      => ':shinto_shrine: Oh god, oh no, Road to Shinnen',
   'rust_islands'         => '<:eecat:460442390457483274> R U S T',
   'rust_legacy'          => '<:eecat:460442390457483274> (legacy) R U S T',
   'rust_mini'            => '<:eecat:460442390457483274> (mini) R U S T',
   'sa13'                 => '<:KannaSuicide:603609334080995338> SA13',
   'sc_royals1'           => ':eye: Royals',
   'sc_tl_build_puzzle_fft_final' => '<:PepeKek:603647721496248321> Build Puzzle',
   'th_ep1_01'            => '<:irlmaier:460382258336104448> They Hunger: Episode 1',
   'th_ep2_00'            => '<:irlmaier:460382258336104448> They Hunger: Episode 2',
   'th_ep3_00'            => '<:irlmaier:460382258336104448> They Hunger: Episode 3',
   'th_escape'            => '<:KannaSpook:603856338132664321> They Hunger: Escape',
   'the_daikon_warfare1'  => ':seedling: The Daikon Warfare',
   'tunnelvision_1'       => '<:KannaZooming:640195746444083200> Tunnel Vision',
   'uboa'                 => ':rice_ball: UBOA',
};

#my $discord_markdown_pattern = qr/(?<!\\)(`|@|:|#|\||__|\*|~|>)/;
my $discord_markdown_pattern = qr/(?<!\\)(`|@|#|\||_|\*|~|>)/;

###

my $gi = MaxMind::DB::Reader->new(file => $$config{'geo'});

my $dbh = DBI->connect("dbi:SQLite:$$config{'db'}", undef, undef, {
   RaiseError => 1,
   sqlite_open_flags => SQLITE_OPEN_READONLY,
});

DumpFile($$config{store}, $store) unless (-f $$config{store});
$store = LoadFile($$config{store});

discord_on_ready();
discord_on_message_create();

$discord->init();

open my $fh, '<', $$config{'fromsven'};

my $filestream = IO::Async::FileStream->new(
   read_handle => $fh,

   interval => 0.5,

   on_initial => sub ($self, $)
   {
      $self->seek_to_last( "\n" );
   },

   on_read => sub ($self, $buffref, $)
   {
      return unless ($discord->connected);

      while ( $$buffref =~ s/^(.*\n)// )
      {
         my $line = decode_utf8_lax($1);

         chomp( $line );

         if ( $line =~ /^mapend .+ [0-9][0-9]?$/ )
         {
            say localtime(time) . " -- mapend: $line";

            my @data = split( ' ', $line );

            if ( $data[1] eq '_server_start' )
            {
               $discord->send_message( $$config{discord}{linkchan}, '<:Surprised:640195746963914802> **Server restarted** <:wojakrage:800709248500891648> Last map was: `' . $lastmap . '`' );
               return;
            }

            return if ( $data[2] eq '0' );

            my ($after, $sec) = ('', 0);
            $sec   = time - $maptime if $maptime;
            $after = ' after `' . duration($sec+5) . '`' if ($sec > 60);
            $maptime = 0;

            $discord->send_message( $$config{discord}{linkchan}, ":checkered_flag: Map `$data[1]` ended$after" );
         }
         elsif ( $line =~ /^status .+ [0-9][0-9]?$/ )
         {
            say localtime(time) . " -- status: $line";

            my @data = split( ' ', $line );

            $discord->status_update( { 'name' => 'SC on ' . $data[1], type => 0 } );

            $maptime = time;

            if ($lastmap eq $data[1])
            {
               $retries++;
            }
            else
            {
               $retries = 0;
            }

            if ( $data[2] eq '0' )
            {
               $lastmap = $data[1];
               return;
            }

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

            push $$embed{'fields'}->@*, { 'name' => 'Attempt',  'value' => '#' . $retries, 'inline' => \1, } if ($retries > 0);

            my $message = {
               'content' => '',
               'embed' => $embed,
            };
            
            $discord->send_message( $$config{discord}{linkchan}, $message );

            if ( exists $$maps{$data[1]} && $data[1] ne $lastmap )
            {
               my $s = '';
               $s = 's' if ( $data[2] > 1 );
               $discord->send_message( $$config{discord}{mainchan}, "**$$maps{$data[1]}** has started with **$data[2]** player$s!" );
            }

            $lastmap = $data[1];
         }
         else
         {
            $line =~ /<(.+?)><(?:(.+?):.+?)?><(.+?)> (.+)/;
            say localtime(time) . " -> $line";

            my $nick    = $1;
            my $ip      = $2;
            my $steamid = $3;
            my $msg     = $4;

            my $r = $gi->record_for_address($ip) if(!$$cache{$steamid}{cc} && $ip);

            return if ($msg =~ /^\.(vc|cspitch) /);
            return if ($msg =~ /^\/[a-z]$/);

            return if (exists $$cache{$steamid}{antispam} && $msg eq $$cache{$steamid}{antispam});
            $$cache{$steamid}{antispam} = $msg;

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

            $msg = '_\*' . substr($msg, 4) . '\*_' if ($msg =~ /^\/me /);

            my $clearcache;

            my $final = "`$nick`  $msg";
            if ($line =~ /^- /)
            {
               $final =~ s/^/<:gtfo:603609334781313037> /;
               $clearcache++;
            }
            $final =~ s/^/<:NyanPasu:562191812702240779> / if ($line =~ /^\+ /);

            $$cache{$steamid}{cc} = lc($r->{country}{iso_code}) if (!$$cache{$steamid}{cc} && $ip && $r->{country}{iso_code});

            my $message = {
               content => ':' . ($$cache{$steamid}{cc} ? ('flag_' . $$cache{$steamid}{cc}) : 'gay_pride_flag') . ': ' . $final,
               allowed_mentions => { parse => [] },
            };

            $discord->send_message( $$config{discord}{linkchan}, $message );

            delete $$cache{$steamid} if $clearcache;
         }
      }

      return;
   }
);

my $timer = IO::Async::Timer::Periodic->new(
   interval => 15,

   on_tick => sub ($) {
      DumpFile($$config{store}, $store) if $storechanged;
      $storechanged = 0;

      for (keys $$store{steamidqueue}->%*)
      {
         delete $$store{steamidqueue}{$_} unless (exists $$store{steamidqueue}{$_}{ts} && (($$store{steamidqueue}{$_}{ts} + 3600) > time));
         $storechanged = 1;
      }

      return unless (defined $$store{reminders} && $discord->connected);

      while (my ($k, $v) = each $$store{reminders}->%*)
      {
         if (defined $$v{time} && $$v{time} <= time)
         {
            my @allowed;

            if ($$v{target} =~ /^<@!?(\d+)>$/)
            {
               if ($1 != $$v{owner})
               {
                  push(@allowed, $1);
                  $$v{text} .= " (reminded by <\@$$v{owner}>)";
               }
            }

            push(@allowed, $$v{owner}) unless @allowed;

            my $message = {
               'content' => $$v{target} . ' ' . $$v{text},
               'allowed_mentions' => { users => [@allowed] },
            };

            $discord->send_message( $$v{chan}, $message );

            $storechanged = 1;
            delete $$store{reminders}{$k};
         }
      }
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
            $msg =~ s/<a?(:[^:.]+:)\d+>/$1/g; # emoji

            return unless $msg;

            my $nick = defined $$member{'nick'} ? $$member{'nick'} : $$author{'username'};
            $nick =~ s/`//g;
            $nick =~ s/%/%%/g;
            $nick =~ s/(\R|\s)+/ /gn;

            say localtime(time) . " <- <$nick> $msg";

            open (my $tosvenfh, '>>:encoding(UTF-8)', $$config{'tosven'});
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
                       'value'  => lc($r->[11]) eq 'us' ? ':gay_pride_flag:' : ':flag_'.($r->[11] ? lc($r->[11]) : 'white').':',
                       'inline' => \1,
                    },
                    {
                       'name'   => 'Time on TWLZ',
                       'value' => $r->[14] < 1 ? '-' : duration( $r->[14]*30 ) . ' +',
                       'inline' => \1,
                    },
                    {
                       'name'   => 'First Seen',
                       'value'  => defined $r->[17] ? $r->[17] : 'Unknown',
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
            #my ($aqi_num, $aqi_txt) = aqi_by_coords($lat, $lon);

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
                #'description' => sprintf('**%s**%s', $w->symbol_txt, (defined $aqi_num ? ' (Air quality: ' . $aqi_txt . ')' : '')),
                'description' => sprintf('**%s**', $w->symbol_txt),
                'thumbnail' => {
                   'url'    => sprintf('%s/%s.%s', $symbolurl, $w->symbol, $symboltype),
                },
                'footer' => {
                   'text' => sprintf('Elevation: %dm (%dft) / Local time: %s / Forecast for: %s-%s', int($alt), int($alt * 3.2808), DateTime->now(time_zone => $tz)->strftime('%R'),  DateTime->from_epoch(epoch => ($w->forecast_time), time_zone => $tz)->strftime('%R'), DateTime->from_epoch(epoch => $w->forecast_time+3600, time_zone => $tz)->strftime('%R')),
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
                    'value'  => sprintf('%s, %.2g m/s from %s', $w->windspeed_bft_txt, $w->windspeed_ms, $w->windfrom_dir),
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
         elsif ( $msg =~ /^!img ?(.+)?/i && $channel eq $$config{discord}{vipchan} )
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
            my $ua = LWP::UserAgent->new( agent => 'Mozilla/5.0', timeout => 3 );
            my $r = $ua->get( $neko, 'Content-Type' => 'application/json', 'Accept-Encoding' => HTTP::Message::decodable );
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
         elsif ( $msg =~ /^!ud (.+)/i && $channel eq $$config{discord}{mediachan} )
         {
            my $input = $1;
            my $query = uri_escape( $input );
            my $ua = LWP::UserAgent->new( agent => 'Mozilla/5.0', timeout => 3 );
            $ua->agent( ssl_opts => { verify_hostname => 0 } );
            my $r = $ua->get( "https://api.urbandictionary.com/v0/define?term=$query", 'Content-Type' => 'application/json', 'Accept-Encoding' => HTTP::Message::decodable );
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
            my $r = $ua->get( $url, 'Content-Type' => 'application/json', 'Accept-Encoding' => HTTP::Message::decodable );
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
         elsif ( $msg =~ /^!(set|get) (tz|steamid) ?(.*)?/i && !($channel ~~ $$config{discord}{nocmdchans}->@*) )
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

                  if ( $value =~ /STEAM_(0:[01]:[0-9]+)/n && !exists $$store{steamidqueue}{$value} )
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
                  elsif ( exists $$store{steamidqueue}{$value} )
                  {
                     $discord->create_reaction( $channel, $msgid, "\N{U+23F3}" );
                  }
                  else
                  {
                     r_red( $channel, $msgid );
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
         elsif ( $msg =~ /^\.rem (total|list|del(?:ete)?) ?(.+)?/i && !($channel ~~ $$config{discord}{nocmdchans}->@*) && $id == $$config{discord}{owner_id} )
         {
            unless (defined $$store{reminders} && scalar(keys $$store{reminders}->%*))
            {
               $discord->send_message( $channel, '`0`' );
               return;
            }

            if ($1 eq 'total')
            {
               $discord->send_message( $channel, '`' . scalar(keys $$store{reminders}->%*) . '`' );
            }
            elsif ($1 eq 'list')
            {
               # TODO: allow users to use DM for list and delete + translate to users tz
               my $text = "id :: chan :: owner :: target :: text :: at (utc) :: in\n";
               $text   .= "===================================\n";

               for (sort keys $$store{reminders}->%*)
               {
                  next unless (defined $$store{reminders}{$_});

                  $text .= "$_ :: <#$$store{reminders}{$_}{chan}> :: <\@$$store{reminders}{$_}{owner}> :: " . ($$store{reminders}{$_}{target} =~ /<\@!?$$store{reminders}{$_}{owner}>/ ? 'owner' : $$store{reminders}{$_}{target})
                        . " :: $$store{reminders}{$_}{text} :: " . DateTime->from_epoch(epoch => $$store{reminders}{$_}{time})->strftime('%F %R') . ' :: '
                        . duration($$store{reminders}{$_}{time} - time) . "\n";
               }

               while ($text =~ /\G(.{0,1990}(?:.\z|\R))/sg)
               {
                  my $message = {
                     'content' => $1,
                     'allowed_mentions' => { parse => [] },
                  };

                  #$discord->send_message( $channel, $message );
                  $discord->send_message_content_blocking( $channel, $message );
               }
            }
            elsif ($1 eq 'del' || $1 eq 'delete')
            {
               if ($2 && $2 =~ /(?:#|id )(\d+)/i)
               {
                  for (keys $$store{reminders}->%*)
                  {
                     if ($1 == $_)
                     {
                        delete $$store{reminders}{$_};
                        $storechanged = 1;

                        r_green( $channel, $msgid );
                     }
                  }
               }
            }
         }
         elsif ( $msg =~ /^!?rem(?:ind)?\s+(?:(?<target>[^\s-]+)\s+)?(?:(?:in|at)\s+)?(?:(?<mins>\d+)|(?:(?<year>\d{4})-?(?<month>\d\d)-?(?<day>\d\d)\s+)?(?<hm>\d\d:\d\d))(?:\s+(?:(?:to|that)\s+)?(?<text>.+)?)?$/i )
         # TODO: make y m d all optional
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

            $$store{reminders}{$$store{reminder_count}++} = {
               time   => $time,
               chan   => $channel,
               owner  => $id,
               target => $target,
               text   => $text,
               added  => time,
            };

            $storechanged = 1;

            if ($delay && $delay <= 360)
            {
               r_green( $channel, $msgid );
            }
            else
            {
               $discord->send_message( $channel, "<\@$id> <:greentick:712004372678049822> `T-minus ". duration($time - time) . '`' );
            }
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

   return ($gmt[5] ?                                                       $gmt[5].'y' : '').
          ($gmt[7] ? ($gmt[5]                                  ? ' ' : '').$gmt[7].'d' : '').
          ($gmt[2] ? ($gmt[5] || $gmt[7]                       ? ' ' : '').$gmt[2].'h' : '').
          ($gmt[1] ? ($gmt[5] || $gmt[7] || $gmt[2]            ? ' ' : '').$gmt[1].'m' : '').
          ($gmt[0] ? ($gmt[5] || $gmt[7] || $gmt[2] || $gmt[1] ? ' ' : '').$gmt[0].'s' : '');
}

sub aqi_by_coords ($lat, $lon)
{
   my $json = get('https://api.waqi.info/feed/geo:' . $lat . ';' . $lon . '/?token=' . $$config{'aqiapikey'});

   if ($json)
   {
      my $aqidata = decode_json($json);

      if ( $$aqidata{status} eq 'ok' )
      {
         my $i;
         my @txt = ('Good', 'Moderate', 'Unhealthy for Sensitive Groups', 'Unhealthy', 'Very Unhealthy', 'Hazardous');
         my $aqi = $$aqidata{data}{aqi};

         given ( $aqi )
         {
            when ( $_ < 50 )
            {
               $i = 0;
            }
            when ( $_ < 100 )
            {
               $i = 1;
            }
            when ( $_ < 150 )
            {
               $i = 2;
            }
            when ( $_ < 200 )
            {
               $i = 3;
            }
            when ( $_ < 300 )
            {
               $i = 4;
            }
            when ( $_ >= 300 )
            {
               $i = 5;
            }
         }

         return ($aqi, $txt[$i]);
      }
   }

   return;
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
      $discord->delete_all_reactions_for_emoji( $$store{steamidqueue}{$steamid}{chan}, $$store{steamidqueue}{$steamid}{msgid}, "\N{U+23F3}" );
      $discord->add_guild_member_role( $$config{discord}{guild_id}, $$store{steamidqueue}{$steamid}{discordid}, $$config{discord}{ver_role} );
      $discord->send_message( $$store{steamidqueue}{$steamid}{chan}, "<\@$$store{steamidqueue}{$steamid}{discordid}> <:greentick:712004372678049822> You have successfully validated your Steam ID! VIP status granted." );
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
