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
use OpenAI::API::Request::Completion;
use OpenAI::API::Request::Image::Generation;
use LWP::Simple;
use File::Temp ':POSIX';
use File::Basename;
use Encode::Simple qw(encode_utf8_lax decode_utf8_lax);

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

         if ($channel == $$config{discord}{gptchan})
         {
            if ($msg =~ /^<@1167502883839819777> +?genimg (.+)/ || $msg =~ /^<@&1167503499622363169> +?genimg (.+)/) {
               return 0; # disabled for now

               say "IMAG <$$author{username}> genimg $1\n";

               my $request = OpenAI::API::Request::Image::Generation->new(
                  config => $gptconfig,
                  prompt => $1,
                  size => '512x512',
               );

               my $res;

               eval { $res = $request->send(); };

               if ($@) {
                  $discord->create_reaction( $channel, $msgid, ':redtick:712004372707541003' );
                  return;
               }

               my $url = $res->{data}->[0]{url};
               my $file = tmpnam() . '.png';
               my $dl = getstore($url, $file);

               $msg =~ s/^<@&?[0-9]+> +?genimg //i;

               say "IMAG >> [$msg]\n";

               my $txt = encode_utf8_lax($msg.':');

               $discord->send_image( $$config{discord}{gptchan}, { path => $file, name => basename($file), content => $txt }, sub { unlink $file }  );
            }
            elsif ($msg =~ /^<@1167502883839819777> +?COMP(?:LETE)?\s+(.+)/is || $msg =~ /^<@&1167503499622363169> +?COMP(?:LETE)?\s+(.+)/is) {
               my $in = $1;

               chomp($in);

               say "COMP <$$author{username}> $in\n";

               my $res;
               $res = gptreq2($in);

               if ($res) {
                  $res =~ s/\n\n/\n/g;
                  $res =~ s/^\s+//;
                  say "COMP >> $res\n";
                  my $send = '<@' . $$author{id} . '>: ' . $res;
                  my @out = split(/\G(.{1,1500})(?=\n|\z)/s, $send);
                  if (scalar(@out) > 1) {
                     $discord->send_message_content_blocking( $$config{discord}{gptchan}, $_ ) for @out;
                  }
                 else {
                     $discord->send_message( $$config{discord}{gptchan}, $send );
                  }
               }
            }
            elsif ($msg =~ /^<@1167502883839819777>\s+?(.+)/s || $msg =~ /^<@&1167503499622363169>\s+?(.+)/s) {
               my $in = $1;

               chomp($in);

               say "CHAT <$$author{username}> $in\n";

               my $res;
               $res = gptreq('<@' . $$author{id} . '>: ' . $in, 0);

               if ($res) {
                  $res =~ s/^\s+//;
                  say "CHAT >> $res\n";
                  my $send = $res;
                  $send =~ s/^@// if ($send =~ /^@<@/);
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
         max_tokens => 768,
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
      my $err = (split /\n/, $@)[0];
      say "$@";
      undef $gptres;
      sysmsg();
      return $err . ' GPT reset, new session initiated, previous context and role is now forgotten.';
   }

   return $$gptres{choices}[0]{message}{content};
}

sub sysmsg() {
   gptreq("You are a bot named Paul in a Discord chat channel. Excessively use Markdown for text formatting. Subtly use Emojis when appropriate. The currently speaking user name will be in front of every input prompt, remember the name and reference the user accordingly. You are rhetorically well versed, playful, joking and a little philosphical. Replace common adjectives with their more eloquent alternatives, but don't overdo it.", 1);
}

sub gptreq2($m) {
   my $comp = OpenAI::API::Request::Completion->new(
      config => $gptconfig,
      model  => 'gpt-3.5-turbo-instruct',
      max_tokens => 1488,
      prompt => $m,
   );

   my $res;
   eval { $res = $comp->send(); };

   if ($@) {
      say "$@";
      return (split /\n/, $@)[0];
   }

   return $$res{choices}[0]{text};
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
