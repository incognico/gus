#!/usr/bin/env perl

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

use Data::Dumper;
use IO::Async::Loop::Mojo;
use Mojo::Discord;
use OpenAI::API::Request::Chat;

my ($guild, $users, $started, $ready, $readyc, $resumed, $resumedc)
=  (undef,  undef,  time,     0,      0,       0,        0        );
my ($gptres, $chat);

my $config = {
   discord => {
      gptchan  => 1167503883338268732,
      owner_id => 540067740594077698,
      guild_id => 458323696910598165,
   }
};

my $gptconfig = OpenAI::API::Config->new(
   api_key => 'sk-XXX',
   api_base => 'https://api.openai.com/v1',
   timeout  => 60,
   retry    => 3,
   sleep    => 2,
);

my $discord = Mojo::Discord->new(
   'version'   => '9999',
   'url'       => 'https://twlz.lifeisabug.com',
   'token'     => '',
   'reconnect' => 1,
   'verbose'   => 1,
   'logdir'    => "$ENV{HOME}/gus",
   'logfile'   => 'discord_gpt.log',
   'loglevel'  => 'info',
);

###

discord_on_ready();
discord_on_guild_create();
discord_on_resumed();
discord_on_message_create();

$discord->init();

my $loop = IO::Async::Loop::Mojo->new;

$loop->run unless (Mojo::IOLoop->is_running);

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

         if ($channel == $$config{discord}{gptchan} && ($msg =~ /^<@1167502883839819777> +?(.+)/ || $msg =~ /^<@&1167503499622363169> +?(.+)/))
         {
            my $in = $1;

            say "<$$author{username}> $in\n";

            my $res;
            $res = gptreq('<@' . $$author{id} . '>: ' . $in, 0);
            next if $@;

            if ($res) {
               say ">> $res\n";
               #my $send = '<@' . $$author{id} . '> ' . $res;
               my $send = $res;
               my @out = split(/\G(.{1,1500})(?=\n|\z)/s, $send);
               if (scalar(@out) > 1) {
                  $discord->send_message_content_blocking( $$config{discord}{gptchan}, $_ ) for @out;
               }
              else {
                  $discord->send_message( $$config{discord}{gptchan}, $send );
               }
            }
         }
      }
   });

   return;
}

###

sub gptreq($m, $sys) {
   unless ($gptres) {
      $chat = OpenAI::API::Request::Chat->new(
         config => $gptconfig,
         model  => 'gpt-3.5-turbo',
         max_tokens => 420,
         messages => [
            { role => $sys ? 'system' : 'user', content => $m },
         ],
      );

      eval { $gptres = $chat->send(); };
   }
   else {
      eval { $gptres = $chat->send_message($m); };
   }

   return 0 if $sys;

   if ($@) {
      say "$@";
      undef $gptres;
      sysmsg();
      return (split /\n/, $@)[0] . ' GPT reset, new session initiated, previous context and role is now forgotten.';
   }

   return $gptres->{choices}[0]{message}{content};
}

sub sysmsg() {
   gptreq('You are a bot named Paul in a Discord chat channel. Extensively make use of Markdown syntax. Subtly use Emojis when appropriate. The currently speaking user name will be in front of every input prompt, remember the names and reference the user accordingly.', 1);
}

sub discord_on_ready ()
{
   $discord->gw->on('READY' => sub ($gw, $hash)
   {
      $ready = $resumed = time;
      $readyc++;

      add_me($hash->{'user'});

      $discord->status_update( { 'name' => 'GPT-3.5', type => 0 } );
   });

   return;
}

sub discord_on_guild_create ()
{
   $discord->gw->on('GUILD_CREATE' => sub ($gw, $hash)
   {
      $guild = $discord->get_guild($$config{'discord'}{'guild_id'});

      sysmsg();
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

sub quit ($)
{
   exit;
}
