#!/usr/bin/env perl

# Gus - Discord bot for the twilightzone Sven Co-op server
#
# Requires https://github.com/vsTerminus/Mojo-Discord
# Based on https://github.com/vsTerminus/Goose
#
# Copyright 2017-2022, Nico R. Wohlgemuth <nico@lifeisabug.com>

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

use DBD::SQLite::Constants ':file_open';
use DBI;
use DateTime::TimeZone;
use DateTime;
use Encode::Simple qw(encode_utf8_lax decode_utf8_lax);
use File::Basename;
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
use POSIX 'floor';
use Term::Encoding 'term_encoding';
use URI::Escape;
use Weather::METNO;
use YAML::Tiny qw(LoadFile DumpFile);

$ua->agent( 'Mozilla/5.0' );
$ua->timeout( 3 );
$ua->default_header('Accept-Encoding' => HTTP::Message::decodable);

my ($guild, $users, $started, $ready, $readyc, $resumed, $resumedc)
=  (undef,  undef,  time,     0,      0,       0,        0        );
my ($store, $storechanged, $lastmap, $retries, $maptime, $cache)
=  ({},     0,             '',       0,        0,        {}    );
my ($emojis)
=  ({}     );

my $config = {
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
   waappid      => '',

   discord => {
      linkchan   => 458683388887302155,
      mainchan   => 458323696910598167,
      mediachan  => 615139520135954453,
      #vipchan    => 748823540496597013,
      vipchan    => 0,
      ayayachan  => 459345843942588427,
      trashchan  => 512991515744665600,
      jailchan   => 916442377105854504,
      nocmdchans => [706113584626663475, 610862900357234698, 698803767512006677],

      client_id  => 393059875871260672,
      owner_id   => 373912992758235148,
      guild_id   => 458323696910598165,

      ver_role   => 712296542211670088,
      jail_role  => 916442703225561089
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
   'loglevel'  => 'info',
);

my $maps = {
   'ba_tram1'             => '<:flower:772815800712560660> HL: Blue Shift',
   'ba_tram_mv2'          => '<:flower:772815800712560660> HL: Blue Shift',
   'bm_nightmare_a_final' => '<:scary:516921261688094720> Black Mesa Nightmare',
   'bm_sts'               => '<:sven:459617478365020203> Black Mesa Special Tactics Sector',
   'botparty'             => '<:omegalul:458685801706815489> Bot Party',
   'botrace'              => '<:happy:555506080793493538> Bot Race',
   'dy_accident1'         => ':person_in_motorized_wheelchair: HL: Decay',
   'echoes08'             => '<:wow:516921262199799818> HL: Echoes',
   'escape_series_1a'     => ':runner: Escape Series: Part 1',
   'escape_series_2a'     => ':runner: Escape Series: Part 2',
   'escape_series_3a'     => ':runner: Escape Series: Part 3',
   'f_island'             => ':island: Comfy, the other island map',
   'f_island_v2'          => ':island: Comfy, the other island map',
   'fallguys'             => ':person_doing_cartwheel::person_doing_cartwheel: Fall Guys',
   'hidoi_map1'           => '<:BAKA:603609334550888448> ....(^^;) Hidoi Map',
   'hl_c01_a1'            => '<:flower:772815800712560660> Half-Life',
   'island'               => ':island: Comfy, island',
   'mustard_b'            => ':hotdog: Mustard Factory',
   'of0a0'                => '<:flower:772815800712560660> HL: Opposing Force',
   'of1a1_mv2'            => '<:flower:772815800712560660> HL: Opposing Force',
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
   'sc_tl_build_puzzle_fft_final' => '<:PepeKek:603647721496248321> Build Puzzle',
   'shockraid_jungle'     => ':tanabata_tree: ShockRaid Jungle',
   'th_ep1_01'            => '<:irlmaier:460382258336104448> They Hunger: Episode 1',
   'th_ep2_00'            => '<:irlmaier:460382258336104448> They Hunger: Episode 2',
   'th_ep3_00'            => '<:irlmaier:460382258336104448> They Hunger: Episode 3',
   'th_escape'            => '<:KannaSpook:603856338132664321> They Hunger: Escape',
   'the_daikon_warfare1'  => ':seedling: The Daikon Warfare',
   'tunnelvision_1'       => '<:KannaZooming:640195746444083200> Tunnel Vision',
   'uboa'                 => ':rice_ball: UBOA',
};

my $reactions = {
   'green'  => ':greentick:712004372678049822',
   'red'    => ':redtick:712004372707541003',
   'what'   => ':what:660870075607416833',
   'pepe'   => ':PepeHands:557286043548778499',
   'ia'     => ':Inshallah:953722958021550190',
   'map'    => "\N{U+1F5FA}",
   'change' => "\N{U+1F504}",
   'wait'   => "\N{U+23F3}",
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
discord_on_guild_create();
discord_on_resumed();
discord_on_message_create();
discord_on_message_delete();
discord_on_guild_member_remove();

$discord->init();

open my $fh, '<', $$config{'fromsven'};

my $filestream = IO::Async::FileStream->new(
   read_handle => $fh,

   read_all => 1,
   interval => 1,

   on_initial => sub ($self, $)
   {
      $self->seek_to_last( "\n" );
   },

   on_read => sub ($self, $buffref, $)
   {
      return unless $discord->connected;

      while ( $$buffref =~ s/^(.*\n)// )
      {
         $$cache{msgin}++;

         my $line = decode_utf8_lax( $1 );

         chomp( $line );

         if ( $line =~ /^(?:\d+) mapend .+ [0-9][0-9]?$/ )
         {
            say localtime(time) . ' => ' . $line;

            my @data = split( ' ', $line );

            $$cache{mapchanges}++;
            $$cache{mapchangetime} = time;

            if ( $data[2] eq '_server_start' )
            {
               #$cache = {};

               my $add = '';
               $add = ' <:wojakrage:800709248500891648> Last map was: `' . $lastmap . '`' if ($lastmap && $lastmap ne '_server_start');
               $discord->send_message( $$config{discord}{linkchan}, '<:Surprised:640195746963914802> **Server restarted**' . $add );

               return;
            }

            return if ( $data[3] == 0 );

            my ($after, $sec) = ('', 0);
            $sec   = time - $maptime if $maptime;
            $after = ' after `' . duration($sec) . '`' if ($sec > 30);
            $maptime = 0;

            $discord->send_message( $$config{discord}{linkchan}, ":checkered_flag: Map `$data[2]` ended$after" );
         }
         elsif ( $line =~ /^(?:\d+) status .+ [0-9][0-9]? .+$/ )
         {
            say localtime(time) . ' => ' . $line;

            my @data = split( ' ', $line );

            $maptime = time-5;

            if ($lastmap eq $data[2])
            {
               $retries++;
            }
            else
            {
               $retries = 0;
               $discord->status_update( { 'name' => 'SC on ' . $data[2], type => 0 } );
            }

            if ( $data[3] == 0 )
            {
               $lastmap = $data[2];
               return;
            }

            my $embed = {
               'color' => randcol(),
               'provider' => {
                  'name' => 'twlz',
                  'url' => 'https://twlz.lifeisabug.com',
                },
                'fields' => [
                {
                   'name'   => 'Map',
                   'value'  => $data[2],
                   'inline' => \1,
                },
                {
                   'name'   => 'Players',
                   'value'  => $data[3],
                   'inline' => \1,
                },
                ],
            };

            push $$embed{'fields'}->@*, { 'name' => 'Difficulty', 'value' => $1.'%',             'inline' => \1, } if ($line =~ /diff(?:iculty)?: (.+)%/);
            push $$embed{'fields'}->@*, { 'name' => 'Attempt',    'value' => '#' . ($retries+1), 'inline' => \1, } if ($retries);

            my $message = {
               'content' => '',
               'embed' => $embed,
            };
            
            $discord->send_message( $$config{discord}{linkchan}, $message );

            my $pingstring = '';

            if (defined $$store{pings}{$data[2]})
            {
               $pingstring .= "<\@$_> " for (keys $$store{pings}{$data[2]}->%*);
               $pingstring .= '<:ping:640195746074853409>';
               delete $$store{pings}{$data[2]};
               $storechanged = 1;
            }

            if ( exists $$maps{$data[2]} && $data[2] ne $lastmap )
            {
               my $s = '';
               $s = 's' if ( $data[3] > 1 );
               $discord->send_message( $$config{discord}{mainchan}, "**$$maps{$data[2]}** has started with **$data[3]** player$s! $pingstring" );
            }
            elsif ( $pingstring )
            {
               $discord->send_message( $$config{discord}{mainchan}, "**$data[2]** is now starting! $pingstring" );
            }

            $lastmap = $data[2];
         }
         elsif ( $line =~ /^(\d+) plugin ([^ ]+) (.+)$/ )
         {
            return unless ($2 && defined $3);

            say localtime(time) . ' => ' . $line;

            my $ts     = $1;
            my $caller = $2;
            my $msg    = $3;

            my $td = time - $ts;
            say localtime(time) . ' !! warning: previous message desynced by: ' . $td . 's!' if ($td > 3);

            $msg =~ s/`//g;
            $msg =~ s/(\s|\R)+/ /g;
            $msg =~ s/\@+everyone/everyone/g;
            $msg =~ s/\@+here/here/g;

            given ( $caller )
            {
               when ( 'Radio' )
               {
                  my @data = split(/\|/, $msg, 3);

                  $msg = ':musical_note: ' . ($data[2] eq '(none)' ? 'N' : ('Dj `' . $data[2] . '` is n')) . 'ow playing `' . $data[1] . '` on `' . $data[0] . '`';
               }
               when ( [qw(MapModule ForceSurvival SMaker)] )
               {
                  my @data = split(/\\/, $msg);

                  if ( $data[0] eq 'point_checkpoint' )
                  {
                     $msg = ( $$cache{$data[1]}{cc} ? ":flag_$$cache{$data[1]}{cc}:" : ':triangular_flag_on_post:' ) . ' <:ShyGalDelet:712015481997099138> `' . $data[2] . '`  _' . $data[3] . '_ <:sven:459617478365020203>';
                  }
                  else
                  {
                     continue;
                  }
               }
               when ( 'Trails' )
               {
                  my @data = split(/\\/, $msg);

                  if ( $data[0] eq 'score')
                  {
                     my $names = join('` & `', @data[2..$#data]);

                     $msg = ':dna: Trails: `' . $names . '` scored `' . $data[1] . '` points' . ($#data > 2 ? ' (tied)' : '');
                  }
                  elsif ( $data[0] eq 'rambo')
                  {
                     my $text = join(' ', @data[1..$#data]);

                     $msg = ':dna: Trails: `' . $text . '`'; 
                  }
               }
               when ( 'PartyMode' )
               {
                  if ( $msg =~ /LOL PARTY/ )
                  {
                     $msg = ':partying_face: :tada: `' . $msg . '`';
                  }
                  else
                  {
                     $msg = ':partying_face: :angry: `' . $msg . '`';
                  }
               }
               default
               {
                  $msg = '<:sven:459617478365020203> `' . $caller . '`  ' . $msg;
               }
            }

            my $message = {
               content => $msg,
               allowed_mentions => { parse => [] },
            };

            $discord->send_message( $$config{discord}{linkchan}, $message );
         }
         else
         {
            $line =~ /^([0-9]+) <(observer|alive|dead|player|\+|-)>\\<(.+)>\\<(?:([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}):[0-9]+)?><(STEAM_0:[01]:[0-9]+)> (.+)$/;

            return unless ($5 && defined $6);

            say localtime(time) . ' -> ' . $line;

            my $ts      = $1;
            my $status  = $2;
            my $nick    = $3;
            my $ip      = $4;
            my $steamid = $5;
            my $msg     = $6;

            my $td = time - $ts;
            say localtime(time) . ' !! warning: previous message desynced by: ' . $td . 's!' if ($td > 3);

            if ( $steamid eq 'STEAM_0:0:19542618') # Mic-Chan
            {
               $$cache{$steamid}{cc} = '';
            }
            elsif ( !$$cache{$steamid}{cc} && $ip )
            {
               my $r = $gi->record_for_address($ip);
               $$cache{$steamid}{cc} = lc($r->{country}{iso_code}) if $r->{country}{iso_code};
            }

            return if ($msg =~ /^\.(?:vc|cspitch|lagc|lost|ping) /i);
            return if ($msg =~ /^[\/\.][a-z]$/);
            return if ($msg =~ /^diff$/);

            return if (exists $$cache{$steamid}{antispam} && $msg eq $$cache{$steamid}{antispam});
            $$cache{$steamid}{antispam} = $msg;

            $nick =~ s/`//g;

            $msg =~ s/(\s|\R|\N{U+1160})+/ /g;
            $msg =~ s/\@+everyone/everyone/g;
            $msg =~ s/\@+here/here/g;
            $msg =~ s/$discord_markdown_pattern/\\$1/g;

            my @m = $msg =~ /:([^:.]+):/g;
            for (@m)
            {
               my $e = $_;
               $e =~ s/\\_/_/g if ($e =~ /\\_/);

               if (exists $$emojis{$e})
               {
                  if ($$emojis{$e}{animated})
                  {
                     $msg =~ s/:\Q$_\E:/<a:$e:$$emojis{$e}{id}>/g;
                  }
                  else
                  {
                     $msg =~ s/:\Q$_\E:/<:$e:$$emojis{$e}{id}>/g;
                  }
               }
               else
               {
                  $msg =~ s/:\Q$_\E:/:$e:/g;
               }
            }

            if ($msg =~ /^!verify/ )
            {
                verify($steamid);
                return;
            }

            my ($final, $emoji, $clearcache) = ('', '', 0);

            given ( $status )
            {
               when ( 'observer' )
               {
                  $emoji = ':telescope: ';
               }
               when ( 'alive' )
               {
                  $emoji = '<:ShyGalDelet:712015481997099138> ';
               }
               when ( 'dead' )
               {
                  $emoji = '<:rip:462250760038776832> ';
               }
               when ( '+' )
               {
                  $$cache{today}{$steamid}++;

                  return if ($$cache{$steamid}{active} && time - $$cache{$steamid}{active} < 43200); # expire join cache after 12h of "activity"

                  $emoji = '<:NyanPasu:562191812702240779> ';
                  $msg = '_' . $msg . '_';

                  $$cache{$steamid}{active} = time;

                  return if ($$cache{mapchanges} && $$cache{mapchanges} == 1 && time - $$cache{mapchangetime} < 60); # prevent join flood after Gus restart
               }
               when ( '-' )
               {
                  if ( $nick eq '\orphan' )
                  {
                     delete $$cache{$steamid};
                     $$cache{ghosted}++;
                     return;
                  }

                  $emoji = '<:gtfo:603609334781313037> ';
                  $msg = '_' . $msg . '_';

                  $clearcache++;
               }
            }

            $msg = '_' . substr($msg, 4) . '_' if ($msg =~ /^\/me /);

            if ( $steamid eq 'STEAM_0:0:19542618') # Mic-Chan
            {
               $emoji = ':mega:';
            }

            $final = $emoji . '`' . $nick . '`  ' . $msg;

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

my $fasttimer = IO::Async::Timer::Periodic->new(
   interval => 15,

   on_tick => sub ($)
   {
      DumpFile($$config{store}, $store) if $storechanged;
      $storechanged = 0;

      for (keys $$store{jail}->%*)
      {
         my $jailid = $_;

         unless (exists $$store{jail}{$_} && $$store{jail}{$_} > time)
         {
            $discord->remove_guild_member_role( $$config{discord}{guild_id}, $jailid, $$config{discord}{jail_role}, sub { $discord->send_message($$config{discord}{mainchan}, '<@'.$jailid.'> Was released from the jail.') } );
            delete $$store{jail}{$_};
            $storechanged = 1;
         }
      }

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

      my $day = (localtime(time))[6];

      if (!defined $$cache{day} || $day != $$cache{day})
      {
         $$cache{day} = $day;
         delete $$cache{today};
      }
   }
);
$fasttimer->start;

my $slowtimer = IO::Async::Timer::Periodic->new(
   interval => 7200,

   on_tick => sub ($)
   {
      for (keys $$cache{msgpair}->%*)
      {
         my $c = $_;

         for (keys $$cache{msgpair}{$c}->%*)
         {
            delete $$cache{msgpair}{$c}{$_} unless (exists $$cache{msgpair}{$c}{$_}{ts} && (($$cache{msgpair}{$c}{$_}{ts} + 259200) > time));
         }
      }
   }
);
$slowtimer->start;

my $loop = IO::Async::Loop::Mojo->new;

$loop->add($filestream);
$loop->add($fasttimer);
$loop->add($slowtimer);

$loop->run unless (Mojo::IOLoop->is_running);

close $fh;
$dbh->disconnect;
exit;

###

sub discord_on_message_create ()
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

         if ( $channel == $$config{discord}{linkchan} )
         {
            $msg =~ s/`//g;
            $msg =~ s/%/%%/g;
            if ( $msg =~ s/<@!?(\d+)>/\@$$users{'users'}{$1}{'username'}/g ) # user/nick # TODO: nick translation like below ($$member{'nick'})
            {
               $msg =~ s/(?:\R^)\@$$users{'users'}{$1}{'username'}/ >>> /m if ($1 == $$users{'id'}); # prob not needed anymore now that discord removed the weird quoting thing
            }
            $msg =~ s/(\R|\s)+/ /gn;
            $msg =~ s/<#(\d+)>/#$$guild{'channels'}{$1}{'name'}/g; # channel
            $msg =~ s/<@&(\d+)>/\@$$guild{'roles'}{$1}{'name'}/g; # role
            $msg =~ s/<a?(:[^:.]+:)\d+>/$1/g; # emoji

            return unless $msg;

            my $nick = defined $$member{'nick'} ? $$member{'nick'} : $$author{'username'};
            $nick =~ s/`//g;
            $nick =~ s/%/%%/g;
            $nick =~ s/(\R|\s)+/ /gn;

            open (my $tosvenfh, '>>:encoding(UTF-8)', $$config{'tosven'});

            # TODO: Make this work and add limit of 3 lines or something
            while ( $msg =~ /\G(.{0,126}(?:.\z))/sg )
            {
               say localtime(time) . " <- <$nick> $1";
               say $tosvenfh "(DISCORD) $nick: $1";

               $$cache{msgout}++;
            }

            close $tosvenfh;
         }
         elsif ( $msg =~ /^!player ([^\*]+)(\*)?$/i )
         {
            my $param   = $1;
            my $orderfl = ($2 ? 1 : 0);
            my ($stmt, @bind, $r);

            my $nsa;
            $nsa = 1 if ( $channel == $$config{discord}{ayayachan} || $channel == $$config{discord}{trashchan} );

            if ( $param =~ /^STEAM_(0:[01]:[0-9]+)/ )
            {
               $stmt = 'SELECT * FROM stats WHERE steamid = ? ORDER BY datapoints DESC, date(seen) DESC LIMIT 1';
               @bind = ( "$1" );
            }
            else
            {
               $stmt = 'SELECT * FROM stats WHERE name LIKE ? ORDER BY' . ($orderfl ? '' : ' datapoints DESC,') . ' date(seen) DESC LIMIT 1';
               @bind = ( "%$param%" );
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

               my $nickname = decode_utf8_lax($r->[2]);
               $nickname =~ s/$discord_markdown_pattern/\\$1/g;

               my $embed = {
                  'color' => randcol(),
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
                      'value'  => '**[' . $nickname . '](' . $$result{'response'}{'players'}->[0]{'profileurl'} . ' "' . $personaname . '")**',
                      'inline' => \1,
                    },
                    {
                       'name'   => 'Country',
                       'value'  => lc($r->[11]) eq 'il' ? ':flag_ps:' : ( lc($r->[11]) eq 'au' ? '<:ausgulag:916311826168422420>' : ':flag_'.($r->[11] ? lc($r->[11]) : 'white').':' ),
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
                       'value'  => $$cache{'STEAM_'.$r->[1]} ? 'Now!' : ((exists $$cache{today} && $$cache{today}{'STEAM_'.$r->[1]}) ? 'Today' : (defined $r->[16] ? $r->[16] : 'Unknown')),
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

               $discord->send_message( $channel, $message, sub { $$cache{msgpair}{$channel}{$msgid}{id} = shift->{id}; $$cache{msgpair}{$channel}{$msgid}{ts} = time } );
            }
            else
            {
                react( $channel, $msgid, 'red' );
            }
         }
         elsif ( $msg =~ /^!stat(us|su)/i && !($channel ~~ $$config{discord}{nocmdchans}->@*) )
         {
            $discord->start_typing( $channel, sub {
               my $infos = getstatus();

               unless ( defined $infos )
               {
                  if ( $$cache{mapchanges} && time - $$cache{mapchangetime} <= 30 )
                  {
                     react( $channel, $msgid, 'map' );
                     react( $channel, $msgid, 'change' );
                  }
                  else
                  {
                     react( $channel, $msgid, 'pepe' );
                  }
               }
               else
               {
                  my ($d, $a, $t) = ('', '', '');
                  $d = 'Difficulty: **' . ($1+0) . '%**  ' if ( $$infos{'sname'} =~ /diff(?:iculty)?: (.+)%/ );
                  $a = ', Attempt: **#' . ($retries+1) . '**' if $retries;
                  $t = '(started **' . duration(time-$maptime) . "** ago$a) " if ($maptime && $$infos{'players'});
                  my $message = "Map: **$$infos{'map'}** $t ${d}Players: **$$infos{'players'}**/$$infos{'max'}";

                  $discord->send_message( $channel, $message, sub { $$cache{msgpair}{$channel}{$msgid}{id} = shift->{id}; $$cache{msgpair}{$channel}{$msgid}{ts} = time } );
               }
            });
         }
         elsif ( $msg =~ /^!w(?:eather)? ?(.+)?/i && !($channel ~~ $$config{discord}{nocmdchans}->@*) )
         {
            my ($alt, $flg, $loc, $lat, $lon, $tz) = (0, 'xx');

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
                  react( $channel, $msgid, 'red' );
                  return;
               }

               $loc = $input->{formatted_address};
               $lat = $input->{geometry}{location}{lat};
               $lon = $input->{geometry}{location}{lng};
               $alt = elev_by_coords($lat, $lon);
               $tz  = (tz_by_coords($lat, $lon))[0];

               unless ( $tz )
               {
                  react( $channel, $msgid, 'pepe' );
                  return;
               }

               my $found;

               for ($$input{address_components}->@*)
               {
                  if ('country' ~~ $$_{types}->@*)
                  {
                     $flg = lc($_->{short_name});
                     $found++;
                  }
               }

               $flg = cc_by_coords($lat, $lon) unless $found;

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
               'color' => randcol(),
               'provider' => {
                  'name' => 'met.no',
                  'url'  => 'https://www.met.no/',
                },
                'author' => {
                   'name'     => sprintf('Weather for %s', $loc),
                   'url'      => sprintf('https://www.google.com/maps/@%f,%f,13z', $lat, $lon),
                   'icon_url' => sprintf('https://distfiles.lifeisabug.com/circle-flags/flags/%s.png', $flg),
                },
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
                    'value'  => sprintf('%s, %.2g m/s from %s', $w->windspeed_bft_txt, $w->windspeed_ms, $w->windfrom_dir_utf8arrow),
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

            $discord->send_message( $channel, $message, sub { $$cache{msgpair}{$channel}{$msgid}{id} = shift->{id}; $$cache{msgpair}{$channel}{$msgid}{ts} = time } );
         }
         elsif ( $msg =~ /^!img ?(.+)?/i && $channel == $$config{discord}{vipchan})
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
               react( $channel, $msgid, 'pepe' );
               return;
            }
            my $i = decode_json ( $r->decoded_content );

            if ( defined $$i{success} && $$i{success} )
            {
               $discord->send_message( $channel, $$i{message} );
            }
            else
            {
               react( $channel, $msgid, 'pepe' );
            }
         }
         elsif ( $msg =~ /^!ud (.+)/i && $channel == $$config{discord}{mediachan} )
         {
            my $input = $1;
            my $query = uri_escape( $input );
            my $ua = LWP::UserAgent->new( agent => 'Mozilla/5.0', timeout => 3 );
            $ua->agent( ssl_opts => { verify_hostname => 0 } );
            my $r = $ua->get( "https://api.urbandictionary.com/v0/define?term=$query", 'Content-Type' => 'application/json', 'Accept-Encoding' => HTTP::Message::decodable );
            unless ( $r->is_success )
            {
               react( $channel, $msgid, 'pepe' );
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

                  $discord->send_message( $channel, "```asciidoc\n$res```", sub { $$cache{msgpair}{$channel}{$msgid}{id} = shift->{id}; $$cache{msgpair}{$channel}{$msgid}{ts} = time } );
               }
               else
               {
                  react( $channel, $msgid, 'red' );
               }
            }
            else
            {
               react( $channel, $msgid, 'pepe' );
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
               react( $channel, $msgid, 'pepe' );
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
                  'color' => randcol(),
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

               $discord->send_message( $channel, $message, sub { $$cache{msgpair}{$channel}{$msgid}{id} = shift->{id}; $$cache{msgpair}{$channel}{$msgid}{ts} = time } );
            }
            else
            {
               react( $channel, $msgid, 'red' );
            }
         }
         elsif ( $msg =~ /^((?:\[\s\]\s[^\[\]]+\s?)+)/ && !($channel ~~ $$config{discord}{nocmdchans}->@*) )
         {
            my @x;

            $msg =~ s/`//g;
            $msg =~ s/(\[\s\]\s[^\[\]]+)+?\s?/push @x,$1/eg;
            $x[int(rand(@x))] =~ s/\[\s\]/[x]/;

            $discord->send_message( $channel, join('', @x), sub { $$cache{msgpair}{$channel}{$msgid}{id} = shift->{id}; $$cache{msgpair}{$channel}{$msgid}{ts} = time } );
         }
         elsif ( $msg =~ /^!ping ([^.]+)(?:\.bsp)?/i && !($channel ~~ $$config{discord}{nocmdchans}->@*) )
         {
            my $map = lc($1);

            return unless (defined $map);
            if ( (exists $$store{pings}{$map} && exists $$store{pings}{$map}{$id}) || $map eq '_server_start')
            {
               react( $channel, $msgid, 'ia' );
               return;
            }

            my @maps = map { (fileparse($_, qr/\.[^.]*/))[0] } glob('/home/svends/sc5/svencoop*/maps/*.bsp');

            if ( $map ~~ @maps )
            {
               $$store{pings}{$map}{$id}++;
               $storechanged = 1;
               react( $channel, $msgid, 'green' );
            }
            else
            {
               react( $channel, $msgid, 'red' );
            }
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
                     react( $channel, $msgid, 'green' );
                  }
                  else
                  {
                     react( $channel, $msgid, 'red' );
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

                     react( $channel, $msgid, 'wait' );
                     $discord->send_message( $channel, "<\@$id> Within the next hour, join the twlz Sven Co-op server and type `!verify` in chat to verify your Steam ID." );
                  }
                  elsif ( exists $$store{steamidqueue}{$value} )
                  {
                     react( $channel, $msgid, 'wait' );
                  }
                  else
                  {
                     react( $channel, $msgid, 'red' );
                  }
               }
               else
               {
                  $$store{users}{$id}{$type} = $value;
                  $storechanged = 1;

                  react( $channel, $msgid, 'green' );
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
                  react( $channel, $msgid, 'red' );
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

                  $discord->send_message( $channel, $message );
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

                        react( $channel, $msgid, 'green' );
                     }
                  }
               }
            }
         }
         elsif ( $msg =~ /^!?rem(?:ind)?\s+(?:(?<target>[^\s-]+)\s+)?(?:(?:in|at)\s+)?(?:(?<mins>\d+)|(?:(?<year>\d{4})-?(?<month>\d\d)-?(?<day>\d\d)\s+)?(?<hm>\d?\d:\d\d))(?:\s+(?:(?:to|that)\s+)?(?<text>.+)?)?$/i )
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
                  react( $channel, $msgid, 'what' );
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
                  react( $channel, $msgid, 'what' );
                  return;
               }
            }

            unless ($target =~ /<@!?(\d+)>/)
            {
               react( $channel, $msgid, 'what' );
               return;
            }

            if ($time < time || $time > 7952342400)
            {
               react( $channel, $msgid, 'what' );
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
               react( $channel, $msgid, 'green' );
            }
            else
            {
               $discord->send_message( $channel, "<\@$id> <:greentick:712004372678049822> `Reminding you in: ". duration($time - time) . '`' );
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

            $tz = 'Etc/UTC' if ($tz =~ /^utc$/i);

            unless ( DateTime::TimeZone->is_valid_name($tz) )
            {
               my $geo = Geo::Coder::Google->new(apiver => 3, language => 'en', key => $$config{'gmapikey'});

               my $input;
               eval { $input = $geo->geocode(location => $tz) };

               unless ( $input )
               {
                  react( $channel, $msgid, 'red' );
                  return;
               }

               $loc = $input->{formatted_address};
               $tz  = (tz_by_coords($input->{geometry}{location}{lat}, $input->{geometry}{location}{lng}))[0];

               unless ( $tz )
               {
                  react( $channel, $msgid, 'pepe' );
                  return;
               }
            }

            my ($date, $time, $sname, $offset, $emoji, $m, $day, $month, $epoch, $week) = split(/#/, DateTime->now(time_zone => $tz)->strftime('%F#%T#%Z#%z#%l#%M#%A#%B#%s#%V'));
            $emoji =~ s/\s//g;
            $emoji .= '30' if ($m >= 30);

            my $embed = {
               'color' => randcol(),
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

            $discord->send_message( $channel, $message, sub { $$cache{msgpair}{$channel}{$msgid}{id} = shift->{id}; $$cache{msgpair}{$channel}{$msgid}{ts} = time } );
         }
         elsif ( $msg =~ /^!alpha (.+)/i && $channel != $$config{discord}{mainchan})
         {
            my $q = uri_escape($1);

            #react( $channel, $msgid, 'wait' );

            $discord->start_typing( $channel, sub {
               my @c = qw(A B C D E F G H I J K L M N O P Q R S T U V W X Y Z a b c d e f g h i j k l m n o p q r s t u v w x y z 0 1 2 3 4 5 6 7 8 9 _);
               my $tmp = '/tmp/XXXXXXXX.gif';
               $tmp =~ s/X/$c[int(rand(@c))]/ge;

               my $ua = LWP::UserAgent->new( timeout => 11 );
               my $r = $ua->get( 'http://api.wolframalpha.com/v1/simple?appid=' . $$config{waappid} . '&background=36393F&foreground=white&fontsize=22&width=760&units=metric&timeout=8&i=' . $q, 'Accept-Encoding' => HTTP::Message::decodable, ':content_file' => $tmp);
               unless ( $r->is_success && -s $tmp )
               {
                  #$discord->delete_all_reactions_for_emoji( $channel, $msgid, $$reactions{wait} );
                  react( $channel, $msgid, 'red' );
               }
               else
               {
                  my $args = {
                     'path' => $tmp,
                     'name' => ((split /\//, $tmp)[-1]),
                  };

                  #$discord->send_image( $channel, $args, sub { unlink $tmp if (-e $tmp); $discord->delete_all_reactions_for_emoji( $channel, $msgid, $$reactions{wait} ); $$cache{msgpair}{$channel}{$msgid}{id} = shift->{id}; $$cache{msgpair}{$channel}{$msgid}{ts} = time } );
                  $discord->send_image( $channel, $args, sub { unlink $tmp if (-e $tmp); $$cache{msgpair}{$channel}{$msgid}{id} = shift->{id}; $$cache{msgpair}{$channel}{$msgid}{ts} = time } );
               }
            });
         }
         elsif ( $msg =~ /^!bible ?((?:[0-9] )?[A-z]+)? ?(?:([0-9]+):([0-9]+))?/i )
         {
            my $book = $1;
            my $chapter = $2;
            my $verse = $3;

            my $r;

            unless ($1 && $2 && $3)
            {
               $r = get('https://bible-api.com/?random=verse&translation=kjv');
            }
            else
            {
               $r = get('https://bible-api.com/' . $book . '+' . $chapter . ':' . $verse . '?translation=kjv');
            }

            if (!$r || $r eq '"translation not found"' || $r eq '{"error":"not found"}')
            {
               react( $channel, $msgid, 'red' );
               return;
            }

            my $json = decode_json($r);
            $$json{verses}[0]{text} =~ s/\n/ /g;

            my $embed = {
               'color' => randcol(),
                'fields' => [
                 {
                    'name'   => $$json{verses}[0]{book_name} . ' ' . $$json{verses}[0]{chapter} . ':' . $$json{verses}[0]{verse},
                    'value'  => $$json{verses}[0]{text},
                    'inline' => \0,
                 }
                 ],
            };

            my $message = {
               'content' => '',
               'embed' => $embed,
            };

            $discord->send_message( $channel, $message, sub { $$cache{msgpair}{$channel}{$msgid}{id} = shift->{id}; $$cache{msgpair}{$channel}{$msgid}{ts} = time } );
         }
         elsif ( $msg =~ /^!help/i )
         {
            $discord->send_message( $channel, 'https://twlz.lifeisabug.com/gus', sub { $$cache{msgpair}{$channel}{$msgid}{id} = shift->{id}; $$cache{msgpair}{$channel}{$msgid}{ts} = time } );
         }
         elsif ( $msg =~ /^!([jb])ail <@!?(\d+)> ?([0-9]+)?/i && $id == $$config{discord}{owner_id} )
         {
            my $jailid = $2;

            if ($1 eq 'j')
            {
               unless ($3)
               {
                  react( $channel, $msgid, 'red' );
                  return;
               }

               my $jailmin = $3;

               $$store{jail}{$jailid} = time + $jailmin*60;
               $storechanged = 1;
               $discord->add_guild_member_role( $$config{discord}{guild_id}, $jailid, $$config{discord}{jail_role}, sub { $discord->send_message( $$config{discord}{jailchan}, '<@'.$jailid.'> You have been jailed for '.duration($jailmin*60).'.' ) } );
               react( $channel, $msgid, 'green' );
            }
            else
            {
               $$store{jail}{$jailid} = $storechanged = 1;
               react( $channel, $msgid, 'green' );
            }
         }
         elsif ( $msg =~ /^!uptime/i && !($channel ~~ $$config{discord}{nocmdchans}->@*) && $id == $$config{discord}{owner_id} )
         {
            my @files = sort {(stat($a))[9] <=> (stat($b))[9]} glob('/home/svends/sc5/svends.*.pid');

            my $embed = {
               'color' => randcol(),
                'title' => '**:chart_with_upwards_trend: Statistics**',
                'fields' => [
                 {
                    'name'   => 'Server Uptime',
                    'value'  => duration(uptime()),
                    'inline' => \1,
                 },
                 {
                    'name'   => 'Server LoadAVG',
                    'value'  => load(),
                    'inline' => \1,
                 },
                 {
                    'name'   => 'SvenDS Uptime',
                    'value'  => duration(time-(stat($files[-1]))[9]),
                    'inline' => \1,
                 },
                 {
                    'name'   => 'Gus Uptime',
                    'value'  => duration(time-$started),
                    'inline' => \1,
                 },
                 {
                    'name'   => 'Sess. Uptime',
                    'value'  => duration(time-$ready),
                    'inline' => \1,
                 },
                 {
                    'name'   => 'Conn. Uptime',
                    'value'  => duration(time-$resumed),
                    'inline' => \1,
                 },
                 {
                    'name'   => 'Session',
                    'value'  => '#' . $readyc,
                    'inline' => \1,
                 },
                 {
                    'name'   => 'Resumed',
                    'value'  => $resumedc . ' time' . ($resumedc == 1 ? '' : 's'),
                    'inline' => \1,
                 },
                 {
                    'name'   => 'Map Changes',
                    'value'  => $$cache{mapchanges} ? $$cache{mapchanges} : 0,
                    'inline' => \1,
                 },
                 {
                    'name'   => 'Relay Sent',
                    'value'  => $$cache{msgout} ? $$cache{msgout} : 0,
                    'inline' => \1,
                 },
                 {
                    'name'   => 'Relay Received',
                    'value'  => $$cache{msgin} ? $$cache{msgin} : 0,
                    'inline' => \1,
                 },
                 {
                    'name'   => 'Ghost Leavers',
                    'value'  => $$cache{ghosted} ? $$cache{ghosted} : 0,
                    'inline' => \1,
                 },
                 {
                    'name'   => 'Trolldeletes',
                    'value'  => $$cache{trolldeletes} ? $$cache{trolldeletes} : 0,
                    'inline' => \1,
                 },
                 ],
            };

            my $r = get('http://localhost:8811/metrics');

            if ( $r )
            {
               my $served = 0;
               $served = $1 if ($r =~ /^cloudflared_tunnel_response_by_code\{status_code="200"\} ([0-9]+)$/m);
               push $$embed{'fields'}->@*, { 'name' => 'FastDL Served', 'value' => $served, 'inline' => \1 }; 

               my ($total, $div) = (0, 1e+9);
               my @m = $r =~ /^quic_client_(?:sent|receive)_bytes\{conn_index="[0-9]+"\} (.+)$/gm;
               for (@m)
               {
                  $total += $_;
               }
               push $$embed{'fields'}->@*, { 'name' => 'FastDL Traffic', 'value' => sprintf('%.3g GB', $total/$div), 'inline' => \1 };
            }

            my $message = {
               'content' => '',
               'embed' => $embed,
            };

            $discord->send_message( $channel, $message, sub { $$cache{msgpair}{$channel}{$msgid}{id} = shift->{id}; $$cache{msgpair}{$channel}{$msgid}{ts} = time } );
         }
      }
   });

   return;
}

sub discord_on_message_delete ()
{
   $discord->gw->on('MESSAGE_DELETE' => sub ($gw, $hash)
   {
      my $msgid    = $hash->{'id'};
      my $channel  = $hash->{'channel_id'};

      if (exists $$cache{msgpair}{$channel}{$msgid}{id})
      {
         $discord->delete_message( $channel, $$cache{msgpair}{$channel}{$msgid}{id} );
         delete $$cache{msgpair}{$channel}{$msgid};
         $$cache{trolldeletes}++;
      }
   });

   return;
}

sub discord_on_guild_member_remove ()
{
   $discord->gw->on('GUILD_MEMBER_REMOVE' => sub ($gw, $hash)
   {
      my $msg = '<@'.$hash->{'user'}{'id'}.'> ('.$hash->{'user'}{'username'}.'#'.$hash->{'user'}{'discriminator'}.') has left the server.';
      $discord->send_message( $$config{discord}{mainchan}, $msg );
      $discord->send_message( $$config{discord}{trashchan}, $msg );
   });

   return;
}

###

sub discord_on_ready ()
{
   $discord->gw->on('READY' => sub ($gw, $hash)
   {
      $ready = $resumed = time;
      $readyc++;

      add_me($hash->{'user'});

      my $infos = getstatus();

      unless ( defined $infos )
      {
         $discord->status_update( { 'name' => 'Sven Co-op', type => 0 } );
      }
      else
      {
         $discord->status_update( { 'name' => 'SC on ' . $$infos{'map'}, type => 0 } );
         $lastmap = $$infos{'map'};
      }
   });

   return;
}

sub discord_on_guild_create ()
{
   $discord->gw->on('GUILD_CREATE' => sub ($gw, $hash)
   {
      $guild = $discord->get_guild($$config{'discord'}{'guild_id'});

      for (keys $$guild{'emojis'}->%*)
      {
         $$emojis{$$guild{emojis}{$_}{name}}{id}       = $_;
         $$emojis{$$guild{emojis}{$_}{name}}{animated} = $$guild{emojis}{$_}{animated};
      }
   });

   return;
}

sub discord_on_resumed ()
{
   $discord->gw->on('RESUMED' => sub ($gw, $hash)
   {
      $resumed = time;
      $resumedc++;
   });

   return;
}

sub add_me ($user)
{
   $$users{'id'} = $$user{'id'};
   add_user($user);

   return;
}

sub add_user ($user)
{
   $$users{'users'}{$$user{'id'}} = $user;

   return;
}

###

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

sub cc_by_coords ($lat, $lon)
{
   my $json = get('https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=' . $lat . '&lon=' . $lon);

   if ($json)
   {
      my $nomdata = decode_json($json);
      return lc($$nomdata{address}{country_code}) if (exists $$nomdata{address}{country_code});
   }

   return 'xx';
}

sub verify ($steamid)
{
   if ( defined $$store{steamidqueue}{$steamid} )
   {
      $discord->delete_all_reactions_for_emoji( $$store{steamidqueue}{$steamid}{chan}, $$store{steamidqueue}{$steamid}{msgid}, $$reactions{wait} );
      $discord->add_guild_member_role( $$config{discord}{guild_id}, $$store{steamidqueue}{$steamid}{discordid}, $$config{discord}{ver_role} );
      $discord->send_message( $$store{steamidqueue}{$steamid}{chan}, "<\@$$store{steamidqueue}{$steamid}{discordid}> <:greentick:712004372678049822> You have successfully validated your Steam ID! VIP status granted." );
      react( $$store{steamidqueue}{$steamid}{chan}, $$store{steamidqueue}{$steamid}{msgid}, 'green' );

      delete $$store{steamidqueue}{$steamid};
   }

   return;
}

sub getstatus ()
{
   my $if       = IO::Interface::Simple->new('ens3');
   my $addr     = $if->address;
   my $port     = $$config{'serverport'};
   my $ap       = "$addr:$port";
   my $encoding = term_encoding;

   my $q = Net::SRCDS::Queries->new(
      encoding => $encoding,
      timeout  => $maptime ? 0.5 : 0.25,
   );

   $q->add_server( $addr, $port );
   my $infos = $q->get_all;

   return $$infos{$ap}{'info'} if ( defined $$infos{$ap}{'info'} );
   return;
}

sub uptime ()
{
   open my $proc_uptime, '<', '/proc/uptime';
 
   my $line = <$proc_uptime>;
   my ($uptime) = $line =~ /^(\d+)/;

   return $uptime;
}
 
sub load ()
{
   open my $proc_loadavg, '<', '/proc/loadavg';
 
   my $line = <$proc_loadavg>;
   my ($load1, $load5, $load15) = $line =~ /^(\d+\.?\d*)\s+(\d+\.?\d*)\s+(\d+\.?\d*)/;

   return ($load1, $load5, $load15);
}

sub react ($channel, $msgid, $reaction)
{
   $discord->create_reaction( $channel, $msgid, $$reactions{$reaction} );
   return;
}

sub randcol ()
{
   my ($h, $s, $v) = (rand(360)/60, 0.5+rand(0.5), 0.9+rand(0.1));

   my $i = floor( $h );
   my $f = $h - $i;
   my $p = $v * ( 1 - $s );
   my $q = $v * ( 1 - $s * $f );
   my $t = $v * ( 1 - $s * ( 1 - $f ) );

   my ($r, $g, $b);

   if ( $i == 0 )
   {
      ($r, $g, $b) = ($v, $t, $p);
   }
   elsif ( $i == 1 )
   {
      ($r, $g, $b) = ($q, $v, $p);
   }
   elsif ( $i == 2 )
   {
      ($r, $g, $b) = ($p, $v, $t);
   }
   elsif ( $i == 3 )
   {
      ($r, $g, $b) = ($p, $q, $v);
   }
   elsif ( $i == 4 )
   {
      ($r, $g, $b) = ($t, $p, $v);
   }
   else
   {
      ($r, $g, $b) = ($v, $p, $q);
   }

   return hex(sprintf('0x%02x%02x%02x', int(floor($r*255)), int(floor($g*255)), int(floor($b*255))));
}

sub quit ($)
{
   if ($storechanged)
   {
      say "\n" . 'Saving $store because it had changes.';
      DumpFile($$config{store}, $store);
      say 'Done.';
   }
   else
   {
      say "\n" . 'Not saving $store, no changes were made.';
   }

   $discord->disconnect('Quit', 1000);
   say 'Disconnected.';

   exit;
}
