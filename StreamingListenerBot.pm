#!perl --

package StreamingListenerBot;

use strict;
use warnings;
use feature qw( say );

use AnyEvent::HTTP;
use AnyEvent::WebSocket::Client;

use JSON;
use URI::Escape;
use HTML::Entities;
use Regexp::Trie;

my $JSON = JSON->new;

####################################################
# ユーティリティ

my $eac;
{
	open(my $fh,"<","eac.json") or die "eac.json $!";
	local $/ = undef;
	$eac =  decode_json <$fh>;
	close($fh);
}
my $rt = Regexp::Trie->new;
while(my($k,$v)= each %$eac){
	my $sv = join '',map { chr( hex( $_ )) } split /-/,$k;
	if( $sv =~/[^0x00-0x7f]/ ){
		$rt->add($sv);
	}
}
my $reEmoji = $rt->regexp;


sub decodeHTML($){
	my($sv)=@_;
	my $b = "";
	my $last_end = 0;
	while( $sv =~ /<([^>]+)>/g ){
		my $tag = $1;
		my $start = $-[0];
		my $end = $+[0];
		
		my $length = $start - $last_end;
		$length and $b .= substr( $sv,$last_end,$length);
		$last_end = $end;

		if( $tag =~ m<^/p$>i ){
			$b .= "\n";
		}elsif( $tag =~ m<^br/?$>i ){
			$b .= "\n";
		}
	}
	my $length = length($sv) - $last_end;
	$length and $b .= substr( $sv,$last_end,$length);
	
	$b = decode_entities($b);
	$b =~ s/$reEmoji/ /g;
	$b =~ s/\s+/ /g;
	$b =~ s/^\s//;
	$b =~ s/\s$//;
	return $b;
}

######################################################
# ctor

sub new {
	my $class = shift;

	return bless {
		client	 => AnyEvent::WebSocket::Client->new,
		ping_interval => 60,
		last_message_received => time,
		last_connection_start => 0,
		last_ping_sent => time,
		@_,
	}, $class;
}

sub ping{
	my $self = shift;
	if( $self->{conn} ){
	#	say "sending ping.";
		$self->{last_ping_sent} = time;
		$self->{conn}->send( AnyEvent::WebSocket::Message->new(body=>"",opcode => 9) );
	}
}
sub pong{
	my $self = shift;
	if( $self->{conn} ){
		say "sending pong.";
		$self->{conn}->send( AnyEvent::WebSocket::Message->new(body=>"",opcode => 10) );
	}
}

sub on_timer{
	my $self = shift;
	my $now = time;

	if( $self->{conn} ){
#		if( $now - $self->{last_message_received} >= 60 ){
#			# ping応答が途切れているようなので、今の接続は閉じる
#			say "ping timeout.";
#			eval{
#				$self->{conn}->close;
#			};
#			$@ and warn $@;
#			undef $self->{conn};
#			# fall thru. そのまま作り直す
#		}else
		{
			if( $now - $self->{last_ping_sent} >= 10 ){
				# 定期的にpingを送る
				$self->ping;
			}
			# 再接続は必要ない
			return;
		}
	}

	$self->check_instance_information();
}

sub check_instance_information{
	my $self = shift;
	my $now = time;

	# 前回接続開始してから60秒以内は何もしない
	my $remain = $self->{last_connection_start} + 60 -$now;
	$remain > 0 and return say "waiting $remain seconds to restart connection.";

	$self->{last_connection_start} = $now;

	say "check_instance_information start.";

	### say $JSON->encode( $self->{config} );

	# get instance information
	http_request
		"GET" => "https://$self->{config}{instance}/api/v1/instance",
		timeout => 10,
		headers => {
			'Authorization', "Bearer $self->{config}{token_info}{access_token}",
		},
		sub {
		my($data,$headers)=@_;

		$self->{last_event_received} = time;

		(defined $data and length $data)
		or return say "HTTP error. $headers->{Status} $headers->{Reason}";

		my $instance_info = $self->{instance_info} = eval{ decode_json $data };
		$instance_info or die "could not get instance information\n";

		my $streaming_api = "wss://$self->{config}{instance}";
		if( $instance_info and $instance_info->{urls} and $instance_info->{urls}{streaming_api} ){
			$streaming_api = $instance_info->{urls}{streaming_api};
		}

		my $stream_url = $self->{stream_url} = "$streaming_api/api/v1/streaming/?access_token=$self->{config}{token_info}{access_token}&stream=$self->{stream}";
		say "stream_url=$stream_url";
		
		$self->start_stream();
	};
}

sub start_stream{
	my $self = shift;
	my $now = time;

	eval{
		$self->{client}->connect( $self->{stream_url} )->cb(sub{

			$self->{last_event_received} = time;
			
			my $conn = $self->{conn} = eval{ shift->recv };
			$@ and return warn "WebSocket error. $@";

			say "WebSocket connected.";

			$conn->on(each_message => sub {
				my($conn, $message) = @_;
				$self->{last_event_received} = time;

				if( $message->is_ping ){
					say "ping received.";
					$self->pong();
					return;
				}elsif( $message->is_pong ){
					say "pong received.";
					return;
				}

				#
				my $data = eval{ decode_json $message->body };
				$@ and warn $@;
				return if not $data or $data->{event} ne 'update';
				#
				my $status = eval{ $JSON->decode( $data->{payload} ) };
				$@ and warn $@;
				return if not $status;
				#
				$status->{reblog} and $status = $status->{reblog};
				#
				my $who = $status->{account};
				$self->{callback}( 
					decodeHTML($who->{display_name}),
					decodeHTML($status->{content})
				);
			});

			$conn->on(finish => sub {
				my($conn) = @_;
				$self->{last_event_received} = time;
				undef $self->{conn};
				say "WebSocket finished.";
			});

		});
	};
	$@ and warn "WebSocket error. $@";
}

1;
