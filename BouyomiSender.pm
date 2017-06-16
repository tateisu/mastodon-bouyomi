package BouyomiSender;
use strict;
use warnings;
use Encode;
use AnyEvent::Socket;
use feature qw( say );

my $UTF8 = Encode::find_encoding( "utf8" );

sub new {
	my $class = shift;

	return bless {
		@_,
	}, $class;
}

sub send{
	my($self,$message)=@_;
	
	# UTF-8 encode
	$message = $UTF8->encode( $message );
	
	my $speed = -1;  # 速度: -1=画面上の設定値。それ以外=マニュアル指定 有効範囲は50-300
	my $tone  = -1;  # 音程: -1=画面上の設定値。それ以外=マニュアル指定 有効範囲は50-200
	my $volume = -1; # 音量: -1=画面上の設定値。それ以外=マニュアル指定 有効範囲は0-100
	my $voice  = 0;   # 声質: 0:棒読みちゃん画面上の設定、1:女性1、2:女性2、3:男性1、4:男性2、5:中性、6:ロボット、7:機械1、8:機械2、10001～:SAPI5

	my $data = pack("vvvvvCV"
		,1 # [0-1]  (16Bit) コマンド          （ 0:メッセージ読み上げ）
		,$speed
		,$tone
		,$volume
		,$voice
		,0 # 文字コード種別 0:UTF-8, 1:Unicode, 2:Shift-JIS
		,length $message # エンコードされた文字列のバイト長
	). $message;

	tcp_connect $self->{host},$self->{port},sub{
		my($fh) = @_;
		if(not $fh){
			say "BouyomiSender: TCP connection failed. $self->{host},$self->{port} $!\n";
		}else{
			my $handle = new AnyEvent::Handle( fh => $fh );
			$handle->push_write($data);
			$handle->on_drain(sub{ undef $handle; });
		}
	};
}

1;
__END__
   
		default:
			printf("使用法1>BouyomiChanSample 文章\r\n");
			printf("使用法2>BouyomiChanSample 速度(50-300) 音程(50-200) 音量(0-100) 声質(0-8) 文章\r\n");
			return -1;
	//送信するデータの生成(文字列を除いた先頭の部分)
	char buf[15];
	*((short*)&buf[0])  = 0x0001; 
	*((short*)&buf[2])  = speed;  //[2-3]  (16Bit) 速度              （-1:棒読みちゃん画面上の設定）
	*((short*)&buf[4])  = tone;   //[4-5]  (16Bit) 音程              （-1:棒読みちゃん画面上の設定）
	*((short*)&buf[6])  = volume; //[6-7]  (16Bit) 音量              （-1:棒読みちゃん画面上の設定）
	*((short*)&buf[8])  = voice;  //[8-9]  (16Bit) 声質              （ 0:棒読みちゃん画面上の設定、1:女性1、2:女性2、3:男性1、4:男性2、5:中性、6:ロボット、7:機械1、8:機械2、10001～:SAPI5）
	*((char* )&buf[10]) = 2;      //[10]   ( 8Bit) 文字列の文字コード（ 0:UTF-8, 1:Unicode, 2:Shift-JIS）
	*((long* )&buf[11]) = len;    //[11-14](32Bit) 文字列の長さ
	
	//接続先指定用構造体の準備
	server.sin_addr.S_un.S_addr = inet_addr("127.0.0.1");
	server.sin_port             = htons(50001);
	server.sin_family           = AF_INET;

	//Winsock2初期化
	WSAStartup(MAKEWORD(1, 1), &wsadata);

	//ソケット作成
	sock = socket(AF_INET, SOCK_STREAM, 0);

	//サーバに接続
	connect(sock, (struct sockaddr *)&server, sizeof(server));

	//データ送信
	send(sock, buf, 15, 0);
	send(sock, msg, len, 0);

	//ソケット終了
	closesocket(sock);
	
	//Winsock2終了
	WSACleanup();
	
