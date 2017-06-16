#!perl --
use strict;
use warnings;
use Getopt::Long;
use JSON;
use URI::Escape;
use feature qw( say );
BEGIN{ push @INC,'.' }
use StreamingListenerBot;
use BouyomiSender;
use utf8;

binmode \*STDOUT,":encoding(utf8)";
binmode \*STDERR,":encoding(utf8)";


sub usage{
	my($err) = @_;
	$err and say $err;

	print <<"END";
(to create access_info.json)
usage: $0 -i instance-name -u user-mail-address -p password -c access_info.json
options:
  -i instance          : host name of instance
  -u user-mail-address : user mail address
  -p password          : user password
  -c config_file       : file to save instance-name,client_id,client_secret,access_token
  -v                   : verbose mode.

(to listen stream)
usage: $0 -t access_info.json -s stream-type
options:
  -c config_file  : file to load instance-name,client_id,client_secret,access_token
  -s stream-type  : comma-separated list of stream type. default is 'public:local'
  -v              : verbose mode.
  --bh host : host name or ip address of BouyomiChan
  --bp port : post number of BouyomiChan
END
	exit 1;
}

my $verbose=0;
my $opt_instance="";
my $opt_user="";
my $opt_password="";
my $opt_config="";
my $opt_stream="public:local";
my $opt_name="StreamToBouyomi";
my $opt_pid_file;
my $opt_bouyomi_host="127.0.0.1";
my $opt_bouyomi_port=50001;

GetOptions(
	"verbose:+"  => \$verbose,
	"instance=s" => \$opt_instance, 
	"user=s"   => \$opt_user,  
	"password|p=s"   => \$opt_password,  
	"config=s"   => \$opt_config,  
	"stream=s"   => \$opt_stream,  
	"name=s"   => \$opt_name,  
	"pid_file=s"   => \$opt_pid_file,  
	"bouyomi_host|bh=s"   => \$opt_bouyomi_host,  
	"bouyomi_port|bp=i"   => \$opt_bouyomi_port,  
) or usage "bad options.";

if( not $opt_config or not $opt_stream ){
	usage();
}

say "verbose=$verbose";
say "opt_instance=$opt_instance";
say "opt_user=$opt_user";
say "opt_config=$opt_config";
say "opt_stream=$opt_stream";

####################################################
# 認証してトークンをファイルに保存

sub postApi{
	my($path,$data)=@_;
	my $cmd = "curl -sS -X POST 'https://$opt_instance$path' --data '$data'";
	say $cmd;
	my $result = `$cmd`;
	say $result;
	$data = eval{ decode_json $result };
	if($@){
		say "could not parse JSON response. $@";
		exit 11;
	}elsif(not $data){
		say "missing JSON response. $@";
		exit 12;
	}
	return $data;
}

if( $opt_instance and $opt_user and $opt_password ){
	#
	say "register client '$opt_name' ...";
	my $data = "";
	$data .= "client_name=" . uri_escape($opt_name);
	$data .= "&redirect_uris=urn:ietf:wg:oauth:2.0:oob";
	$data .= "&scopes=read";
	my $client_info = postApi( "/api/v1/apps", $data );
	if( not $client_info->{client_id} or not $client_info->{client_secret} ){
		say "could not get client_id, client_secret.";
		exit 21;
	}

	#
	say "get access_token...";
	$data = "";
	$data .= "client_id=" . $client_info->{client_id};
	$data .= "&client_secret=" . $client_info->{client_secret};
	$data .= "&grant_type=password";
	$data .= "&username=" . uri_escape($opt_user);
	$data .= "&password=" . uri_escape($opt_password);
	my $token_info = postApi( "/oauth/token", $data );
	if( not $token_info->{access_token} ){
		say "could not get access_token.";
		exit 22;
	}
	
	if( not $opt_config ){
		say "token is NOT saved because configuration file name is not specified.";
		exit 31;
	}
	
	open(my $fh,">",$opt_config) or die "$opt_config : $!";
	print $fh encode_json { instance=>$opt_instance, client_info=>$client_info, token_info=>$token_info};
	close($fh) or die "$opt_config : $!";
	say "instance and client_id and access_token is saved to $opt_config.";
	exit;
}

####################################################
# 保存したトークンを読み込む

my $config;
{
	my $json;
	{
		open(my $fh,"<",$opt_config) or die "$opt_config : $!";
		local $/ = undef;
		$json = <$fh>;
		close($fh) or die "$opt_config : $!";
	}
	$config = eval{ decode_json $json };
	if($@){
		say "could not parse JSON data in $opt_config. $@";
		exit 42;
	}elsif( not $config ){
		say "missing config data.";
		exit 43;
	}
}



####################################################
# ボットオブジェクト

my $bouyomi = BouyomiSender->new( host=> $opt_bouyomi_host, port => $opt_bouyomi_port);
my $last_send_time = time;
sub bouyomi_send{
	my($talk)=@_;
	say $talk;
	$bouyomi->send($talk);
	$last_send_time = time;
}

my @bot;
my @check;
for my $stream ( split /,/,$opt_stream ){
	push @bot, StreamingListenerBot->new( 
		config=> $config, 
		stream=> $stream,
		callback=>sub{
			my($name,$message)=@_;

			return if not $message;

			my $talk = "${name}♪ ${message}";

			if( not grep {$_ eq $talk} @check ){
				push @check,$talk;
				shift @check if @check > 60;
				bouyomi_send($talk);
			}
		},
	);
}

@bot or die "no stream specified.";


###########################################################
# タイマー

my @idle_talk = qw(
	ねむい…
	おっぱいー♪ぷるっぷるっん♪まるいね,おおきいね,おっぱい
	ふーふりー♪ふらふー♪ふらー♪
	るーんー♪りーるー♪んーらー♪
);

my $timer = AnyEvent->timer(
	interval => 1 , 
	cb => sub {
		for my $bot(@bot){
			$bot->on_timer;
		}
		if( time - $last_send_time >= 10 ){
			if( @idle_talk and int rand 2 >= 1 ){
				bouyomi_send( $idle_talk[ int rand @idle_talk]);
			}elsif( @check ){
				bouyomi_send( $check[ int rand @check]);
			}
		}
	}
);

###########################################################
# シグナルハンドラ


my $c = AnyEvent->condvar;

my $signal_watcher_int = AnyEvent->signal(signal => 'INT',cb=>sub {
	say "signal INT";
	$c->broadcast;
});

my $signal_watcher_term = AnyEvent->signal(signal => 'TERM',cb=>sub {
	say "signal TERM";
	$c->broadcast;
});

my $signal_watcher_hup = AnyEvent->signal(signal => 'HUP',cb=>sub {
	say "signal HUP";
	## reload();
});

###########################################################

if( $opt_pid_file ){
	say "write pid file to $opt_pid_file";
	open(my $fh,">",$opt_pid_file) or die "$opt_pid_file $!";
	print $fh "$$";
	close($fh) or die "$opt_pid_file $!";
}

say "loop start.";
$c->wait;
say "loop end.";
exit 0;
