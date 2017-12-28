#!/usr/bin/env perl

# Gus - Discord bot for the twilightzone Sven Co-op server
#
# Based on https://github.com/vsTerminus/Goose
#
# Copyright 2017, Nico R. Wohlgemuth <nico@lifeisabug.com>

use v5.16.0;

use utf8;
use strict;
use warnings;

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

my $self;
my $lastmap = '';

my $config = {
   mainchan => "368487578028081154",
   chatlinkchan => "390586588897345540",
   fancystatuschan => "368487578028081154",
   adminrole => "368491069874241536",
   fromsven => "$ENV{HOME}/sc5/svencoop/scripts/plugins/store/_fromsven.txt",
   tosven => "$ENV{HOME}/sc5/svencoop/scripts/plugins/store/_tosven.txt",
   db => "$ENV{HOME}/scstats/scstats.db",
   steamapikey => "",
   steamapiurl => "http://api.steampowered.com/ISteamUser/GetPlayerSummaries/v0002/?key=XXXSTEAMAPIKEYXXX&steamids=",
   serverport => "27210",

   discord => {
     auto_reconnect => 1,
     client_id => "",
     name => "Gus",
     owner_id => "373912992758235148",
     game => "Sven Co-op @ twlz",
     token => "",
     verbose => 0,
   }
};

my $discord = Mojo::Discord->new(
   'version'   => '0.1',
   'url'       => "dummy",
   'token'     => $$config{'discord'}{'token'},
   'name'      => $$config{'discord'}{'name'},
   'reconnect' => $$config{'discord'}{'auto_reconnect'},
   'verbose'   => $$config{'discord'}{'verbose'},
   'game'      => $$config{'discord'}{'game'},
   'callbacks' => {
     'READY'          => sub { discord_on_ready(shift) },
     'GUILD_CREATE'   => sub { discord_on_guild_create(shift) },
     'MESSAGE_CREATE' => sub { discord_on_message_create(shift) },
   },
);

my $maps = {
   'hl_c01_a1' => '<:hl:369091257999294464> Half-Life',
   'of1a1' => '<:of:370226020982325250> Opposing Force',
   'ba_security1' => '<:bs:370225849426771979> Blue Shift',
   'escape_series_1a' => '<:sc:370225689514737665> Escape Series: Part 1',
   'escape_series_2a' => '<:sc:370225689514737665> Escape Series: Part 2',
   'escape_series_3a' => '<:sc:370225689514737665> Escape Series: Part 3',
   'etc' => '<:sc:370225689514737665> Earthquake Test Center',
   'etc2_1' => '<:sc:370225689514737665> Earthquake Test Center 2',
   'mistake_coop_a' => '<:sc:370225689514737665> Mistake Co-op',
   'po_c1m1' => '<:sc:370225689514737665> Poke 646',
   'po_c1m1' => '<:sc:370225689514737665> Poke 646: Vendetta',
   'rl02' => '<:sc:370225689514737665> Residual Life',
   'th_ep1_00' => '<:th:372377213779312640> They Hunger: Episode 1',
   'th_ep2_00' => '<:th:372377213779312640> They Hunger: Episode 2',
   'th_ep3_00' => '<:th:372377213779312640> They Hunger: Episode 3',
   'th_escape' => '<:th:372377213779312640> Woohoo, They Hunger: Escape',
   'road_to_shinnen' => '<:twlz:370619463038664705> Oh god, oh no, Road to Shinnen',
   'sc_tl_build_puzzle_fft_final' => '<:lul:370224421933285386> Build Puzzle',
};

###

my $dbh = DBI->connect("dbi:SQLite:$$config{'db'}", undef, undef, {
   RaiseError => 1,
   sqlite_open_flags => SQLITE_OPEN_READONLY,
});

$discord->init();

open my $fh, "<", $$config{'fromsven'} or die;

my $filestream = IO::Async::FileStream->new(
   read_handle => $fh,
   interval => 0.5,

   on_initial => sub {
      my ( $self ) = @_;
      $self->seek_to_last( "\n" );
   },

   on_read => sub {
      my ( $self, $buffref ) = @_;

      while ( $$buffref =~ s/^(.*\n)// ) {
         my $line = $1;

         chomp( $line );

         if ( $line =~ /^status .+ [0-9]+$/ )
         {
            say localtime(time) . " -> status: $line";

            my @data = split( ' ', $line );

            my $embed = {
               'color' => '15844367',
               'provider' => {
                  'name' => 'twlz',
                  'url' => 'http://twlz.lifeisabug.com',
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
             $discord->send_message( $$config{'fancystatuschan'}, "**$$maps{$data[1]}** campaign has started with **$data[2]** players!" ) if ( exists $$maps{$data[1]} && $lastmap ne $data[1] );

             $lastmap = $data[1];
          }
          elsif ( $line =~ /^map (.+)$/ )
          {
             say localtime(time) . " -> $line";

             $discord->status_update( { 'game' => "$1 @ twlz Sven Co-op" } );
          }
          else
          {
             say localtime(time) . " -> $line";

             $line =~ s/`//g;
             $line =~ s/^<(.+)><STEAM_0.+> (.+)/`$1`  $2/g;
             $line =~ s/\@ADMINS?/<@&$$config{'adminrole'}>/gi;

             $discord->send_message( $$config{'chatlinkchan'}, $line );
          }
      }
      return 0;
   }
);

my $loop = IO::Async::Loop::Mojo->new();
$loop->add( $filestream );
$loop->run;

close $fh;
$dbh->disconnect;

###

sub discord_on_ready
{
   my ($hash) = @_;
   add_me($hash->{'user'});
   say localtime(time) . " Connected to Discord.";
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
   my $channel = $hash->{'channel_id'};
   my @mentions = @{$hash->{'mentions'}};

   foreach my $mention ( @mentions )
   {
      add_user( $mention );
   }

   unless ( exists $author->{'bot'} && $author->{'bot'} )
   {
      if ( $channel eq $$config{'chatlinkchan'} )
      {
         $msg =~ s/`//g;
         $msg =~ s/%/%%/g;
         $msg =~ s/<@(\d+)>/\@$self->i{'users'}->{$1}->{'username'}/g; # user/nick
         $msg =~ s/<#(\d+)>/#$self->{'channelnames'}->{$1}/g; # channel
         $msg =~ s/<@&(\d+)>/\@$self->{'rolenames'}->{$1}/g; # role
         $msg =~ s/<(:.+:)\d+>/$1/g; # emoji

         say localtime(time) . " <- <$$author{'username'}> $msg";

         open (my $tosvenfh, '>>:encoding(UTF-8)', $$config{'tosven'}) or die;
         say $tosvenfh "(DISCORD) $$author{'username'}: $msg";
         close $tosvenfh;
      }
      elsif ( $channel eq $$config{'mainchan'} && $msg =~ /^!player (.+)/i )
      {
         my $param = $1;
         my ($stmt, @bind, $r);

         if ( $param =~ /^STEAM_(0:[0-9]:[0-9]+)$/ )
         {
            $stmt = "SELECT * FROM stats WHERE steamid = ? ORDER BY score DESC LIMIT 1";
            @bind = ( "$1" );
         }
         else
         {
            $stmt = "SELECT * FROM stats WHERE name LIKE ? ORDER BY score DESC LIMIT 1";
            @bind = ( "%$1%" );
         }

         $r = $dbh->selectrow_arrayref( $stmt, {}, @bind );

         if ( defined $r )
         {
            (my $url = $$config{'steamapiurl'} . $r->[0] ) =~ s/XXXSTEAMAPIKEYXXX/$$config{'steamapikey'}/;
            my $content = get( $url );

            unless ( defined $content )
            {
               $discord->send_message( $channel, "`Couldn't query Steam API`" );
               return;
            }
 
            my $result = decode_json( $content );

             my $embed = {
                'color' => '15844367',
                'provider' => {
                   'name' => 'twlz',
                   'url' => 'http://twlz.lifeisabug.com',
                },
                'thumbnail' => {
                   'url' => $$result{'response'}{'players'}->[0]{avatarfull},
                },
                'fields' => [
                   {
                      'name'   => 'Name',
                      'value'  => "**[".$r->[2]."](".$$result{'response'}{'players'}->[0]{'profileurl'}." \"$$result{'response'}{'players'}->[0]{personaname}\")**",
                      'inline' => \1,
                   },
                   {
                      'name'   => 'Country',
                      'value'  => ":flag_".lc($r->[11]).":",
                      'inline' => \1,
                   },
                   {
                      'name'   => 'Time played on TWLZ',
                      'value'  => duration( $r->[14]*30 ),
                      'inline' => \1,
                   },
                   {
                      'name'   => 'Last Seen',
                      'value'  => defined $r->[16] ? $r->[16] : 'Unknown',
                      'inline' => \1,
                   },
                   {
                      'name'   => 'Score',
                      'value'  => int($r->[4]),
                      'inline' => \1,
                   },
                   {
                      'name'   => 'Deaths',
                      'value'  => $r->[6],
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
         else
         {
             $discord->send_message( $channel, "`No results`" );
         }
      }
      elsif ( $channel eq $$config{'mainchan'} && $msg =~ /^!status/i )
      {
         my $if       = IO::Interface::Simple->new('lo');
         my $addr     = $if->address;
         my $port     = $$config{'serverport'};
         my $ap       = "$addr:$port";
         my $encoding = term_encoding;

         my $q = Net::SRCDS::Queries->new(
            encoding => $encoding,
            timeout  => 0.15,
         );

         $q->add_server( $addr, $port );
         my $infos = $q->get_all;

         unless ( defined $$infos{$ap}{'info'} )
         {
            $discord->send_message( $channel, "`Couldn't query server`" );
         }
         else
         {
            $discord->send_message( $channel, "Map: **$$infos{$ap}{'info'}{'map'}**  Players: **$$infos{$ap}{'info'}{'players'}/$$infos{$ap}{'info'}{'max'}**" );
         }
      }
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

sub duration {
   my $sec = shift;

   my @gmt = gmtime($sec);

   $gmt[5] -= 70;
   return   ($gmt[5] ?                                                       $gmt[5].'y' : '').
            ($gmt[7] ? ($gmt[5]                                  ? ' ' : '').$gmt[7].'d' : '').
            ($gmt[2] ? ($gmt[5] || $gmt[7]                       ? ' ' : '').$gmt[2].'h' : '').
            ($gmt[1] ? ($gmt[5] || $gmt[7] || $gmt[2]            ? ' ' : '').$gmt[1].'m' : '');
            ($gmt[0] ? ($gmt[5] || $gmt[7] || $gmt[2] || $gmt[1] ? ' ' : '').$gmt[0].'s' : '');
}
